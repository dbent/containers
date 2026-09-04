---
name: markdown-format
description: Format Markdown files as the final editing pass after any change, including incidental edits and edits made while another skill or workflow is active. Use whenever the current task creates or modifies a .md file; do not apply it to untouched files unless the user or calling workflow explicitly includes them in formatting scope.
---

# Markdown Format

Format every Markdown file created or modified by the current task,
plus any other Markdown file explicitly placed in formatting scope by
the user or calling workflow. Do not format unrelated files, including
files with preexisting changes unrelated to the task.

If the user limits edits to a specific subsection or region, do not run
a whole-file formatter unless the user explicitly authorizes it. Report
that formatting was skipped because it could modify content outside the
authorized scope.

Use the repository-root `.rumdl.toml`. It configures 71-column GFM
formatting, aligned table style, and the ignored cache directory at
`dst/cache/rumdl`. Do not modify that configuration unless the task
explicitly includes it.

Format each in-scope file explicitly:

```sh
rumdl fmt <paths>...
```

After formatting, verify the same files:

```sh
rumdl check <paths>...
```

Review the resulting diff to ensure formatting did not alter unrelated
content, then run `git diff --check`.

## Useful commands

Use these commands as needed for discovery and diagnosis; they do not
replace the required final formatting pass:

- `rumdl --help`: list the available subcommands and global options.
- `rumdl fmt --help`: show formatter options and usage.
- `rumdl check --help`: show checker options and usage.
- `rumdl fmt --diff <paths>...`: preview formatting changes without
  modifying files.
- `rumdl config file`: show the absolute path of the loaded
  configuration file.
- `rumdl config --no-defaults`: show the active nondefault
  configuration values.
- `rumdl explain <rule-name>`: show detailed documentation and examples
  for a rule.
- `rumdl --version`: show the installed version.

If `rumdl` cannot write an in-scope file because the managed checkout
protects it, retry the same explicit formatting command with scoped
permission. Do not broaden the path list.

If `rumdl` is unavailable, do not install it or substitute another
formatter. Report that the in-scope Markdown files were not formatted,
and recommend installing `rumdl` and running the commands manually.
