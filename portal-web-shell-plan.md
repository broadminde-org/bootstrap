# Portal — Unified Web Shell (Standalone Repo) — Execution Plan

Supersedes `/home/luke/ee/.kilo/plans/1789331574454-portal-web-shell.md` (v1, still in ee). All facts below were verified against this host on 2026-09-14.

## Executor context (read first)

- **Your workspace:** `~/portal` — a NEW standalone private repo `github.com/broadminde-org/portal`. It starts empty; you create everything in it.
- **How go-shared is consumed (read carefully):** as an ordinary **remote Go module** — `require github.com/broadminde-org/go-shared v1.0.0` in go.mod, fetched by the Go toolchain over SSH. The host is already provisioned: git rewrites `https://github.com/broadminde-org/go-shared` → `git@github-go-shared:…` (deploy-key alias, `~/.gitconfig` + `~/.ssh/hosts.d/github-go-shared.conf`) and `GOPRIVATE=github.com/broadminde-org/*` is set in `~/.config/go/env`.
  - **NEVER** add a `replace` directive, a `go.work` file, or any reference to a filesystem path for go-shared.
  - `/home/luke/go-shared` is an optional read-only source clone for browsing APIs — the build does NOT need it. If your file tools can't see it (sandbox), ignore it and rely on the package names quoted in this plan.
- **Read-only pattern references** (do NOT modify): ee monorepo at `/home/luke/ee` (e.g. copy shapes from `/home/luke/ee/apps/enki/...`). If your file tools can't read outside `~/portal`, proceed from the inline instructions anyway and ask the user for specific file contents only when truly blocked.
- This plan file lives in `~/bootstrap` (host workspace), not in your workspace and not in ee.
- If any Step 0 prerequisite fails, stop and report before writing code.
- Do not use ee's MCP tools or scripts — they only know ee apps. All commands run in `~/portal`.

## Product summary

Web shell/dashboard for broadminde UIs. Top navbar (logo → dashboard, one nav item per registered app, user-menu stub) + workspace swapping between app UIs. Third-party apps (Woodpecker CI, NetBird) embed via **iframe** from their existing subdomains. Static YAML app registry with hot-reload + health polling. No auth in v1 (private overlay only; seams left for later). `type: native` reserved in schema for future first-party embedding.

## Step 0 — Environment prerequisites (verify, then proceed)

```bash
git config --global --get-regexp 'url\..*insteadof' | grep go-shared   # git@github-go-shared rewrite present
go env GOPRIVATE                                                       # includes github.com/broadminde-org/*
git ls-remote git@github-go-shared:broadminde-org/go-shared.git HEAD   # deploy key works
go version                                                             # 1.26.x
node --version                                                         # >= 22
cat ~/infra/caddy/central.json                                         # central Caddy present
command -v caddy-route                                                 # registration CLI on PATH
docker network ls | grep -w edge                                       # edge network exists
npm view @broadminde-org/frontend version                                          # must print a version, not 401
```

**GitHub Packages auth note:** npm auth for `@broadminde-org/*` is provisioned host-wide (user-level `~/.npmrc`) by a bootstrap user init step — handoff: `/home/luke/bootstrap/1789334444179-npm-packages-auth-handoff.md` (execution plan: `/home/luke/bootstrap/1789334444179-npm-packages-auth-execution.md`). The check above must succeed **with no env vars set**. If it 401s, the bootstrap step hasn't run or its token is invalid — stop and tell the user to run `~/bootstrap/user/init.sh 98` (step `98-npm-shared`; requires `GITHUB_PACKAGES_TOKEN` in `~/bootstrap/.env` per the handoff). Never add tokens to the portal repo itself. (The `frontend-shared-access` rule against Packages tokens applies to the *ee* repo, not to portal — but host-level user config keeps portal clean too.)

If `git ls-remote` fails with `Permission denied (publickey)`: the go-shared deploy key isn't provisioned in your environment — stop and ask the user (provisioning is `bootstrap user/init.d/99-go-shared`; do not rewire SSH config yourself). If `go get`/`go mod download` fails later despite ls-remote working, ask the user to run `cd ~/portal && go mod download` in their own shell once — the per-user module cache (`~/go/pkg/mod`) is shared, so subsequent builds work without network access to GitHub.

**`GITHUB_PACKAGES_TOKEN` is not part of this plan.** Portal never reads it; npm auth is entirely the user-level `~/.npmrc` from the bootstrap step. The Step 0 `npm view` check (run with no env vars) is the only auth gate — if it passes, Step 3 `npm install` works.

## Step 1 — Repo scaffold

