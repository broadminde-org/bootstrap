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
  Restart an editor server that predates `12-bashrc`/`35-node` provisioning.
- Inspect `~/.cache/ms-playwright` for the current user. The cache may have
  been cleared by maintenance; a directory alone does not prove launch works.
- If availability matters, try launching a browser and report its actual error.
  Missing shared libraries require the operator to run root-tier provisioning;
  agents must not attempt privilege escalation.

Distinguish these failures explicitly:

- **Not provisioned for this user:** `dev` is disabled or step `39-playwright`
  has not completed, and the executable/cache are absent.
- **MCP unavailable:** inspect live config, agent permissions, and startup error;
  use the installed Node Playwright CLI or a project test when MCP access is
  denied. Do not treat MCP permission denial as a missing browser install.
- **System libraries missing:** browser binaries exist but launch reports
  missing shared libraries; root-tier `06-playwright-deps` must be run manually
  by the operator on a supported distro.
- **Browser installed but unavailable:** launch error despite installed
  executable/cache; report the launch error.
- **App/server blocked:** browser is installed, but the dev server or backend
  cannot start; do not report Playwright as missing.
- **Python Playwright absent:** expected by design; use
  `uv run --with playwright` for Python automation.

## Toolkit 1 (preferred): Playwright MCP browser tools

The Playwright MCP (`@playwright/mcp`) is seeded in
`~/.config/kilo/kilo.json` by bootstrap step `37-kilo-settings` on new configs.
When enabled and permitted for this agent, its tools appear as
`playwright_browser_*` — no browser lifecycle or scripts to manage.

Use it for: verifying frontend functionality, debugging UI behavior,
capturing screenshots, reading console logs and network requests.

**Workflow (reconnaissance-then-action):**

1. Make sure the dev server is running (e.g. Vite's default port 5173).
   If not, start it as a background process or ask the user to start it.
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

**The Python `playwright` package is NOT pre-installed** (the environment
installs Node `@playwright/test` via `35-node`, and `20-python` provides
only uv + interpreter). Run scripts through uv's ephemeral environment:

```bash
uv run --with playwright python your_automation.py
```

**Helper scripts available**:
- `scripts/with_server.py` - Manages server lifecycle (supports multiple servers)

**Always run scripts with `--help` first** to see usage. DO NOT read the source until you try running the script first and find that a customized solution is absolutely necessary. These scripts can be very large and thus pollute your context window. They exist to be called directly as black-box scripts rather than ingested into your context window.

## Decision Tree: Choosing Your Approach

```
User task → Must the run be saved/repeated? (CI, regression, multi-server)
    ├─ No, MCP permitted → Playwright MCP tools (Toolkit 1)
    │         1. Start dev server if needed
    │         2. Navigate → snapshot → act on refs → verify
    │
    └─ Yes, or MCP unavailable → Python script path (Toolkit 2)
              ├─ Server already running? → write script, run with
              │   uv run --with playwright python your_automation.py
              └─ Need server lifecycle? →
                   ./scripts/with_server.py --help  (executable, stdlib-only)
                   then wrap: ./scripts/with_server.py \
                     --server "npm run dev" --port 5173 -- \
                     uv run --with playwright python your_automation.py
```

## Example: with_server.py (single server)

```bash
./scripts/with_server.py --server "npm run dev" --port 5173 -- \
  uv run --with playwright python your_automation.py
```

**Multiple servers (e.g., backend + frontend):**
```bash
./scripts/with_server.py \
  --server "cd backend && python server.py" --port 3000 \
  --server "cd frontend && npm run dev" --port 5173 -- \
  uv run --with playwright python your_automation.py
```

Script template — include only Playwright logic (servers are managed):
```python
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True) # Always launch chromium in headless mode
    page = browser.new_page()
    page.goto('http://localhost:5173') # Server already running and ready
    page.wait_for_load_state('networkidle') # CRITICAL: Wait for JS to execute
    # ... your automation logic
    browser.close()
```

## Common Pitfalls

- ❌ **Don't** write a Python script for a one-off interactive check — use
  the MCP browser tools instead.
- ❌ **Don't** assume the Python `playwright` package exists — use
  `uv run --with playwright python …`. This warning does not mean that the
  bootstrap-managed Node Playwright package or browser binaries are missing.
  (`with_server.py` itself is stdlib-only and executable: `./scripts/with_server.py`
  works directly.)
- ❌ **Don't** inspect the DOM before waiting for `networkidle` on dynamic
  apps (script path) — or before taking a fresh snapshot (MCP path).
- ✅ **Do** wait for `page.wait_for_load_state('networkidle')` before
  inspection in scripts.

## Best Practices (script path)

- **Use bundled scripts as black boxes** - To accomplish a task, consider whether one of the scripts available in `scripts/` can help. These scripts handle common, complex workflows reliably without cluttering the context window. Use `--help` to see usage, then invoke directly.
- Use `sync_playwright()` for synchronous scripts
- Always close the browser when done
- Use descriptive selectors: `text=`, `role=`, CSS selectors, or IDs
- Add appropriate waits: `page.wait_for_selector()` or `page.wait_for_timeout()`

## Reference Files

- **examples/** - Examples showing common patterns (script path):
  - `element_discovery.py` - Discovering buttons, links, and inputs on a page
  - `static_html_automation.py` - Using file:// URLs for local HTML
  - `console_logging.py` - Capturing console logs during automation
