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

## Module Versions And Private Access
- Load `package-version-lookup` for version/CLI facts and `debug-with-logs` for failures. Inspect `go.mod`, `go.sum`, `go.work`, replacements, vendoring, and available dependency source first; a local replacement is not evidence that a published version works.
- Look up the module path declared by its `go.mod`, not an import's package subdirectory or an SSH alias. Major v2+ modules normally include `/vN`; respect exceptions such as `gopkg.in` and legacy `+incompatible` versions rather than rewriting the path blindly. Proxy paths also require Go's uppercase escaping (`A` becomes `!a`).
- Proxy version lists are unordered, may omit pseudo-versions, and are not a latest-release guarantee. Use Go module-aware version/query semantics, distinguish prereleases and retractions, and report the query and source; never take the last line or lexical maximum as latest.
- Classify privacy before any remote lookup. Inspect effective `GOPRIVATE`, `GONOPROXY`, `GONOSUMDB`, `GOPROXY`, and `GOSUMDB` through authorized, value-screened evidence. `GOPRIVATE` supplies defaults that explicit overrides can defeat. A proxy's fallback rules do not make a private lookup safe.
- Never send private module paths to public proxies, checksum databases, registry HTTP endpoints, or public search. For `go-shared`, load `go-shared-access` and follow its existing read-only SSH routing; other private modules require their own approved route. Missing access is a blocker, not permission to provision credentials, change global routing, or retry publicly.
- Reject failed HTTP responses, malformed bodies, invalid module/version results, and mismatched identities; do not parse an error page as a version or guess after failure. Record unavailable verification without exposing credentials or private request URLs.
- `go list`, version queries, builds, and tests can contact proxies, VCS hosts, checksum services, or download toolchains and write module/build caches. A cached result is not fresh network evidence, and a warm cache can mask broken private routing. Inspect network/cache policy before authorized execution; do not clear shared caches or run commands under source/static-only authority.

## Backend Structure (codemap standard)
For ee Go backend apps governed by `ee/docs/standards/backend-structure.md`, follow these conventions. Do not impose this layout on unrelated repositories or standalone helpers:
- HANDLER_STRUCT: `backend/handler.go` defines one `Handler` struct whose named fields are sub-handlers (`Projects *ProjectHandler`). Field name = route group; type name = domain.
- SINGLE_REGISTER: all authenticated routes are registered in one `func (h *Handler) RegisterRoutes(api gin.IRouter)` — one route per line as `api.VERB("/path", h.Field.Method)`, sorted by group under `// Group` comment headers. No conditionals, no `.GET().POST()` chaining.
- POSITIONAL_AUTH: public routes live in `server.go:SetupRoutes` above the `RequireAuth` middleware call; everything in `RegisterRoutes` is authenticated by position. The API group is created with `ginutil.NewTracedGroup`.
- Naming: `handlers_<domain>.go` per domain, struct `<Domain>Handler`, constructor `New<Domain>Handler`, all methods on receiver `*<Domain>Handler`.

## Tooling
- Workspace-aware: inspect `go.mod`, any `go.work`, and project instructions; run checks from the applicable module/workspace roots rather than assuming every repo uses a workspace.
- VALIDATION: retain affected Go formatting, vet, and regression checks plus applicable project/milestone gates under the governing execution policy. Use the existing harness; absent a convention, relevant formatting and a minimal regression are a floor, not a replacement for security, money-path, or release qualification. Execution needs actual authority; report blocked checks rather than running them under source/static-only scope.
- FAILURE_BOUNDARY: Report unrelated pre-existing failures; do not expand scope to fix them.
- Host tooling may include golangci-lint, gosec, and govulncheck (`~/go/bin`); verify availability without installing merely for a narrow correction.
- GOWORK_CHECK: before claiming a published dependency consumer works, inspect `replace`/vendor selection and verify the intended version with `GOWORK=off go build ./...` and applicable consumer tests under authorized network/cache policy. Disabling the workspace alone does not disable module replacements or vendoring.
- In the ee repo use the `tests [app]` script (on PATH via direnv; auto-detects the app from `$PWD`) instead of assembling lint/test invocations by hand.

## Error Handling
- WRAP: `fmt.Errorf("doing thing: %w", err)` — add context at each layer, preserve the chain.
- NO_SWALLOW: every error is handled or returned. No `_ = fn()`, no empty catch blocks.
- BOUNDARY: map errors to HTTP status codes in handlers/middleware, never inside stores or services.

## Testing
- Table-driven tests with named cases; `*_test.go` beside the source file.
- Run per-module respecting `go.work`; use the published-consumer check above for versioned dependency claims.

## Anti-Patterns
The shared-module and route/layout anti-patterns below apply only where those project conventions govern the code.
- REIMPLEMENT: writing an auth/middleware/logging/HTTP helper that exists in go-shared
- BARE_HANDLERS_GO: domain handler methods in a grab-bag `handlers.go` instead of `handlers_<domain>.go`
- ROUTE_SCATTER: route registrations outside `RegisterRoutes` (authenticated) or `SetupRoutes` (public)
- INLINE_ROUTE_CONDITIONAL: `if cfg.FeatureX { ... }` inside `RegisterRoutes`
- CHAINED_ROUTES: `api.GET(...).POST(...)` chains
- SERVER_RECEIVER: domain handler methods with `*Server` receivers instead of `*<Domain>Handler`
