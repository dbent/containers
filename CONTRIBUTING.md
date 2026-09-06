# Contributing

## Scope

Changes should keep each image family reproducible, minimal for its
stated role, and usable through rootless Podman. Add a platform only
when every upstream input and validation path supports it.

Use American English in repository-authored prose. Use Nushell for
repository automation and keep the Justfile as the public command
surface. Do not edit generated or operational state as maintained
source.

## Requirements

Focused source linting requires Git, Just, Nushell, Rumdl, REUSE, and
actionlint. The canonical validation gate additionally requires
rootless Podman and uses the built `dev` image for the full lint
toolchain. Updating the Arch snapshot requires `curl` and network
access.

No dependency-installation step is required. Confirm the tools are
available, then inspect the public commands with:

```sh
just --list
```

## Validation

Format maintained Markdown and the Justfile with:

```sh
just format
```

Run focused source and static-analysis checks during iteration with:

```sh
just lint
```

Run the canonical acceptance gate before completion:

```sh
just validate
```

That command builds and smoke-tests both image variants, then runs the
source and static-analysis checks inside the proposed `dev` image. The
individual image recipes remain available for focused iteration:

```sh
just build
just smoke
```

Those image commands accept `base`, `dev`, or default to both variants.
Review the intended diff and run `git diff --check` for every change.

## Source and Disposable State

- Edit image-family source only under `src/<family>/`.
- Treat `src/archlinux/VERSION` as the Arch snapshot authority.
- Put retained generated or build output under `dst/`.
- Put repository-local caches and other operational state under
  `.tmp/`.
- Use `scratch/` only for disposable exploration.
- Run `just clean` to remove `dst/` and `.tmp/` without touching source
  or scratch material.

## Commits and Publication

Keep commits focused and use Conventional Commits. Preserve configured
signing, obtain approval for the exact staged state and message, and
verify signed commits after creation. A completed change does not
authorize a commit or push.

Pull requests and pushes to `main` never publish images. Create a
release from a clean, synchronized `main` branch with:

```sh
just release archlinux/<variant>-YYYY.MM.DD-N
```

The recipe verifies that the selected variant's same-date sequence
starts at `1` and has no gaps, then creates and verifies a signed
annotated tag without pushing it. Review the tag and push it using the
printed command.

Only a valid release-tag push publishes images. The workflow
independently checks the tag and grants registry-write permission only
to its publication job, then verifies the selected variant's release,
date, and floating aliases through anonymous pulls. Do not publish
local test tags as part of ordinary validation.
