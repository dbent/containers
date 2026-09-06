set shell := ["nu", "--no-config-file", "--commands"]
set positional-arguments
set tempdir := "/tmp"

today := `date now | date to-timezone UTC | format date "%Y%m%d"`

default:
    @just --list

# Validate source metadata and the Arch version contract.
validate:
    #!/usr/bin/env -S nu --no-config-file

    def fail [message: string, code: int = 1] {
      print --stderr $"error: ($message)"
      exit $code
    }

    def main [] {
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

      ^just --unstable --fmt --check
    }

# Update the Arch snapshot and its newest same-date upstream image.
update-arch snapshot=today:
    #!/usr/bin/env -S nu --no-config-file

    def fail [message: string, code: int = 1] {
      print --stderr $"error: ($message)"
      exit $code
    }

    def main [snapshot: string] {
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

# Build one variant, or all variants, with its full release tag.
build variant="all":
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

    def main [requested: string] {
      let image = ($env.IMAGE? | default 'ghcr.io/dbent/archlinux')
      let snapshot = (open --raw src/archlinux/VERSION | str trim)
      let run_id = ($env.RUN_ID? | default '0')
      if not ($run_id =~ '^(0|[1-9][0-9]*)$') {
        fail 'RUN_ID must be a nonnegative decimal integer'
      }
      let version = $"($snapshot).($run_id)"
      let revision = ($env.REVISION? | default 'local')

      for target in (variants $requested) {
        (
          ^podman build
            --file src/archlinux/Containerfile
            --platform linux/amd64
            --target $target
            --build-arg $"VERSION=($version)"
            --build-arg $"REVISION=($revision)"
            --tag $"($image):($target)-($version)"
            src/archlinux
        )
      }
    }

# Add date, floating, and optional full-commit aliases.
tag variant="all":
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

    def main [requested: string] {
      let image = ($env.IMAGE? | default 'ghcr.io/dbent/archlinux')
      let snapshot = (open --raw src/archlinux/VERSION | str trim)
      let run_id = ($env.RUN_ID? | default '0')
      if not ($run_id =~ '^(0|[1-9][0-9]*)$') {
        fail 'RUN_ID must be a nonnegative decimal integer'
      }
      let version = $"($snapshot).($run_id)"
      let revision = ($env.REVISION? | default '')

      if not ($revision | is-empty) and not ($revision =~ '^[0-9a-f]{40,64}$') {
        fail 'REVISION must be a full hexadecimal Git object ID'
      }

      for target in (variants $requested) {
        let source = $"($image):($target)-($version)"
        ^podman image exists $source
        ^podman tag $source $"($image):($target)-($snapshot)"
        ^podman tag $source $"($image):($target)"
        if not ($revision | is-empty) {
          ^podman tag $source $"($image):($target)-sha-($revision)"
        }
      }
    }

# Run root, mirror, metadata, and tool smoke tests.
smoke variant="all":
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

    def main [requested: string] {
      let image = ($env.IMAGE? | default 'ghcr.io/dbent/archlinux')
      let snapshot = (open --raw src/archlinux/VERSION | str trim)
      let run_id = ($env.RUN_ID? | default '0')
      if not ($run_id =~ '^(0|[1-9][0-9]*)$') {
        fail 'RUN_ID must be a nonnegative decimal integer'
      }
      let version = $"($snapshot).($run_id)"
      let revision = ($env.REVISION? | default 'local')

      for target in (variants $requested) {
        let ref = $"($image):($target)-($version)"
        let snapshot_path = $"(
          $snapshot | str substring 0..3
        )/($snapshot | str substring 4..5)/(
          $snapshot | str substring 6..7
        )"
        let expected_mirror = $"Server = https://archive.archlinux.org/repos/(
          $snapshot_path
        )/$repo/os/$arch"

        let root = (^podman run --rm $ref id -u | complete)
        if $root.exit_code != 0 or ($root.stdout | str trim) != '0' {
          fail $"($ref) does not run as root"
        }
        let mirror = (
          ^podman run --rm $ref
            grep -Fxq $expected_mirror /etc/pacman.d/mirrorlist
          | complete
        )
        if $mirror.exit_code != 0 {
          fail $"($ref) does not use the expected Archive mirror"
        }
        let cache = (
          ^podman run --rm $ref
            find /var/cache/pacman/pkg -mindepth 1 -print -quit
          | complete
        )
        if $cache.exit_code != 0 or not ($cache.stdout | str trim | is-empty) {
          fail $"($ref) package cache is not empty"
        }
        let sync_database = (
          ^podman run --rm $ref
            find /var/lib/pacman/sync -maxdepth 1 -name '*.db' -print -quit
          | complete
        )
        if $sync_database.exit_code != 0 or ($sync_database.stdout | str trim | is-empty) {
          fail $"($ref) has no active package sync database"
        }

        let inspect = (^podman image inspect $ref | complete)
        if $inspect.exit_code != 0 {
          print --stderr ($inspect.stderr | str trim)
          exit $inspect.exit_code
        }
        let details = ($inspect.stdout | from json | first)
        let labels = $details.Labels
        if $details.Architecture != 'amd64' {
          fail $"($ref) has an unexpected architecture"
        }
        if ($labels | get 'dev.dbent.containers.variant') != $target {
          fail $"($ref) has an unexpected variant label"
        }
        if ($labels | get 'org.opencontainers.image.version') != $version {
          fail $"($ref) has an unexpected version label"
        }
        if ($labels | get 'org.opencontainers.image.revision') != $revision {
          fail $"($ref) has an unexpected revision label"
        }
        if ($labels | get 'org.opencontainers.image.source') != 'https://github.com/dbent/containers' {
          fail $"($ref) has an unexpected source label"
        }

        if $target == 'dev' {
          let commands = [
            actionlint curl gcc git jq just make node nu reuse rumdl ssh tar unzip zip zstd
          ]
          let command_script = 'def main [...commands: string] { for command in $commands { if (which $command | is-empty) { print --stderr $"error: missing command ($command)"; exit 1 } } }'
          let command_check = (
            ^podman run --rm $ref nu --no-config-file --commands
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
            ^podman run --rm $ref nu --no-config-file --commands
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
              $ref reuse lint
          )
        }
      }
    }

# Push every tag for one variant, or all variants. Authenticate first.
publish variant="all": (tag variant)
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

    def main [requested: string] {
      let image = ($env.IMAGE? | default 'ghcr.io/dbent/archlinux')
      let snapshot = (open --raw src/archlinux/VERSION | str trim)
      let run_id = ($env.RUN_ID? | default '0')
      if not ($run_id =~ '^(0|[1-9][0-9]*)$') {
        fail 'RUN_ID must be a nonnegative decimal integer'
      }
      let version = $"($snapshot).($run_id)"
      let revision = ($env.REVISION? | default '')

      for target in (variants $requested) {
        let base_tags = [$"($target)-($version)", $"($target)-($snapshot)", $target]
        let tags = if ($revision | is-empty) {
          $base_tags
        } else {
          $base_tags | append $"($target)-sha-($revision)"
        }
        for tag_name in $tags {
          ^podman push $"($image):($tag_name)"
        }
      }
    }
