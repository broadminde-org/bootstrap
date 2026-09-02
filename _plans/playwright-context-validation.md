# Host Context Plan — Playwright Capability Validation

**Date:** 2026-09-01
**Scope:** global Kilo context deployed by bootstrap
**Problem:** an agent reviewing `frontend-extraction-plan-b.md` repeated the stale
claim that Playwright browser binaries were unavailable, even though Playwright is
provisioned host-wide.

## Goal

Make future agents distinguish **actual missing capability** from **stale project
notes**, and make the host's Playwright provisioning model explicit enough that
browser-test blockers are not misdiagnosed.

## Root Cause

Three different concepts were conflated:

1. **Playwright MCP availability** — configured globally through
   `~/.config/kilo/kilo.json` and exposed in sessions as `playwright_browser_*`.
2. **Node Playwright installation** — global `@playwright/test`, plus browser
   binaries under `~/.cache/ms-playwright`, installed by user-tier step
   `35-node`.
3. **Python Playwright installation** — intentionally not installed permanently;
   scripts should use `uv run --with playwright`.

A historical execution note said "Playwright browser binaries are not installed."
That note was treated as current host truth without validating the actual host
context. The correct diagnosis was: Playwright was available; browser smoke tests
were blocked separately by backend/dev-server failures.

## Current Sources Of Truth

### Bootstrap provisioning

- `init.d/06-playwright-deps/run.sh`
  - Root-tier system dependencies required to launch Chromium, Firefox, and
    WebKit.
  - Capability-gated by `dev`.
- `user/init.d/35-node/run.sh`
  - Installs Node through nvm.
  - Installs global packages from `packages.txt`.
  - Runs `npx playwright install chromium firefox webkit` when
    `@playwright/test` is present.
- `user/init.d/35-node/packages.txt`
  - Includes `@playwright/test`.
- `user/init.d/30-scripts/scripts/maintain.d/85-playwright-cache.sh`
  - Can intentionally remove `~/.cache/ms-playwright` during maintenance.
  - This means cache existence is host state, not permanent policy.

### Global Kilo context

- `~/.config/kilo/kilo.json`
  - Configures the Playwright MCP using `npx -y @playwright/mcp@0.0.38`.
- `~/.kilo/skills/webapp-testing/SKILL.md`
  - Says to prefer Playwright MCP for interactive browser checks.
  - Correctly says the Python `playwright` package is not pre-installed.
  - Does **not** currently provide a mandatory validation checklist for
    capability claims.

### Bootstrap source for global context

- `user/init.d/37-kilo-settings/_config/kilo/kilo.json`
  - Source for `~/.config/kilo/kilo.json`.
- `user/init.d/37-kilo-settings/_kilo/skills/webapp-testing/SKILL.md`
  - Source for `~/.kilo/skills/webapp-testing/SKILL.md`.
- `user/init.d/37-kilo-settings/run.sh`
  - Deploys `_config/kilo` to `~/.config/kilo` and `_kilo` to `~/.kilo`.
  - Syncs skills without deleting user-installed additions.
  - Diffs `kilo.json`/`kilo.jsonc` instead of overwriting existing files.

## Proposed Changes

### 1. Update the bootstrap source skill

Edit:

```text
user/init.d/37-kilo-settings/_kilo/skills/webapp-testing/SKILL.md
```

Add a short section near the top, before the toolkit decision tree:

```markdown
## Host Capability Baseline

On bootstrap-provisioned hosts, assume Playwright browser tooling is available
unless proven otherwise:

- The Playwright MCP is configured in `~/.config/kilo/kilo.json`.
- Bootstrap user step `35-node` installs global `@playwright/test` and browser
  binaries under `~/.cache/ms-playwright`.
- Bootstrap root step `06-playwright-deps` installs the system libraries when
  the host has the `dev` capability enabled.

Do not repeat historical claims that "Playwright is not installed" without
validating current host state. Check at least one current signal:

- availability of `playwright_browser_*` MCP tools in the active session;
- `command -v playwright`;
- browser directories under `~/.cache/ms-playwright`.

Distinguish these failures explicitly:

- **Capability absent:** no MCP tools, no Playwright executable, no browser
  cache, and bootstrap state does not provision it.
- **Browser installed but unavailable:** MCP or launch error despite installed
  executable/cache; report the launch error.
- **App/server blocked:** browser is installed, but the dev server or backend
  cannot start; do not report Playwright as missing.
- **Python Playwright absent:** expected by design; use
  `uv run --with playwright` for Python automation.
```

