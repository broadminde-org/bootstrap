# Read-Only Analysis Tasks

## Scope
Analysis, review, audit, and assessment tasks (read-only by nature).

## Exploration Order
1. LIST_ROOT: List top-level directory with symlinks resolved
2. CHECK_PLANS: Find any plan documents (`plans/`, `.kilo/plans/`, `docs/plans/`)
3. READ_BUILD: Read build config (Makefile, Dockerfile, go.work, pyproject.toml, package.json)
4. GREP_AGENTS: Check active agent context set (`~/.config/kilo/agents/`, `~/.config/kilo/rules/`, or project `.kilo/agents/`)
5. GREP_STAGING: Check for staged/unapplied context changes (`.kilo-new/`, `_plans_temp/`)
6. READ_CODEMAPS: Read `codemap.md`, `ARCHITECTURE.md`, `README.md`

## Verification Required
- PILOT_TRUTH: Verify user claims against written plans and actual files. Claims without evidence get tagged `[UNVERIFIED]`.
- PLAN_REALITY: Compare draft plans against disk state. Flag gaps between intent and reality.
- RULE_ACCURACY: Cross-check context set claims against actual source files.

## Report Format
Each analysis report must include:
1. **Files on disk**: Table of what exists with symlink status
2. **Prior usage**: Whether each capability is actively used (true/false with inline quote evidence)
3. **Plan status**: Draft→Applied→Stale lifecycle for each plan
4. **Context coverage**: Which files/rules/standards cover which domains
5. **Issues and gaps**: Mismatches, missing coverage, stale references
