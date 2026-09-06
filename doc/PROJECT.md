# Project Setup

## Repository Decisions

- `GIT-003`: Retain the established SHA-1 object format. The canonical
  upstream and public references are already GitHub-hosted SHA-1
  objects; rewriting them solely to prefer SHA-256 would break stable
  commit and image trace references without improving current
  interoperability. Reconsider only if the canonical host and required
  integrations support a transition that preserves those references.

## Language Quality Tools

- Markdown uses Rumdl with `.rumdl.toml`; `just format` rewrites it and
  `just lint` checks it.
- Just uses its built-in formatter; both quality commands invoke it in
  the appropriate write or check mode.
- GitHub Actions YAML uses actionlint through `just lint`.
- Nushell has no separate formatter or linter selected. Loading
  `bin/containers.nu` exercises the Nushell parser, and the public
  commands provide behavioral validation. No suitable Nushell-specific
  tool is currently available in the official Arch package
  repositories.
- Containerfile and embedded package-installation shell have no
  separate formatter or linter selected. The source-contract checks,
  Podman build, and runtime smoke tests provide stronger
  project-specific coverage; ShellCheck does not parse Containerfile
  instructions as shell scripts.

Re-evaluate the unselected Nushell and Containerfile tools when a
maintained, suitable option is available from the official Arch
repositories. Before adopting a fixed-style formatter, confirm broad
language-community consensus or obtain an explicit project decision
about its style.

## Project Setup Exceptions

- `DEV-003`: Do not provide a Development Container for this
  repository. Its core build and smoke-test workflow requires the
  invoking user's rootless Podman namespaces, storage, and credentials.
  A nested or socket-forwarded container would add privilege and
  host-coupling concerns without isolating the actual build
  environment. The published `dev` image remains a downstream
  development and Actions artifact, not a self-hosting environment for
  this repository.
- `CI-005`: Do not generate a changelog or create hosted release
  objects. Signed `archlinux/<variant>-YYYY.MM.DD-N` tags explicitly
  version and publish individual OCI images, while focused Git history
  remains the change record. Reconsider if the audience needs curated
  release notes, a compatibility policy, or non-container release
  artifacts.
