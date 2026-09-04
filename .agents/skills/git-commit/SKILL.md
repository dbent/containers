---
name: git-commit
description: Create or amend approval-gated Git commits with repository conventions for Conventional Commits messages, line lengths, bodies, staging, signing behavior, and timestamp preservation. Use whenever the user asks to commit, amend, fix up, reword, or otherwise create a commit.
---

# Git Commit

Create or amend a focused commit while preserving unrelated worktree
changes. Every commit requires fresh user approval of the exact staged
state and message.

## Inspect and stage

Before proposing a commit:

1. Inspect `git status --short`, the unstaged diff, and the staged
   diff.
2. Identify the files that belong to the requested change. Do not stage
   unrelated changes or temporary review artifacts.
3. Stage intended paths explicitly. Use a broad command such as
   `git add -A` only when the user clearly requests every outstanding
   change and the complete file list has been verified.
4. Review `git diff --cached --name-status`,
   `git diff --cached --stat`, and `git diff --cached --check`.
5. Stop if the staged changes are empty, incoherent, unexpected, or
   include files outside the requested scope.

Do not discard, overwrite, unstage, or otherwise alter changes that do
not belong to the requested commit.

For an intentionally empty commit, confirm that no paths are staged and
state that the resulting tree will be empty before requesting approval.

## Respect signing configuration

Let the active Git configuration and explicit user instructions
determine whether to sign a commit. Do not require a signature or pass
`-S` unconditionally.

Never disable configured or requested signing to work around a failure.
If sandbox restrictions prevent signing or verification, request
permission to run the command outside the sandbox.

## Write the message

Follow the
[Conventional Commits 1.0.0 specification][conventional-commits] as the
baseline. Apply the stricter repository rules below in addition to its
requirements.

Use this structure:

```text
<type>[optional scope][optional !]: <description>

[optional body]

[optional footer]
```

Apply these rules:

- Limit the entire first line, including its prefix, to 50 characters.
- Write the type, scope, and initial description word in lowercase.
  Preserve the proper capitalization of names and acronyms such as OCI,
  GHCR, and CI.
- Write the description in imperative mood without a terminal period.
- Use American English spelling and vocabulary unless explicitly
  instructed otherwise.
- Use a lowercase noun for an optional scope.
- Wrap every line after the first line at 71 characters or fewer,
  including footers.
- Separate the body from the description with one blank line.
- Write a body unless the change is small and the description captures
  it completely.
- Summarize what changed and why it changed. Include useful context,
  rationale, or consequences rather than merely enumerating changes
  evident from the diff.
- Treat the body as Markdown. Use paragraphs, lists, code spans, and
  references when they improve it.
- Do not add a heading unless the body has multiple sections that each
  need a heading.
- Review and copyedit the body before proposing it. If drafting the
  message in a temporary file, do not stage or commit that file.
- Do not add headers, trailers, footers, signatures, attributions,
  generator markers, or other commit-message metadata identifying an
  agent, AI assistant, automation harness, or tool unless explicitly
  requested. This includes `Co-Authored-By:`, `Generated-By:`, and
  similar metadata.

Use these types:

- `feat`: add a capability or behavior.
- `fix`: correct erroneous behavior, prose, or workflow logic.
- `docs`: change documentation without changing behavior.
- `refactor`: restructure content or workflows without changing
  behavior.
- `build`: change build inputs, outputs, or tooling.
- `chore`: perform repository maintenance not covered above.

Choose the type from the change rather than mechanically preserving an
older prefix. Treat `repo` as a scope, not a type. In particular:

- Use `chore(repo)` for repository bookkeeping.
- Use `docs(agents)` for prose instructions for agents.
- Use `chore(agents)` for agent-tool integration.
- Use `chore(format)` for formatter configuration.

Examples:

```text
build: add Arch container images
docs(agents): refine repository guidance
chore(repo): add ignore rules
chore(format): refine formatter configuration
```

## Obtain approval

Immediately before creating or amending a commit:

1. Present the exact subject and body.
2. Present the staged path list and a concise staged diff summary.
3. State whether the commit will be signed and how that was determined.
4. Stop and request explicit user approval for that one commit.

Do not treat an earlier request to implement, finish, commit, push, or
follow a plan as approval. Approval is single-use and applies only to
the staged object state and message shown to the user. If either
changes after approval, repeat the review and request approval again.

## Create a commit

After approval for a new commit:

1. Let Git assign the current author and committer timestamps.
2. Let the active Git configuration provide the author and committer
   identities.
3. Create the commit with the approved message and applicable signing
   behavior.

Do not create a commit without the approval required above.

## Amend a commit

Amending rewrites history. Amend only when the user explicitly requests
it and the target commit is unambiguous.

Before proposing an amendment:

1. Inspect the target commit and confirm it is `HEAD`. Ask before using
   a broader history rewrite for a non-`HEAD` commit.
2. Read the raw commit with `git cat-file commit HEAD` and record both
   original timestamps as Unix seconds with their timezone offsets.
3. Plan to preserve the original author and committer timestamps by
   setting `GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE` when running
   `git commit --amend`.
4. Let the active Git configuration and explicit user instructions
   determine whether to sign the amended commit.
5. Complete the approval gate using the exact amended staged state and
   message.

Do not use `--reset-author` or allow an amendment to silently replace
either original timestamp unless the user explicitly requests that
change.

## Validate and report

After creating or amending a commit:

1. Verify the committed path list and message with `git show`.
2. If the commit is signed, verify it with `git verify-commit HEAD`.
3. Confirm the subject and body line limits and, unless explicitly
   requested, the absence of agent- or harness-specific commit-message
   metadata.
4. Inspect `git status --short` and ensure unrelated worktree changes
   remain intact.
5. Report the new commit hash, subject, signing status, and remaining
   worktree state.

Push only when the user has requested it. After pushing, verify that
the local and upstream refs match and report the result.

[conventional-commits]: https://www.conventionalcommits.org/en/v1.0.0/