1. Create the repo (prefer `gh repo create broadminde-org/portal --private`; if `gh` is unavailable or unauthorized, ask the user to create it) and clone to `~/portal`.
2. Layout:

```
~/portal/
  backend/            # Go module code (package main)
    apps.yaml
  frontend/           # SvelteKit app
  scripts/            # build, tests, dev, stack (see Step 4)
  init.sh, init.d/    # host provisioning + caddy registration (Step 5)
  caddy/portal.caddy.tmpl
  go.mod              # module github.com/broadminde-org/portal  (repo root)
  Dockerfile  docker-compose.yml
  .env.example  .gitignore  AGENTS.md  README.md
```

3. Go module setup (run exactly this — no `go.work`, no `replace`):
   ```bash
   cd ~/portal
   go mod init github.com/broadminde-org/portal
   go get github.com/broadminde-org/go-shared@v1.0.0 github.com/broadminde-org/go-shared/web@v1.0.0
   ```
   The fetch works because of the host-level git rewrite + `GOPRIVATE` verified in Step 0. (Versions per `/home/luke/ee/apps/enki/go.mod`.)
4. `.gitignore`: `node_modules`, `dist`, `.env`, `frontend/.svelte-kit`, `frontend/build`, `backend/static/built`, `*-results/`.
5. README documents the known limitations (see bottom of this plan).

## Step 2 — Backend (`backend/`, gin)

Copy the shape from `/home/luke/ee/apps/enki/backend/` (`main.go`, `config.go`, `server.go` — read them first). Key adaptations:

