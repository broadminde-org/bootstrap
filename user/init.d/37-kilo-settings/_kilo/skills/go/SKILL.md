---
name: go
description: Core Go engineering standards — project structure, go-shared module reuse, codemap backend structure, toolchain, error handling, and testing. Use when writing, reviewing, or refactoring any Go code.
---

# Go Standards

## Shared-First
In repositories that use or require `github.com/broadminde-org/go-shared`, inspect its available source/dependency documentation before writing reusable middleware, auth helpers, logging setup, env loaders, HTTP utilities, retry, or file stores. Do not provision access or install dependencies merely to inventory reuse:
1. READ README.md of go-shared first — it is the package-selection authority.
2. Key packages: `web/ginutil` (TracedGroup, sourcemap, health, CORS), `web/auth` + `web/session` + `web/oidc` (single-user auth stack), `web/authmt` (multi-tenant auth — the two stacks intentionally coexist; never mix), `web/logging`, `web/frontendlog`, `web/feedback`, `web/pgxutil`, `httputil`, `envutil`, `netutil`, `listenutil`, `jsonfilestore`.
3. EVALUATE: meets the need → reuse. Partial → report a possible shared extension; inventory is not authorization to edit another repository or open a PR. Neither → write the smallest in-scope implementation.
4. In applicable apps, do not reimplement an existing suitable go-shared package. Preserve intentional `GOPRIVATE=github.com/broadminde-org/*` settings; do not widen or remove them.

## Backend Structure (codemap standard)
For ee Go backend apps governed by `ee/docs/standards/backend-structure.md`, follow these conventions. Do not impose this layout on unrelated repositories or standalone helpers:
- HANDLER_STRUCT: `backend/handler.go` defines one `Handler` struct whose named fields are sub-handlers (`Projects *ProjectHandler`). Field name = route group; type name = domain.
- SINGLE_REGISTER: all authenticated routes are registered in one `func (h *Handler) RegisterRoutes(api gin.IRouter)` — one route per line as `api.VERB("/path", h.Field.Method)`, sorted by group under `// Group` comment headers. No conditionals, no `.GET().POST()` chaining.
- POSITIONAL_AUTH: public routes live in `server.go:SetupRoutes` above the `RequireAuth` middleware call; everything in `RegisterRoutes` is authenticated by position. The API group is created with `ginutil.NewTracedGroup`.
- Naming: `handlers_<domain>.go` per domain, struct `<Domain>Handler`, constructor `New<Domain>Handler`, all methods on receiver `*<Domain>Handler`.

## Tooling
- Workspace-aware: inspect `go.mod`, any `go.work`, and project instructions; run checks from the applicable module/workspace roots rather than assuming every repo uses a workspace.
- VALIDATION: use affected formatting, vet, and regression checks during development, then all applicable user-, project-, AGENTS.md-, and CI-required milestone/final checks. A narrower completion claim cannot waive them. Use the existing harness; where no convention applies, a minimal relevant regression and formatting check is a floor, not a ceiling or replacement for security, money-path, or release qualification.
- FAILURE_BOUNDARY: Report unrelated pre-existing failures; do not expand scope to fix them.
- Host tooling may include golangci-lint, gosec, and govulncheck (`~/go/bin`); verify availability without installing merely for a narrow correction.
- GOWORK_CHECK: when claiming a versioned dependency consumer works, verify with `GOWORK=off go build ./...` and applicable consumer tests so an accidental local workspace copy cannot satisfy the claim.
- In the ee repo use the `tests [app]` script (on PATH via direnv; auto-detects the app from `$PWD`) instead of assembling lint/test invocations by hand.

## Error Handling
- WRAP: `fmt.Errorf("doing thing: %w", err)` — add context at each layer, preserve the chain.
- NO_SWALLOW: every error is handled or returned. No `_ = fn()`, no empty catch blocks.
- BOUNDARY: map errors to HTTP status codes in handlers/middleware, never inside stores or services.

## Testing
- Table-driven tests with named cases; `*_test.go` beside the source file.
- Run per-module respecting `go.work`; verify with `GOWORK=off` before concluding a versioned dependency works.

## Anti-Patterns
The shared-module and route/layout anti-patterns below apply only where those project conventions govern the code.
- REIMPLEMENT: writing an auth/middleware/logging/HTTP helper that exists in go-shared
- BARE_HANDLERS_GO: domain handler methods in a grab-bag `handlers.go` instead of `handlers_<domain>.go`
- ROUTE_SCATTER: route registrations outside `RegisterRoutes` (authenticated) or `SetupRoutes` (public)
- INLINE_ROUTE_CONDITIONAL: `if cfg.FeatureX { ... }` inside `RegisterRoutes`
- CHAINED_ROUTES: `api.GET(...).POST(...)` chains
- SERVER_RECEIVER: domain handler methods with `*Server` receivers instead of `*<Domain>Handler`
