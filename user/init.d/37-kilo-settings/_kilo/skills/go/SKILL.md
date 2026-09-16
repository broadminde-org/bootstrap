---
name: go
description: Core Go engineering standards — project structure, go-shared module reuse, codemap backend structure, toolchain, error handling, and testing. Use when writing, reviewing, or refactoring any Go code.
---

# Go Standards

## Shared-First
Before writing middleware, auth helpers, logging setup, env loaders, HTTP utilities, retry, or file stores, inventory the private shared module `github.com/broadminde-org/go-shared`:
1. READ README.md of go-shared first — it is the package-selection authority.
2. Key packages: `web/ginutil` (TracedGroup, sourcemap, health, CORS), `web/auth` + `web/session` + `web/oidc` (single-user auth stack), `web/authmt` (multi-tenant auth — the two stacks intentionally coexist; never mix), `web/logging`, `web/frontendlog`, `web/feedback`, `web/pgxutil`, `httputil`, `envutil`, `netutil`, `listenutil`, `jsonfilestore`.
3. EVALUATE: meets the need → reuse. Partial → extend in go-shared via PR. Neither → write new.
4. Never reimplement a go-shared package in app code. `GOPRIVATE=github.com/broadminde-org/*` is intentional — do not widen or remove it.

## Backend Structure (codemap standard)
Every ee Go backend app follows `ee/docs/standards/backend-structure.md`. The three rules:
- HANDLER_STRUCT: `backend/handler.go` defines one `Handler` struct whose named fields are sub-handlers (`Projects *ProjectHandler`). Field name = route group; type name = domain.
- SINGLE_REGISTER: all authenticated routes are registered in one `func (h *Handler) RegisterRoutes(api gin.IRouter)` — one route per line as `api.VERB("/path", h.Field.Method)`, sorted by group under `// Group` comment headers. No conditionals, no `.GET().POST()` chaining.
- POSITIONAL_AUTH: public routes live in `server.go:SetupRoutes` above the `RequireAuth` middleware call; everything in `RegisterRoutes` is authenticated by position. The API group is created with `ginutil.NewTracedGroup`.
- Naming: `handlers_<domain>.go` per domain, struct `<Domain>Handler`, constructor `New<Domain>Handler`, all methods on receiver `*<Domain>Handler`.

## Tooling
- Workspace-aware: repos use `go.work`. Build from repo root.
- DONE_GATE: work is complete only when `gofmt -l .` is empty, `go vet ./...` is clean, and `go test ./...` passes (per module when inside a multi-module repo).
- Linters installed host-wide: golangci-lint, gosec, govulncheck (`~/go/bin`).
- GOWORK_CHECK: `GOWORK=off go build ./...` verifies a consumer uses the versioned go-shared module, not an accidental local workspace copy.
- In the ee repo use the `tests [app]` script (on PATH via direnv; auto-detects the app from `$PWD`) instead of assembling lint/test invocations by hand.

## Error Handling
- WRAP: `fmt.Errorf("doing thing: %w", err)` — add context at each layer, preserve the chain.
- NO_SWALLOW: every error is handled or returned. No `_ = fn()`, no empty catch blocks.
- BOUNDARY: map errors to HTTP status codes in handlers/middleware, never inside stores or services.

## Testing
- Table-driven tests with named cases; `*_test.go` beside the source file.
- Run per-module respecting `go.work`; verify with `GOWORK=off` before concluding a versioned dependency works.

## Anti-Patterns
- REIMPLEMENT: writing an auth/middleware/logging/HTTP helper that exists in go-shared
- BARE_HANDLERS_GO: domain handler methods in a grab-bag `handlers.go` instead of `handlers_<domain>.go`
- ROUTE_SCATTER: route registrations outside `RegisterRoutes` (authenticated) or `SetupRoutes` (public)
- INLINE_ROUTE_CONDITIONAL: `if cfg.FeatureX { ... }` inside `RegisterRoutes`
- CHAINED_ROUTES: `api.GET(...).POST(...)` chains
- SERVER_RECEIVER: domain handler methods with `*Server` receivers instead of `*<Domain>Handler`
