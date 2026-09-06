# AGENTS

This repository defines versioned OCI image families built with
rootless Podman and published to GHCR by GitHub Actions. `/README.md`
is the user-facing reference; `/justfile` is the authority for local
and CI automation.

## Repository Decisions

- Container families live under `/src/<family>/`.
- Pin upstream images by both immutable tag and digest.
- `/src/archlinux/VERSION` is the Arch Archive snapshot source of
  truth. Its `YYYYMMDD` value must match the Archive URL. Change
  `VERSION` only when changing the snapshot; it does not determine the
  release version.
- Releases use signed annotated Git tags named
  `archlinux/<variant>-YYYY.MM.DD-N`. Each variant has an independent
  daily sequence in which `N` starts at `1`, increases monotonically,
  and has no gaps. Removing the `archlinux/` namespace produces the
  exact immutable OCI tag.
- Keep the Arch stages ordered `base`, then `dev`, with `dev` extending
  `base` directly. `base` is minimal. `dev` includes build tools and a
  Node.js runtime but omits `npm`; leave interactive tooling to the
  host.
- Arch variants intentionally default to root. Under rootless Podman,
  container root maps into the invoking user's namespace.
- The Arch family supports `linux/amd64` only. Add an architecture only
  when every upstream image and validation path supports it.
- Preserve the OCI source label that links packages to this repository.

## Build and Publication

- Use `/justfile` recipes for validation, build, smoke tests, tagging,
  and publication. GitHub workflows must call these recipes instead of
  reimplementing their behavior.
- Use rootless Podman. Do not substitute Docker unless the task
  explicitly changes the supported tooling.
- Pull requests and relevant pushes to `main` build and test but never
  publish. Only an explicit valid release-tag push publishes the
  immutable, date, and moving GHCR aliases.
- Authenticate to GHCR with the repository `GITHUB_TOKEN`. Keep GitHub
  Actions permissions minimal and pin reusable actions to full commit
  SHAs.
- Create release tags with
  `just release archlinux/<variant>-YYYY.MM.DD-N`, review the signed
  local tag, then push that tag explicitly.

## Validation

- Canonical acceptance gate: `just validate`.
- Focused image iteration: `just build`, then `just smoke`.
- Markdown changes: use the repository `markdown-format` skill.
- All changes: review the intended diff and run `git diff --check`.
- After publication, verify the GitHub Actions job-container smoke test
  and anonymous pulls of every published alias.

## Hard Constraints

- Do not modify `/AGENTS.md` without explicit user permission.
- The 0BSD license covers repository-authored source only. Do not imply
  that software installed in an image uses that license.
