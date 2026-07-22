---
name: python-shared-first
description: Check existing Python code before writing new infrastructure utilities. Use before implementing middleware, auth, logging, retry, or any cross-cutting Python concern.
---

# Python Shared-First

## Scope
Run before writing: utilities, middleware, auth helpers, env loaders, logging setup, retry/circuit-breaker, error handlers, base classes.

## Methodology
1. INVENTORY: Scan the repo for existing Python modules that could serve the same purpose. Check `src/shared/`, `lib/`, `common/`, `utils/` directories.
2. READ_SOURCE: Read the candidate modules. Understand their API, dependencies, and test coverage.
3. CHECK_IMPORT: Verify the module is importable (`uv sync` then `uv run python -c "import <module>"`).
4. EVALUATE: Does it meet the requirement? If yes, reuse. If partially, extend. If no, write new.

## Extraction Criteria
Extract a shared module when ALL of these are true:
- USED_IN_2_PLACES: The same logic appears in at least 2 separate locations
- NO_APP_DATA_DEP: The logic doesn't depend on application-specific data models
- CONFIGURABLE: Behavior can be controlled through parameters or configuration
- INFRA_LEVEL: The code handles infrastructure concerns (logging, auth, error handling, retry)

## Anti-Patterns
- REIMPLEMENT: Writing a new logger, HTTP client, or auth helper when one already exists
- MODIFY_SHARED: Changing a shared module's API without updating all call sites
- SKIP_MAP: Not running this skill before writing infrastructure code
