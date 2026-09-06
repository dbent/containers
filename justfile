set shell := ["nu", "--no-config-file", "--commands"]

today := `date now | date to-timezone UTC | format date "%Y%m%d"`

default:
    @just --list

# Format maintained source files.
format:
    nu --no-config-file bin/containers.nu format

# Run source, metadata, and static-analysis checks.
lint:
    nu --no-config-file bin/containers.nu lint

# Run the complete source, build, smoke, and lint gate.
validate:
    nu --no-config-file bin/containers.nu validate

# Remove repository-local output and operational state.
clean:
    nu --no-config-file bin/containers.nu clean

# Update the Arch snapshot and its newest same-date upstream image.
update-arch snapshot=today:
    nu --no-config-file bin/containers.nu update-arch {{ quote(snapshot) }}

# Create a signed, gap-free release tag locally without pushing it.
release release-tag:
    nu --no-config-file bin/containers.nu release {{ quote(release-tag) }}

# Build one variant, or all variants, with its local or release tag.
build variant="all":
    nu --no-config-file bin/containers.nu build {{ quote(variant) }}

# Add release-date and floating aliases. Set RELEASE_TAG first.
tag variant="all":
    nu --no-config-file bin/containers.nu tag {{ quote(variant) }}

# Run root, mirror, metadata, and tool smoke tests.
smoke variant="all":
    nu --no-config-file bin/containers.nu smoke {{ quote(variant) }}

# Validate, tag, then push one variant or all variants. Set RELEASE_TAG and authenticate first.
publish variant="all": validate (tag variant)
    nu --no-config-file bin/containers.nu publish {{ quote(variant) }}
