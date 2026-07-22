---
name: go-shared-first
description: Check existing Go packages before writing new shared utilities. Use before implementing middleware, auth, logging, retry, or any cross-cutting Go concern.
---

# Go Shared-First

## Scope
Run before writing: middleware, interceptors, auth helpers, config loaders, logging setup, retry/circuit-breaker, error types, base handlers.

## Methodology
1. INVENTORY: Scan the Go workspace for existing packages. Check `shared/`, `pkg/`, `internal/`, `common/`, `lib/` directories across the module.
2. READ_SOURCE: Read the candidate packages. Understand their exported API, dependencies, and test coverage.
3. CHECK_IMPORT: Verify the package is importable from your target module's `go.mod`.
4. EVALUATE: Does it meet the requirement? If yes, reuse. If partially, extend. If no, write new.

## Extraction Criteria
Extract a shared package when ALL of these are true:
- USED_IN_2_PLACES: The same logic appears in at least 2 separate packages
- NO_APP_DATA_DEP: The logic doesn't depend on application-specific types
- CONFIGURABLE: Behavior can be controlled through parameters, options pattern, or configuration
- INFRA_LEVEL: The code handles infrastructure concerns (logging, auth, error handling, retry)

## Go-Specific Rules
- Use `go.work` for multi-module repos. Never use `replace` directives in `go.mod` for local modules.
- Shared packages live in a shared module imported by app modules. Not copied between apps.
- Interface types in the consuming package. Concrete implementations in the shared package.

## Anti-Patterns
- REIMPLEMENT: Writing a new logger, gRPC interceptor, or config loader when one already exists in shared
- COPY_PASTE: Copying a file from one app module to another instead of extracting to shared
- SKIP_MAP: Not running this skill before writing infrastructure code
