# Implementation Notes

## Selecting an Arch Snapshot

The final numeric component in an upstream Arch image tag is the
upstream GitLab build-job number, not a downstream package or image
release. Select the upstream image first, then use the earliest Archive
snapshot on or after its embedded date that completes `pacman -Syyuu`
without downgrading installed packages.

The image digest fixes the starting filesystem; the Archive date fixes
the package repositories used during the build. Reproducibility
requires both.

## Version Identity

GitHub Actions run IDs are repository-unique and stable across reruns.
A single run ID versions both Arch variants so `base` and `dev` advance
as a coherent family. Local builds use run ID `0` because they are not
published releases.

## Root Identity

Container root is required by package tooling and GitHub Actions job
containers. With rootless Podman it maps through the invoking user's
user namespace and does not grant host root privileges.

## Public Versus Interactive Tools

The `dev` image contains tools needed for builds and non-interactive
jobs. It intentionally omits `npm`, pagers, manual pages, shell
completion, file finders, and other tools expected to remain the host's
responsibility. Smoke tests enforce both the required and intentionally
absent inventories.
