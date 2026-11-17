---
description: Local-only commit workflow with scoped checks and intended changes
agent: code
---

# Commit

## Usage
`/commit <message>`

## Scope
ALLOWED: With an explicit commit request and runtime approval, inspect changes, run authorized affected/project-required commit checks, stage only intended files/hunks, and create a local commit.
DENIED: Stash, pull/rebase, conflict repair, automatic push/publication, force push, skip hooks, amend without user instruction, commit secrets or .env files, or alter unrelated user changes. Publication requires a separate explicit request.

## Methodology
1. INSPECT: Review `git status`, unstaged and staged diffs, and `git log --oneline -10`. Identify intended changes, untracked files, and unrelated user work before any Git mutation.
2. PREFLIGHT: Run affected checks plus applicable project-required commit checks through the existing harness. Report unrelated pre-existing failures separately; do not abort solely for them or silently repair them. A failed/unavailable required commit check still blocks an unqualified successful commit workflow.
3. STAGE: Stage only explicitly intended files/hunks, never `.env`, secrets, node_modules, or unrelated changes. If a mixed file contains unrelated user hunks that cannot be safely isolated by authorized non-interactive staging, stop for operator disposition; do not stash, restore, or repair them.
4. VERIFY_STAGED: Inspect the complete final staged diff, including any pre-existing staged content, and staged filenames. Stop if unrelated staged content would be included. Confirm no secrets and no unintended hunks; preserve user work.
5. COMMIT: `git commit -m "<message>"` locally only. Match recent repo style (conventional commits when used). Never skip hooks. If hooks fail, fix only authorized issues and retry with changed evidence; do not amend a failed commit.
6. REPORT: Inspect status and the resulting local commit; report checks and residual failures. Do not sync, resolve remote conflicts, or push under `/commit`.

## Verification
- Affected checks and project-required commit checks have observed results; unrelated failures are distinguished from required-check failures
- No secrets or .env files in the staged changes
- Commit message is concise and describes the change
- Final staged content contains only intended changes; the commit remains local and user changes are preserved
