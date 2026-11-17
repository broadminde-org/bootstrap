---
name: webapp-testing
description: >-
  Toolkit for interacting with and testing local web applications. Playwright
  MCP is seeded in Kilo config; Node Playwright and browser binaries
  are installed for the deploy user on dev hosts. Verify current state before
  claiming they are missing.
  Uses the Playwright MCP browser tools for interactive testing, debugging UI
  behavior, screenshots, and browser logs; falls back to Python Playwright
  scripts for repeatable automation.
license: Complete terms in LICENSE.txt
metadata:
  category: development
  source:
    repository: 'https://github.com/ComposioHQ/awesome-claude-skills'
    path: webapp-testing
    license_path: webapp-testing/LICENSE.txt
---

# Web Application Testing

Two toolkits may be available in this environment. Pick per the decision tree.

## Authorization Boundary

MCP transport denial/unavailability does not itself deny the underlying
documentation or testing action. An already-available CLI/project harness
is permissible only when that action, Bash, network, and every required side
effect are independently authorized. Denial of the underlying action,
Bash, or network must be reported, not circumvented.

`npx` package resolution and `uv run --with ...` environment/package/cache
preparation are separate side effects. Do not install tools/browsers,
prepare environments, start servers, or write artifacts without applicable
authority. Inspect local availability and invocation effects first; report
missing checks rather than treating a fallback as permission. Screen
console/network evidence and screenshots for secrets before reporting.

## Host Capability Baseline

Bootstrap separates MCP configuration, per-user binaries, and system libraries:

- User step `37-kilo-settings` seeds `~/.config/kilo/kilo.json` with the
  Playwright MCP on a fresh configuration. Existing configs are not overwritten;
  inspect the live config and the active session's MCP permissions.
- On `dev` hosts, user step `39-playwright` installs `@playwright/test` into
  the deploy user's default nvm Node tree (`~/.nvm/versions/node/v*/`) and
  Chromium, Firefox, and WebKit into that user's `~/.cache/ms-playwright`.
  Root step `06-playwright-deps` installs the required system libraries.
- On non-`dev` hosts these steps are skipped, but disabling a capability
  does not uninstall browsers or libraries from an earlier run.

Do not repeat historical claims that "Playwright is not installed" without
validating the current deploy-user environment:

- Check whether `playwright_browser_*` tools are available **to this agent**;
  missing tools can mean MCP permission is denied (for example, the deployed
  `test-engineer` agent), a stale or customized Kilo config, or MCP startup
  failure, not missing browsers.
- Run `command -v playwright` and `playwright --version` as the deploy user.
  If absent from PATH, inspect `~/.nvm/alias/default` and source
  `~/.nvm/nvm.sh` to select `nvm use default` before concluding it is absent.
  An editor server predating provisioning may need an operator restart;
  do not restart it without specific authority.
- Inspect `~/.cache/ms-playwright` for the current user. The cache may have
  been cleared by maintenance; a directory alone does not prove launch works.
- If availability matters and launch side effects are authorized, try launching a browser and report its actual error.
  Missing shared libraries require the operator to run root-tier provisioning;
  agents must not attempt privilege escalation.

Distinguish these failures explicitly:

- **Not provisioned for this user:** `dev` is disabled or step `39-playwright`
  has not completed, and the executable/cache are absent.
- **MCP unavailable:** inspect live config, agent permissions, and startup error;
  use an already-available Node Playwright CLI or project test only under the
  independent authorization boundary above. Do not treat MCP permission
  denial as a missing browser install or authority to bypass action denial.
- **System libraries missing:** browser binaries exist but launch reports
  missing shared libraries; root-tier `06-playwright-deps` must be run manually
  by the operator on a supported distro.
- **Browser installed but unavailable:** launch error despite installed
  executable/cache; report the launch error.
- **App/server blocked:** browser is installed, but the dev server or backend
  cannot start; do not report Playwright as missing.
- **Python Playwright absent:** bootstrap does not provision this package;
  use existing Node/project tooling where independently authorized. Python
  environment/package preparation requires separate specific authority.

## Toolkit 1 (preferred): Playwright MCP browser tools

The Playwright MCP (`@playwright/mcp`) is seeded in
`~/.config/kilo/kilo.json` by bootstrap step `37-kilo-settings` on new configs.
When enabled and permitted for this agent, its tools appear as
`playwright_browser_*` — no browser lifecycle or scripts to manage.

