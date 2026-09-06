#!/usr/bin/env -S nu --no-config-file

def fail [message: string, code: int = 1] {
  print --stderr $"error: ($message)"
  exit $code
}

def variants [requested: string] {
  if $requested == 'all' {
    return ['base', 'dev']
  }
  if $requested in ['base', 'dev'] {
    return [$requested]
  }
  fail $"unknown variant ($requested); expected base, dev, or all" 2
}

def publication-variants [requested: string, release_variant: string] {
  if $requested == 'all' {
    return [$release_variant]
  }
  if $requested != $release_variant {
    fail $"release tag selects ($release_variant), not ($requested)"
  }
  [$requested]
}

def parse-release-tag [release_tag: string] {
  let parsed = (
    $release_tag
    | parse --regex '^archlinux/(?<variant>base|dev)-(?<date>[0-9]{4}[.][0-9]{2}[.][0-9]{2})-(?<sequence>[1-9][0-9]*)$'
  )
  if ($parsed | is-empty) {
    fail $"invalid release tag ($release_tag); expected archlinux/base-YYYY.MM.DD-N or archlinux/dev-YYYY.MM.DD-N"
  }

  let release = ($parsed | first)
  let normalized_date = try {
    $release.date
    | into datetime --format '%Y.%m.%d'
    | format date '%Y.%m.%d'
  } catch {
    ''
  }
  if $normalized_date != $release.date {
    fail $"invalid release date ($release.date)"
  }

  {
    tag: $release_tag
    variant: $release.variant
    date: $release.date
    sequence: ($release.sequence | into int)
    version: $"($release.date)-($release.sequence)"
  }
}

def validate-release-sequence [variant: string, date: string, tags: list<string>] {
  let pattern = (
    '^archlinux/VARIANT-DATE-(?<sequence>[1-9][0-9]*)$'
    | str replace 'VARIANT' $variant
    | str replace 'DATE' $date
  )
  let sequences = (
    $tags
    | each {|tag|
        let parsed = ($tag | parse --regex $pattern)
        if ($parsed | is-empty) {
          fail $"malformed release tag ($tag) in the ($variant) ($date) series"
        }
        $parsed.0.sequence | into int
      }
    | uniq
    | sort
  )
  for entry in ($sequences | enumerate) {
    let expected = $entry.index + 1
    if $entry.item != $expected {
      fail $"release sequence for ($variant) ($date) skips ($expected)"
    }
  }
  $sequences
}

def local-release-tags [variant: string, date: string] {
  ^git tag --list $"archlinux/($variant)-($date)-*"
  | lines
  | where {|tag| not ($tag | is-empty) }
}

def remote-release-tags [variant: string, date: string] {
  let result = (
    ^git ls-remote --tags --refs origin $"refs/tags/archlinux/($variant)-($date)-*"
    | complete
  )
  if $result.exit_code != 0 {
    print --stderr ($result.stderr | str trim)
    exit $result.exit_code
  }
  $result.stdout
  | lines
  | where {|line| not ($line | is-empty) }
  | each {|line|
      $line
      | split row (char tab)
      | last
      | str replace 'refs/tags/' ''
    }
}

def context [revision_default: string] {
  let snapshot = (open --raw src/archlinux/VERSION | str trim)
  let release_tag = ($env.RELEASE_TAG? | default '')
  let release = if ($release_tag | is-empty) {
    null
  } else {
    parse-release-tag $release_tag
  }
  {
    image: ($env.IMAGE? | default 'ghcr.io/dbent/archlinux')
    snapshot: $snapshot
    release: $release
    version: (if $release == null { 'local' } else { $release.version })
    revision: ($env.REVISION? | default $revision_default)
  }
}

def validate-revision [revision: string] {
  if not ($revision | is-empty) and not ($revision =~ '^[0-9a-f]{40,64}$') {
    fail 'REVISION must be a full hexadecimal Git object ID'
  }
}

def markdown-files [] {
  ^git ls-files --cached --others --exclude-standard -- '*.md'
  | lines
  | where {|file| not ($file | is-empty) and ($file | path exists) }
}

