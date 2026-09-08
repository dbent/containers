# Project Setup

## Repository Decisions

- `GIT-003`: Retain the established SHA-1 object format. The canonical
  upstream and public references are already GitHub-hosted SHA-1
  objects; rewriting them solely to prefer SHA-256 would break stable
  commit and image trace references without improving current
  interoperability. Reconsider only if the canonical host and required
  integrations support a transition that preserves those references.

## Project Setup Exceptions

- `LEGAL-005`: License all repository-authored source under 0BSD,
  including image definitions beneath `/src/`. This repository treats
  Containerfiles as infrastructure and distribution definitions rather
  than as a separately reusable software implementation; one permissive
  license keeps those definitions and their automation under the same
  terms. This exception does not relicense base images, installed
  packages, or other included software, which retain their own terms.
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