Use it for: verifying frontend functionality, debugging UI behavior,
capturing screenshots, reading console logs and network requests.

**Workflow (reconnaissance-then-action):**

1. Discover the actual app URL/port from project configuration or observed
   server output. If the server is not running, start it through the available
   tracked process tool only when authorized, or report the server blocker.
2. `playwright_browser_navigate` to the URL.
3. `playwright_browser_snapshot` — returns the accessibility tree with a
   `ref` for every interactive element. **Act on these refs, never on
   guessed selectors.**
4. Interact: `playwright_browser_click`, `playwright_browser_type`,
   `playwright_browser_fill_form`, `playwright_browser_press_key`.
5. Verify the result: re-snapshot, `playwright_browser_take_screenshot`,
   `playwright_browser_console_messages`,
   `playwright_browser_network_requests`.
6. `playwright_browser_close` when done.

## Toolkit 2: Python Playwright scripts (repeatable automation)

Use only when the run must be saved and re-executed: CI-style checks,
regression scripts, or multi-server lifecycle management.

**Bootstrap does not pre-install Python `playwright`** (`39-playwright`
provisions Node tooling on dev hosts; `20-python` provides uv + interpreter).
Prefer an existing project/Node test harness or already-prepared Python
environment. The following example is permissible only with specific
authority for uv environment/package preparation and the test's side effects:

```bash
uv run --with playwright python your_automation.py
```

**Helper scripts available**:
- `scripts/with_server.py` - Manages server lifecycle (supports multiple servers)

Inspect relevant source/local usage before execution when needed to establish
side effects. Use `--help` only when known safe and authorized; do not treat
scripts as opaque black boxes when their effects are uncertain.

## Decision Tree: Choosing Your Approach

```
Underlying test action and side effects authorized?
  No -> report blocker; do not switch transport to bypass it.
  Yes -> one-off and MCP permitted -> MCP snapshot/action/verify.
      -> repeatable or MCP unavailable -> existing project/Node harness,
         or already-prepared Python environment with independently allowed Bash/network.
      -> package/environment preparation needed -> obtain specific authority
         or report unavailable; no implicit npx/uv installation.
```

## Server Lifecycle Examples

Only after inspecting the helper and authorizing both server lifecycle and
environment preparation, adapt these examples to the project's actual
commands and configured ports. The variables below are operator-supplied
example placeholders, not new shared-runner configuration keys:

```bash
./scripts/with_server.py --server "$FRONTEND_DEV_CMD" --port "$FRONTEND_PORT" -- \
  uv run --with playwright python your_automation.py
```

**Multiple servers (e.g., backend + frontend):**
```bash
./scripts/with_server.py \
  --server "$BACKEND_DEV_CMD" --port "$BACKEND_PORT" \
  --server "$FRONTEND_DEV_CMD" --port "$FRONTEND_PORT" -- \
  uv run --with playwright python your_automation.py
```

In scripts, include only the required Playwright logic when server lifecycle
is managed by the helper. Obtain the app URL from project configuration or
observed output, use readiness assertions appropriate to that app, and close
the browser. A script is not required for a one-off authorized MCP check.

## Common Pitfalls

- ❌ **Don't** require a Python script for a one-off interactive check;
  prefer authorized MCP or independently authorized existing tooling.
- ❌ **Don't** assume Python `playwright` exists or prepare it implicitly.
  Inspect existing tooling first. Missing Python tooling does not mean that
  bootstrap-managed Node packages or browser binaries are missing; a
  stdlib-only helper can still start mutating server/test operations.
- ❌ **Don't** inspect the DOM before waiting for `networkidle` on dynamic
  apps (script path) — or before taking a fresh snapshot (MCP path).
- ✅ **Do** wait for `page.wait_for_load_state('networkidle')` before
  inspection in scripts.

## Best Practices (script path)

- Use bundled scripts only when their invocation effects are understood and authorized; read relevant source when needed rather than executing first by default.
- Use `sync_playwright()` for synchronous scripts
- Always close the browser when done
- Use descriptive selectors: `text=`, `role=`, CSS selectors, or IDs
- Add appropriate waits: `page.wait_for_selector()` or `page.wait_for_timeout()`

## Reference Files

- **examples/** - Examples showing common patterns (script path):
  - `element_discovery.py` - Discovering buttons, links, and inputs on a page
  - `static_html_automation.py` - Using file:// URLs for local HTML
  - `console_logging.py` - Capturing console logs during automation
