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
ghcr.io/dbent/archlinux:base-<YYYYMMDD.RUN_ID>
ghcr.io/dbent/archlinux:dev-<YYYYMMDD.RUN_ID>
```

`RUN_ID` is the repository-unique GitHub Actions workflow run ID and is
stable across reruns. Each publication also includes a date alias such
as `dev-<YYYYMMDD>` and a source trace tag such as
`dev-sha-<full-commit-id>`.

Use the development variant in a GitHub Actions job:

```yaml
jobs:
  build:
    runs-on: ubuntu-24.04
    container: ghcr.io/dbent/archlinux:dev
    steps:
      - uses: actions/checkout@v6
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

Local automation requires Just, Nushell, and rootless Podman. The
snapshot update recipe additionally requires `curl`.

The public recipes accept `base`, `dev`, or default to both variants:

```sh
just validate
just build
just smoke
just tag
just build dev
```

Images default to `ghcr.io/dbent/archlinux`. Override `IMAGE` when a
different local name or registry is required:

```sh
IMAGE=localhost/archlinux just build dev
```

Local builds use run ID `0`. Set `RUN_ID` to use another nonnegative
decimal identifier consistently across the build, smoke, tag, and
publish recipes.

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

`just publish` pushes the release, date, floating, and—when `REVISION`
is set—full-commit trace tags. It expects the caller to authenticate
first.

## Versioning and Updates

`src/archlinux/VERSION` contains the Arch Linux Archive snapshot date
in `YYYYMMDD` format. Published family versions use `YYYYMMDD.RUN_ID`,
where `RUN_ID` is supplied by GitHub Actions. The same run ID applies
to `base` and `dev`, so both variants advance together without a
manually maintained release number.

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
metadata under `src/`, add corresponding Just dispatch, and extend the
workflow matrix without duplicating the recipe implementation.

## License

Repository-authored source is available under the
[Zero-Clause BSD](LICENSE) license. Software installed in the images
retains its own licensing terms. Copyright and licensing metadata
conforms to the [REUSE Specification](https://reuse.software/spec/);
run `reuse lint` from the repository root to verify compliance.
