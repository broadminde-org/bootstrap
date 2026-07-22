# Codemap Discovery

## Scope
Starting work in a new application or repository context.

## Workflow
1. READ_CODEMAP: Look for `codemap.md`, `codemap-*.md`, `ARCHITECTURE.md`, `README.md` in the repo root and `docs/` directory.
2. INVENTORY: If codemaps exist, verify they match reality. If not, run codebase-inventory skill.
3. MAP_TOP_LEVEL: Identify the app structure: monorepo layout, entry points, build system, config surface.
4. IDENTIFY_DOMAINS: List technologies in play (languages, frameworks, databases, deployment targets).
5. CHECK_PLANS: Look for `.kilo/plans/` or `docs/plans/` for any in-progress architecture decisions.

## Rules
- NEVER assume you know the app from a single file read. At minimum: read the top-level directory listing, build config, and entry point.
- EXISTING_DOCS take priority. Don't reinvent codemaps that already exist.
- UNKNOWN is better than WRONG. Mark gaps explicitly rather than guessing structure.
