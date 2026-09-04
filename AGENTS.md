# AGENTS

This repository defines versioned OCI image families built with
rootless Podman and published to GHCR by GitHub Actions. `/README.md`
is the user-facing reference; `/justfile` is the authority for local
and CI automation.

## Repository Decisions

- Container families live under `/src/<family>/`.
- Pin upstream images by both immutable tag and digest.
- `/src/archlinux/VERSION` is the Arch Archive snapshot source of
  truth. Its `YYYYMMDD` value must match the Archive URL. Published
  family versions use `YYYYMMDD.RUN_ID`, with the repository-unique
  GitHub Actions run ID supplied through `RUN_ID`; local builds default
  to run ID `0`. Change `VERSION` only when changing the snapshot.
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
- Pull requests build and test but never publish. Relevant pushes to
  `main` publish the moving GHCR aliases.
- Authenticate to GHCR with the repository `GITHUB_TOKEN`. Keep GitHub
  Actions permissions minimal and pin reusable actions to full commit
  SHAs.

## Validation

- Source metadata: `just validate`.
- Image or build-input changes: `just build`, `just smoke`, then
  `just tag`.
- Markdown changes: use the repository `markdown-format` skill.
- All changes: review the intended diff and run `git diff --check`.
- After publication, verify the GitHub Actions job-container smoke test
  and anonymous pulls of every published variant.

## Hard Constraints

- Do not modify `/AGENTS.md` without explicit user permission.
- The 0BSD license covers repository-authored source only. Do not imply
  that software installed in an image uses that license.
