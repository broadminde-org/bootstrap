---
name: shell-shared-first
description: Check existing shell scripts and init.d patterns before writing new provisioning code. Use before creating init.d steps, shell utilities, or env file templates.
---

# Shell Shared-First

## Scope
Run before writing: init.d steps, shell utilities, env file templates, provisioning scripts, cron jobs.

## Methodology
1. INVENTORY: List existing shell scripts and init.d directories. Identify common patterns (logging, error handling, idempotency checks).
2. READ_SOURCE: Read the shared shell library or sourcing patterns. Understand the conventions used.
3. CHECK_SOURCING: Verify how other scripts source shared functions. Follow the same pattern.
4. EVALUATE: Can the new code use existing init.d patterns, sourcing conventions, and helper functions?

## Extraction Criteria
Extract a shared shell library when:
- SAME_PATTERN: The same idempotency check, error handler, or logging function appears in 2+ scripts
- NO_APP_SPECIFIC: The function doesn't depend on application-specific paths or config
- SOURCE_SAFE: The library can be sourced safely from any working directory

## Pattern Rules
- Sourcing: `source "${SCRIPT_DIR}/lib.sh"` or `source ./lib.sh` (relative, `./` prefix)
- Idempotency: CHECK → SKIP_IF_MATCH → APPLY → VERIFY pattern in every step
- Error handling: `set -euo pipefail` at the top of every script
- Logging: Use sourced logging functions, not bare `echo`

## Anti-Patterns
- REIMPLEMENT: Writing a new idempotency check pattern when one already exists in the same init.d directory
- INCONSISTENT_SOURCE: Using a different sourcing convention than existing scripts
- SKIP_MAP: Not checking existing init.d steps before writing a new one