def validate-source [] {
  let snapshot = (open --raw src/archlinux/VERSION | str trim)
  if not ($snapshot =~ '^[0-9]{8}$') {
    fail $"invalid Arch snapshot ($snapshot); expected YYYYMMDD"
  }

  let snapshot_path = $"(
    $snapshot | str substring 0..3
  )/($snapshot | str substring 4..5)/(
    $snapshot | str substring 6..7
  )"
  let containerfile = 'src/archlinux/Containerfile'
  let content = (open --raw $containerfile)
  let upstream = (
    $content
    | lines
    | where {|line| $line starts-with 'ARG ARCH_IMAGE=' }
  )
  if ($upstream | length) != 1 {
    fail 'malformed pinned Arch image'
  }
  let image_pattern = 'ARG ARCH_IMAGE=docker[.]io/archlinux/archlinux:base-(?<snapshot>[0-9]{8})[.]0[.][0-9]+@sha256:[0-9a-f]{64}'
  let image_match = (
    $upstream | first | parse --regex $"^($image_pattern)$"
  )
  if ($image_match | is-empty) {
    fail 'malformed pinned Arch image'
  }
  if $image_match.0.snapshot > $snapshot {
    fail $"upstream image is newer than Archive snapshot ($snapshot)"
  }

  let lines = ($content | lines)
  let archive = $"archive.archlinux.org/repos/($snapshot_path)/"
  if not ($content | str contains $archive) {
    fail 'Archive snapshot does not match the Arch version'
  }
  if not ($lines | any {|line| $line == 'FROM ${ARCH_IMAGE} AS base' }) {
    fail 'base stage does not use the pinned Arch image'
  }
  if not ($lines | any {|line| $line == 'FROM base AS dev' }) {
    fail 'dev stage does not extend base'
  }
  if ($lines | any {|line| $line =~ '^FROM .* AS ci$' }) {
    fail 'unexpected ci stage'
  }
}

def "main format" [] {
  let markdown = (markdown-files)
  if not ($markdown | is-empty) {
    ^rumdl fmt ...$markdown
  }
  ^just --unstable --fmt
}

def "main validate" [] {
  validate-source
  ^just --unstable --fmt --check

  ^nu --no-config-file bin/containers.nu build
  ^nu --no-config-file bin/containers.nu smoke

  let values = (context 'local')
  let lint_image = $"($values.image):dev-($values.version)"
  (
    ^podman run --rm
      --volume $"((pwd)):/src:ro"
      --workdir /src
      $lint_image
      nu --no-config-file bin/containers.nu lint
  )
}

def "main lint" [] {
  validate-source
  ^just --unstable --fmt --check

  let markdown = (markdown-files)
  if not ($markdown | is-empty) {
    ^rumdl check --no-cache ...$markdown
  }
  ^reuse --no-multiprocessing lint
  ^actionlint .github/workflows/containers.yml
}

def "main clean" [] {
  rm --recursive --force dst .tmp
}

def "main update-arch" [snapshot: string] {
  let normalized = if $snapshot =~ '^[0-9]{8}$' {
    try {
      $snapshot
      | into datetime --format '%Y%m%d'
      | format date '%Y%m%d'
    } catch {
      ''
    }
  } else {
    ''
  }
  if $normalized != $snapshot {
    fail $"invalid snapshot ($snapshot); expected a real YYYYMMDD date"
  }

  let snapshot_path = $"(
    $snapshot | str substring 0..3
  )/($snapshot | str substring 4..5)/(
    $snapshot | str substring 6..7
  )"
  let archive = $"archive.archlinux.org/repos/($snapshot_path)/"
  let archive_result = (
    ^curl --fail --silent --output /dev/null --head
      $"https://($archive)core/os/x86_64/core.db"
    | complete
  )
  if $archive_result.exit_code != 0 {
    fail $"Arch snapshot ($snapshot) is unavailable"
  }

  let response = (
    ^curl --fail --silent --show-error --get
      --data-urlencode $"name=base-($snapshot).0."
      --data-urlencode page_size=100
      https://hub.docker.com/v2/repositories/archlinux/archlinux/tags
    | complete
  )
  if $response.exit_code != 0 {
    print --stderr ($response.stderr | str trim)
    exit $response.exit_code
  }
  let entries = (
    $response.stdout
    | from json
    | get results
    | where {|result|
        let name_matches = (
          $result.name =~ $"^base-($snapshot)[.]0[.][0-9]+$"
        )
        let digest_matches = (
          ($result.digest? | default '') =~ '^sha256:[0-9a-f]{64}$'
        )
        $name_matches and $digest_matches
      }
    | each {|result|
        {
          name: $result.name
          digest: $result.digest
          job: ($result.name | split row '.' | last | into int)
        }
      }
  )
  if ($entries | is-empty) {
    fail $"no upstream Arch image found for ($snapshot)"
  }
  let entry = ($entries | sort-by job | last)

  let containerfile = 'src/archlinux/Containerfile'
  let version_file = 'src/archlinux/VERSION'
  let upstream = $"docker.io/archlinux/archlinux:($entry.name)@($entry.digest)"
  let current_version = (open --raw $version_file | str trim)
  let content = (open --raw $containerfile)

  let image_is_current = (
    $content | lines | any {|line| $line == $"ARG ARCH_IMAGE=($upstream)" }
  )
  let archive_is_current = ($content | str contains $archive)
  let version_is_current = $current_version == $snapshot
  if $image_is_current and $archive_is_current and $version_is_current {
    print $"Arch inputs are already current for ($snapshot)"
    return
  }

  let lines = ($content | lines)
  let image_count = (
    $lines | where {|line| $line starts-with 'ARG ARCH_IMAGE=' } | length
  )
  let archive_count = (
    $lines
    | where {|line|
        $line =~ 'archive[.]archlinux[.]org/repos/[0-9]{4}/[0-9]{2}/[0-9]{2}/'
      }
    | length
  )
  if $image_count != 1 or $archive_count != 1 {
    fail 'expected one upstream image and one Archive URL'
  }

  let updated = (
    $content
    | str replace --regex '(?m)^ARG ARCH_IMAGE=.*$' $"ARG ARCH_IMAGE=($upstream)"
    | str replace --regex 'archive[.]archlinux[.]org/repos/[0-9]{4}/[0-9]{2}/[0-9]{2}/' $archive
  )
  $updated | save --force $containerfile
  $"($snapshot)\n" | save --force $version_file
  print $"Updated Arch ($snapshot) from ($entry.name)"
}

