# Containers

Personal OCI container definitions built with rootless Podman and
published to the GitHub Container Registry.

## Arch Linux

The `archlinux` image family is pinned to a dated Arch Linux Archive
snapshot and is published for `linux/amd64` in two variants:

- `base` is a minimal, snapshot-pinned Arch Linux environment.
- `dev` adds general build tools and a Node.js runtime for development
  and GitHub or Gitea Actions jobs. Interactive tooling remains the
  host's responsibility, and the image does not include `npm`.

Container root is intentional. With rootless Podman, it maps into the
invoking user's namespace and does not grant host root privileges.

Pull the moving aliases with:

```sh
podman pull ghcr.io/dbent/archlinux:base
podman pull ghcr.io/dbent/archlinux:dev
```

Immutable release references use the family version:

```text
ghcr.io/dbent/archlinux:base-<YYYY.MM.DD-N>
ghcr.io/dbent/archlinux:dev-<YYYY.MM.DD-N>
```

Each publication also advances a date alias such as `dev-<YYYY.MM.DD>`
and the moving `dev` alias. Consumers that require content identity can
combine a readable release tag with its OCI digest:

```text
ghcr.io/dbent/archlinux:dev-2026.09.06-1@sha256:<manifest-digest>
```

Use the development variant in a GitHub Actions job:

```yaml
jobs:
  build:
    runs-on: ubuntu-24.04
    container: ghcr.io/dbent/archlinux:dev
    steps:
      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6
      - run: just --version
```

Use the development variant from a Dev Container definition:

```json
{
  "image": "ghcr.io/dbent/archlinux:dev",
  "remoteUser": "root",
  "updateRemoteUserUID": false
}
```

The package page is
<https://github.com/users/dbent/packages/container/package/archlinux>.

## Building

Focused source linting requires Git, Just, Nushell, Rumdl, REUSE, and
actionlint. The canonical validation gate additionally requires
rootless Podman: it builds and smoke-tests both variants, then runs the
static checks inside the proposed `dev` image. The snapshot update
recipe also requires `curl`.

The public command surface is:

```sh
just validate
just lint
just format
just build
just smoke
just tag
just build dev
```

The image-focused `build`, `smoke`, `tag`, and `publish` recipes accept
`base`, `dev`, or default to both variants. `just validate` always
checks both variants as one acceptance unit. Unreleased local builds
use the `local` version.

Images default to `ghcr.io/dbent/archlinux`. Override `IMAGE` when a
different local name or registry is required:

```sh
IMAGE=localhost/archlinux just build dev
```

Update the Arch snapshot using a UTC date in `YYYYMMDD` form, or omit
the argument to use the current UTC date:

```sh
just update-arch 20260901
just update-arch
```

The recipe selects the newest upstream Arch base image published for
the requested date, pins its digest, verifies and updates the Archive
URL, and records the snapshot date. It leaves an already-current
configuration unchanged. It fails without changing files if either the
snapshot or a same-date upstream image is unavailable.

## Releasing

Release tags have the form `archlinux/<variant>-YYYY.MM.DD-N`, where
the variant is `base` or `dev` and the date is real and zero-padded.
Each variant has an independent daily sequence: `N` starts at `1` and
increases without gaps. Create the next tag with:

```sh
just release archlinux/dev-2026.09.06-1
```

The recipe requires a clean `main` worktree that exactly matches live
`origin/main`. It checks the remote same-date sequence, creates a
signed annotated tag locally, verifies its signature, and prints the
explicit push command. It never pushes the tag itself.

After review, push the tag as printed. GitHub Actions independently
validates its syntax, sequence, annotation, signature, and ancestry
from `origin/main` before authenticating to GHCR. It then publishes the
release, date, and floating aliases for the selected variant. Pull
requests and pushes to `main` validate but never publish. Removing
`archlinux/` from the Git tag gives the exact immutable OCI tag; for
example, `archlinux/dev-2026.09.06-1` publishes `dev-2026.09.06-1`.

`just publish` is the authenticated lower-level operation used by the
release workflow. It requires
`RELEASE_TAG=archlinux/<variant>-YYYY.MM.DD-N`, runs the canonical
validation gate, creates that variant's publication aliases, and pushes
them.

`just clean` removes generated output beneath `dst/` and operational
state beneath `.tmp/`. Disposable exploration belongs in `scratch/` and
is intentionally preserved by cleanup.

## Versioning and Updates

`src/archlinux/VERSION` contains only the Arch Linux Archive snapshot
date in `YYYYMMDD` format. Release identity is independent: a Git tag
`archlinux/<variant>-YYYY.MM.DD-N` publishes that variant with the
corresponding `<variant>-YYYY.MM.DD-N` image tag. Each variant's daily
sequence resets to `1` on a new date and is manually selected but
mechanically checked for gaps.

Arch's upstream tags use a different scheme:
`base-<YYYYMMDD>.0.<build-job>`. The final number is the Arch GitLab
build job number; it is not a package release number for downstream
images.

Choose the Archive snapshot only after selecting the pinned upstream
image. Start with the date embedded in the upstream tag, build the
`base` stage, and inspect the `pacman -Syyuu` transaction. If it would
downgrade any installed package, advance the Archive date one day at a
time and repeat the build. Use the earliest snapshot that completes
without a downgrade: an earlier snapshot can roll upstream packages
back, while a later snapshot causes avoidable package updates.

Keep the upstream tag and digest, Archive URL, and `VERSION`
synchronized when changing snapshots. The shared date records the
selected repository state, while the digest makes the upstream starting
point reproducible.

To add another image family, place its Containerfile and version
metadata under `src/`, extend `bin/containers.nu`, and update the
publication workflow without duplicating the public Just interface.

Repository architecture and durable decisions are documented under
`doc/`. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development and
validation workflow.

## License

Repository-authored source is available under the
[Zero-Clause BSD](LICENSE) license. Software installed in the images
retains its own licensing terms. Copyright and licensing metadata
conforms to the [REUSE Specification](https://reuse.software/spec/);
run `reuse lint` from the repository root to verify compliance.
