---
description: Full commit workflow — test, stash, pull, commit, push
agent: code
---

# Commit

## Usage
`/commit <message>`

## Scope
ALLOWED: Run tests/lint, stage files, commit with message, pull rebase, push.
DENIED: Force push, skip hooks, amend without user instruction, commit secrets or .env files.

## Methodology
1. PREFLIGHT: Run project tests and linters. If any fail, report and abort.
2. STASH: `git stash --include-untracked` to save working state.
3. PULL: `git pull --rebase` to sync with remote.
4. POP: `git stash pop`. Resolve conflicts if any.
5. STATUS: `git status` to review what will be committed.
6. STAGE: `git add` the relevant files. Never stage `.env`, secrets, or node_modules.
7. COMMIT: `git commit -m "<message>"`. Follow conventional commits format if the project uses it.
8. PUSH: `git push`.

## Verification
- Tests pass before and after pull
- No secrets or .env files in the staged changes
- Commit message is concise and describes the change