def "main validate-release" [release_tag: string] {
  let release = (parse-release-tag $release_tag)
  let tag_ref = $"refs/tags/($release.tag)"
  let exists = (^git show-ref --verify --quiet $tag_ref | complete)
  if $exists.exit_code != 0 {
    fail $"release tag ($release.tag) is not present"
  }
  let object_type = (^git cat-file -t $tag_ref | str trim)
  if $object_type != 'tag' {
    fail $"release tag ($release.tag) must be annotated"
  }

  let tags = (local-release-tags $release.variant $release.date)
  validate-release-sequence $release.variant $release.date $tags | ignore

  let revision = (^git rev-list -n 1 $tag_ref | str trim)
  let on_main = (
    ^git merge-base --is-ancestor $revision refs/remotes/origin/main
    | complete
  )
  if $on_main.exit_code != 0 {
    fail $"release tag ($release.tag) does not target a commit on origin/main"
  }
  print ($release | select variant date version | to json --raw)
}

def "main release" [release_tag: string] {
  let release = (parse-release-tag $release_tag)
  let status = (^git status --porcelain | str trim)
  if not ($status | is-empty) {
    fail 'release tags require a clean worktree'
  }

  let branch = (^git symbolic-ref --quiet --short HEAD | complete)
  if $branch.exit_code != 0 or ($branch.stdout | str trim) != 'main' {
    fail 'release tags must be created from the main branch'
  }

  let remote_main = (
    ^git ls-remote --heads origin refs/heads/main
    | complete
  )
  if $remote_main.exit_code != 0 {
    print --stderr ($remote_main.stderr | str trim)
    exit $remote_main.exit_code
  }
  if ($remote_main.stdout | str trim | is-empty) {
    fail 'origin/main is unavailable'
  }
  let remote_revision = (
    $remote_main.stdout
    | lines
    | first
    | split row (char tab)
    | first
  )
  let revision = (^git rev-parse HEAD | str trim)
  if $revision != $remote_revision {
    fail 'main must exactly match origin/main before creating a release tag'
  }

  let local_tag = (
    ^git show-ref --verify --quiet $"refs/tags/($release.tag)"
    | complete
  )
  if $local_tag.exit_code == 0 {
    fail $"release tag ($release.tag) already exists locally"
  }

  let remote_tags = (
    remote-release-tags $release.variant $release.date
  )
  let sequences = (
    validate-release-sequence $release.variant $release.date $remote_tags
  )
  let expected = ($sequences | length) + 1
  if $release.sequence != $expected {
    fail $"next release for ($release.variant) on ($release.date) must be archlinux/($release.variant)-($release.date)-($expected)"
  }

  ^git tag --sign --annotate $release.tag --message $"Release ($release.version)"
  ^git verify-tag $release.tag
  print $"Created ($release.tag); push it with:"
  print $"git push origin refs/tags/($release.tag)"
}

def "main build" [requested: string = 'all'] {
  let values = (context 'local')
  for target in (variants $requested) {
    (
      ^podman build
        --file src/archlinux/Containerfile
        --platform linux/amd64
        --target $target
        --build-arg $"VERSION=($values.version)"
        --build-arg $"REVISION=($values.revision)"
        --tag $"($values.image):($target)-($values.version)"
        src/archlinux
    )
  }
}

