---
name: webapp-testing
description: >-
  Toolkit for interacting with and testing local web applications.
  Uses the Playwright MCP browser tools for interactive testing, debugging
  UI behavior, screenshots, and browser logs; falls back to Python
  Playwright scripts for repeatable automation.
license: Complete terms in LICENSE.txt
metadata:
  category: development
  source:
    repository: 'https://github.com/ComposioHQ/awesome-claude-skills'
    path: webapp-testing
    license_path: webapp-testing/LICENSE.txt
---

# Web Application Testing

Two toolkits are available in this environment. Pick per the decision tree.

## Toolkit 1 (preferred): Playwright MCP browser tools

The Playwright MCP (`@playwright/mcp`) is configured globally in
`~/.config/kilo/kilo.json` (deployed by bootstrap step `23-kilo-settings`).
Its tools are available in-session as `playwright_browser_*` — no installs,
no browser lifecycle to manage, no scripts to write.

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
    ├─ No → Playwright MCP tools (Toolkit 1)
    │         1. Start dev server if needed
    │         2. Navigate → snapshot → act on refs → verify
    │
    └─ Yes → Python script path (Toolkit 2)
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
- ❌ **Don't** assume `python` or the `playwright` package exists — use
  `uv run --with playwright python …`. (`with_server.py` itself is
  stdlib-only and executable: `./scripts/with_server.py` works directly.)
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