Also update the existing "Common Pitfalls" entry:

```markdown
- ❌ **Don't** assume `python` or the `playwright` package exists — use
  `uv run --with playwright python …`. (`with_server.py` itself is
  stdlib-only and executable: `./scripts/with_server.py` works directly.)
```

Clarify that this warning means the **Python package** is not pre-installed, not
that browser binaries or the Node Playwright package are missing.

### 2. Update the live host context during rollout

After editing the bootstrap source:

1. Run the user-tier deployment step for the deploy user:

   ```bash
   ./user/init.sh 37-kilo-settings
   ```

2. Confirm the live skill is updated:

   ```bash
   grep -n "Host Capability Baseline" ~/.kilo/skills/webapp-testing/SKILL.md
   ```

3. Confirm MCP configuration remains present:

   ```bash
   grep -n '"playwright"' ~/.config/kilo/kilo.json
   ```

4. Confirm Playwright installation state:

   ```bash
   command -v playwright
   ls ~/.cache/ms-playwright
   ```

Do not edit only the live `~/.kilo` copy; it is a deployed artifact and can be
overwritten by bootstrap.

### 3. Record the stale note in the EE plan

In `/home/luke/ee/frontend-extraction-plan-b.md`, correct the Step 6/7 note so it
says the smoke tests were blocked by backend/dev-server issues, not by missing
Playwright binaries.

This is project-history cleanup, not host capability documentation.

### 4. Update bootstrap codemap/docs if needed

If the bootstrap documentation's capability table or context documentation is
materially changed, update the relevant entries in:

- `codemap.md`
- `README.md`

Keep these changes narrowly scoped to capability boundaries:

- `06-playwright-deps`: OS/browser dependencies, root tier, gated by `dev`.
- `35-node`: Node, global `@playwright/test`, browser downloads, user tier.
- `37-kilo-settings`: deploys Playwright MCP config and `webapp-testing` skill.
- Python Playwright: intentionally ephemeral via uv.

## Validation Checklist

- [ ] Bootstrap source skill includes the capability-baseline section.
- [ ] Skill clearly distinguishes Node Playwright, browser binaries, MCP tools,
      and Python Playwright.
- [ ] Skill description instructs agents to verify current host state before
      repeating stale capability claims.
- [ ] `./user/init.sh 37-kilo-settings` deploys the source update.
- [ ] Live `~/.kilo/skills/webapp-testing/SKILL.md` contains the new section.
- [ ] Live `~/.config/kilo/kilo.json` still configures the Playwright MCP.
- [ ] `command -v playwright` resolves.
- [ ] `~/.cache/ms-playwright` contains Chromium, Firefox, and WebKit, or the
      absence is documented as intentional maintenance state.
- [ ] `frontend-extraction-plan-b.md` no longer says Playwright binaries were
      missing.

## Explicit Non-Goals

- Do not install Python Playwright permanently.
- Do not replace the Playwright MCP workflow with Python automation.
- Do not attempt to fix the EE backend/private-module issue in this plan.
- Do not make project plans the source of host capability truth.
- Do not overwrite accumulated live Kilo configuration; follow the existing
  diff-and-manual-merge behavior in `37-kilo-settings`.

## Expected Outcome

Future agents should say, in order of diagnosis:

1. "Playwright MCP is configured globally."
2. "Playwright executable/browser cache is present" or "the cache is absent due
   to maintenance."
3. "If browser testing is blocked, identify whether the actual failure is MCP
   startup, browser launch, frontend startup, backend startup, or application
   behavior."

They should not infer missing browser tooling from stale repo notes.