def "main tag" [requested: string = 'all'] {
  let values = (context '')
  validate-revision $values.revision
  if $values.release == null {
    fail 'RELEASE_TAG is required to create publication aliases'
  }

  for target in (publication-variants $requested $values.release.variant) {
    let source = $"($values.image):($target)-($values.version)"
    ^podman image exists $source
    ^podman tag $source $"($values.image):($target)-($values.release.date)"
    ^podman tag $source $"($values.image):($target)"
  }
}

def "main smoke" [requested: string = 'all'] {
  let values = (context 'local')

  for target in (variants $requested) {
    let image_ref = $"($values.image):($target)-($values.version)"
    let snapshot_path = $"(
      $values.snapshot | str substring 0..3
    )/($values.snapshot | str substring 4..5)/(
      $values.snapshot | str substring 6..7
    )"
    let expected_mirror = $"Server = https://archive.archlinux.org/repos/(
      $snapshot_path
    )/$repo/os/$arch"

    let root = (^podman run --rm $image_ref id -u | complete)
    if $root.exit_code != 0 or ($root.stdout | str trim) != '0' {
      fail $"($image_ref) does not run as root"
    }
    let mirror = (
      ^podman run --rm $image_ref
        grep -Fxq $expected_mirror /etc/pacman.d/mirrorlist
      | complete
    )
    if $mirror.exit_code != 0 {
      fail $"($image_ref) does not use the expected Archive mirror"
    }
    let cache = (
      ^podman run --rm $image_ref
        find /var/cache/pacman/pkg -mindepth 1 -print -quit
      | complete
    )
    if $cache.exit_code != 0 or not ($cache.stdout | str trim | is-empty) {
      fail $"($image_ref) package cache is not empty"
    }
    let sync_database = (
      ^podman run --rm $image_ref
        find /var/lib/pacman/sync -maxdepth 1 -name '*.db' -print -quit
      | complete
    )
    if $sync_database.exit_code != 0 or ($sync_database.stdout | str trim | is-empty) {
      fail $"($image_ref) has no active package sync database"
    }

    let inspect = (^podman image inspect $image_ref | complete)
    if $inspect.exit_code != 0 {
      print --stderr ($inspect.stderr | str trim)
      exit $inspect.exit_code
    }
    let details = ($inspect.stdout | from json | first)
    let labels = $details.Labels
    if $details.Architecture != 'amd64' {
      fail $"($image_ref) has an unexpected architecture"
    }
    if ($labels | get 'dev.dbent.containers.variant') != $target {
      fail $"($image_ref) has an unexpected variant label"
    }
    if ($labels | get 'org.opencontainers.image.version') != $values.version {
      fail $"($image_ref) has an unexpected version label"
    }
    if ($labels | get 'org.opencontainers.image.revision') != $values.revision {
      fail $"($image_ref) has an unexpected revision label"
    }
    if ($labels | get 'org.opencontainers.image.source') != 'https://github.com/dbent/containers' {
      fail $"($image_ref) has an unexpected source label"
    }

    if $target == 'dev' {
      let commands = [
        actionlint curl gcc git jq just make node nu reuse rumdl ssh tar unzip zip zstd
      ]
      let command_script = 'def main [...commands: string] { for command in $commands { if (which $command | is-empty) { print --stderr $"error: missing command ($command)"; exit 1 } } }'
      let command_check = (
        ^podman run --rm $image_ref nu --no-config-file --commands
          $command_script ...$commands
        | complete
      )
      if $command_check.exit_code != 0 {
        print --stderr ($command_check.stderr | str trim)
        exit $command_check.exit_code
      }

      let packages = [bash-completion fd less man-db npm ripgrep wget]
      let package_script = 'def main [...packages: string] { for package in $packages { let result = (^pacman -Q $package | complete); if $result.exit_code == 0 { print --stderr $"error: unexpected package ($package)"; exit 1 } } }'
      let package_check = (
        ^podman run --rm $image_ref nu --no-config-file --commands
          $package_script ...$packages
        | complete
      )
      if $package_check.exit_code != 0 {
        print --stderr ($package_check.stderr | str trim)
        exit $package_check.exit_code
      }

      (
        ^podman run --rm
          --volume $"((pwd)):/src:ro"
          --workdir /src
          $image_ref reuse lint
      )
    }
  }
}

def "main publish" [requested: string = 'all'] {
  let values = (context '')
  validate-revision $values.revision
  if $values.release == null {
    fail 'RELEASE_TAG is required to publish images'
  }

  for target in (publication-variants $requested $values.release.variant) {
    let tags = [
      $"($target)-($values.version)"
      $"($target)-($values.release.date)"
      $target
    ]
    for tag_name in $tags {
      ^podman push $"($values.image):($tag_name)"
    }
  }
}

def main [] {
  print 'Use a subcommand: format, lint, validate, clean, update-arch, validate-release, release, build, tag, smoke, or publish.'
}