- `main.go`: ldflags vars `Version/BuildNumber/GitSHA/BuildTime`, signal.NotifyContext graceful shutdown (copy enki's verbatim, rename).
- `config.go`: `envutil.EnvOr`/`EnvInt` from `github.com/broadminde-org/go-shared/envutil`. Fields: `ListenAddr` (`LISTEN_ADDR`, default `:8100` — port is free; taken locally: 8080, 8090–92, 8095–96), `LogLevel`, `StaticDir` (`static/built`), `AppsConfigPath` (`PORTAL_APPS_CONFIG`, default `backend/apps.yaml` in dev, `/app/apps.yaml` in image), plus **unused placeholder fields** `AuthDevMode`, `OIDCIssuerURL`, `SessionSecret` (auth seam).
- `registry.go`: YAML load → validated `[]App`; `fsnotifyutil.New({Path, WatchType: fsnotifyutil.WatchFile, OnChange: reload})` (`github.com/broadminde-org/go-shared/fsnotifyutil` — debounced, handles file-not-yet-existing); atomic swap via `atomic.Pointer` or RWMutex. Unknown `type` is kept and rendered as "unsupported" frontend-side — not an error.
- `health.go`: background poller, 30s interval, per-app 5s timeout, redirect-following client, results map under RWMutex. **Status rule: transport error/timeout → `down`; HTTP 502/503/504 → `down` (Caddy answers these for dead upstreams — the original "any response = up" rule is WRONG); any other status incl. 401/403/404 → `up`; before first check → `unknown`.** Run one check immediately at startup, don't wait 30s.
- `server.go`: gin router; `GET /api/apps` (registry merged with cached status: `{slug,name,url,icon,description,type,order,status,last_checked}`), `GET /api/apps/:slug`, healthz/readyz via `github.com/broadminde-org/go-shared/web/ginutil` health helper; no-op `authMiddleware` passthrough wrapping `/api/*` (auth seam); SPA serving via `ginutil.SPAMiddleware({StaticDir: cfg.StaticDir})` — do NOT hand-roll fallback logic, it already excludes `/api/`, `/healthz`, `/readyz`.
- `apps.yaml` seed (Woodpecker + NetBird):

```yaml
apps:
  - slug: woodpecker
    name: Woodpecker CI
    url: https://ci.broadminde.org
    health_url: http://woodpecker-server:8000   # direct on edge net: bypasses the Caddy IP ACL that 404s off-mesh traffic
    icon: git-branch
    description: CI pipelines
    type: iframe
    enabled: true
    order: 10
  - slug: netbird
    name: NetBird
    url: https://birb.broadminde.org
    health_url:                                # unset → defaults to url (fine: any non-5xx = up)
    icon: network
    description: Mesh VPN admin
    type: iframe
    enabled: true
    order: 20
```

- Tests: `registry_test.go` (valid load, unknown type tolerated, hot-reload swap), `health_test.go` with `httptest` — **401→up, 502→down, timeout→down** (the 502 case is mandatory).

**Acceptance:** `cd ~/portal && go build ./... && go vet ./... && go test ./...` all green.

## Step 3 — Frontend (`frontend/`, SvelteKit 5 runes)

1. `frontend/.npmrc` (committed) — registry mapping ONLY, no authToken line:
   ```
   @broadminde-org:registry=https://npm.pkg.github.com
   ```
   Auth comes from the user-level `~/.npmrc` provisioned by the bootstrap init step (Step 0 note). Do NOT add a `_authToken=${GITHUB_PACKAGES_TOKEN}` line: project config overrides user config, and an unset env var would replace working user-level auth with an empty token → 401.
   `package.json`: `"@broadminde-org/frontend": "^2.0.0"`; devDeps aligned with `/home/luke/ee/package.json` to avoid version skew (svelte ^5.55.3, @sveltejs/kit ^2.57.1, @sveltejs/adapter-static ^3.0.10, vite ^8.0.8, @sveltejs/vite-plugin-svelte ^7.0.0, tailwindcss ^4.2.2, svelte-check ^4.4.6, typescript ^5.9.3) + `lucide-svelte ^1.0.1`.
2. `vite.config.ts`: shared `createViteConfig` from `@broadminde-org/frontend/viteConfig` (`backendTarget` from `resolveBackendPort()`); `svelte.config.ts` via `@broadminde-org/frontend/svelteConfig` (adapter-static — monorepo standard). Reference: `/home/luke/ee/apps/enki/frontend/`.
3. `src/app.css`: import `@broadminde-org/frontend/base.css` + theme css per enki's `src/app.css`.
4. `src/routes/+layout.svelte`: `TopNavbar` (from package root), `VersionFooter`, theme-cycle button adapted from `/home/luke/ee/apps/enki/frontend/src/routes/+layout.svelte` with localStorage key **`portal-theme`**. Navbar `items` built from `GET /api/apps` → `NavItem[]` (`href: /apps/{slug}`, lucide icon resolved from the `icon` string), `appName="Portal"`, `appHref="/"`. `currentPath` from `$page.url.pathname`. `userMenu` stub (avatar → `/profile`, no logout).
5. `src/routes/+layout.ts` (or `+page.ts` on `/`): fetch `/api/apps`; **re-fetch every 15s** (SvelteKit `invalidate('/api/apps')` on interval in layout `onMount`, cleaned up on destroy) — status dots and hot-reload visibility both depend on this.
6. `src/routes/+page.svelte`: `PageShell` + tile grid; tile = lucide icon + name + description + `StatusBadge` from `status`; click → `/apps/{slug}`; hide `enabled:false`.
7. `src/routes/apps/[slug]/+page.svelte`: full-bleed iframe (`flex:1; border:none; width:100%`), `src`=app `url`, `title`=name. Sandbox:
   `sandbox="allow-forms allow-modals allow-popups allow-popups-to-escape-sandbox allow-same-origin allow-scripts allow-downloads"` `allow="clipboard-read; clipboard-write"`.
   Code comment required: *allow-same-origin+allow-scripts nullify sandbox isolation — kept for functionality; the security boundary is the private network + per-app Caddy ACLs, not the sandbox.*
   Loading spinner until iframe `load` fires; if API says `down`, show `AlertBanner` above the iframe (do not block render — status may be stale). `type !== 'iframe'` → placeholder.
8. `src/routes/profile/+page.svelte`: static stub ("Local user — auth not enabled"). No `/login` route.

**Acceptance:** `npm install && npm run check && npm run build` clean in `frontend/`.

## Step 4 — Scripts + dev loop

Minimal scripts in `~/portal/scripts/` (on PATH via a repo `.envrc` containing `PATH_add "$PWD/scripts"`, same style as ee), adapted from `/home/luke/ee/scripts/tests` style:

- `tests`: `go build/vet/test ./...` + `golangci-lint` if present + frontend `npm run check` + `npm run lint`.
- `dev up|down`: backend on `:8100` (air optional), `vite dev` proxying `/api`→`:8100`; vite `--host 0.0.0.0` only if you want central-Caddy dev access.
- `build`: frontend build → `backend/static/built/`, `go build -o dist/portal` with ldflags (`-X main.Version=...` per enki), docker build.
- `stack up|down`: docker compose.

**Acceptance:** `dev up` → dashboard on the vite port shows seeded apps with live status; kill/restart a target and watch the dot flip within ~45s (30s poll + 15s refresh).

## Step 5 — Docker, compose, init, portal Caddy

- `Dockerfile` (copy `/home/luke/ee/apps/enki/Dockerfile` pattern): alpine runtime, `COPY dist/portal ./portal`, `COPY dist/frontend ./static/built`, `COPY backend/apps.yaml /app/apps.yaml`, non-root USER, `EXPOSE 8100`, HEALTHCHECK on `:8100/healthz`. **Go build happens on host** (deploy key + npm token live there), never inside docker build.
- `docker-compose.yml`: service `portal`, joins external `edge` network (name `edge`), no published host port in prod, `LISTEN_ADDR=:8100`.
- `init.sh` + `init.d/`: render + register the portal snippet, gated on central-Caddy discovery:

```bash
if [ -f "$HOME/infra/caddy/central.json" ] && command -v caddy-route >/dev/null 2>&1; then
  tmpfile=$(mktemp)
  sed "s|\${APP_HOST}|$APP_HOST|g" caddy/portal.caddy.tmpl > "$tmpfile"
  caddy-route register portal "$tmpfile"; rm -f "$tmpfile"
else
  echo "NOTE: central caddy not detected — register manually"
fi
```

- `caddy/portal.caddy.tmpl`:

```caddyfile
${APP_HOST} {
    tls {
        dns acmedns /etc/caddy/acmedns.json
    }
    reverse_proxy portal:8100
}
```

(`APP_HOST` default `portal.broadminde.org`. DNS-01/acmedns is mandatory; site blocks only — no global options. `caddy-route deregister portal` on teardown.)

## Step 6 — Frame-policy edits for embedded apps (host-level, OUTSIDE ~/portal)

`~/infra/caddy/routes.d/*.caddy` are **rendered artifacts — do not edit them directly.** Locate the source templates first:

```bash
grep -rl "frame-ancestors" ~/ --include="*.caddy*" --include="*.tmpl" 2>/dev/null | grep -v routes.d
grep -rl "ci.broadminde.org\|birb.broadminde.org" ~/bootstrap ~/*/init.d ~/*/caddy 2>/dev/null
```

1. **NetBird**: its dashboard CSP (routes.d/netbird.caddy line 58) pins `frame-ancestors 'self'` — extend to `frame-ancestors 'self' https://portal.broadminde.org` **in the source template** (rendered by that deployment's `init.d/20-render`), re-render, `caddy-route register netbird <rendered>`.
2. **Woodpecker**: `ci-dashboard.caddy` has no CSP/XFO (verified) — add `header_down Content-Security-Policy "frame-ancestors 'self' https://portal.broadminde.org"` to its `reverse_proxy` block **in its source template** (rendered from `WOODPECKER_HOST` by its init.sh), re-register as `ci-dashboard`. Also strip any `X-Frame-Options` if present (`header_down -X-Frame-Options`).
3. Verify: `curl -sI https://ci.broadminde.org | grep -i 'content-security\|x-frame'` and same for `birb.`.

## Step 7 — Final validation

1. `tests` green (incl. the mandatory 401→up / 502→down health tests).
2. `stack up`: `caddy-route list` shows portal; `https://portal.broadminde.org` serves over TLS; dashboard shows live statuses.
3. `/apps/woodpecker` and `/apps/netbird` render in iframes with **no CSP/XFO console errors**.
4. Refresh on `/apps/{slug}` deep-links correctly (SPA fallback via ginutil).
5. Edit `apps.yaml` → backend list changes without restart; UI reflects within one 15s poll cycle.
6. README limitation confirmed: Woodpecker login inside the iframe fails at the IdP redirect → log in at `ci.broadminde.org` directly → iframe then works (same-site cookies, shared eTLD+1 `broadminde.org`).

## Known limitations (put in README)

- Embedded-app login inside iframes hits the IdP's own frame policy — authenticate at the app's subdomain first.
- No iframe↔address-bar deep-link sync in v1.
- No auth on the shell — never expose portal.broadminde.org beyond the overlay.

## Deferred (do not build)

- **Auth:** `.github/instructions/auth-runtime-modes.instructions.md` four-mode pattern; go-shared `web/session` + `web/auth`, then OIDC via `web/oidc` + `web/zitadellogin`; shared `LoginForm`/`stores/auth` frontend-side. Cross-app SSO into iframes is out of scope even then (each app keeps its own auth until a shared-Zitadel architecture).
- **Discovery:** mDNS/overlay writer feeding the stable `GET /api/apps` shape; registry likely moves to Postgres then.
- **`type: native`**: Svelte custom-element embedding + postMessage deep-link protocol, designed when the first first-party app embeds.

## Open questions (resolve at execution time)

- Repo name/path confirmed as `broadminde-org/portal` → `~/portal`; agent creates via `gh` if authorized, else user creates.
- Frontend dev port: suggest 3010 (enki uses 3006; avoid collision).
- Exact filesystem location of the netbird + woodpecker Caddy source templates (Step 6 grep finds them).
