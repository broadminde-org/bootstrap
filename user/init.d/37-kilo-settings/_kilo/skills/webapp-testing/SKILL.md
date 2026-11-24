---
name: webapp-testing
description: >-
  Guidance for interacting with and testing local web applications: frontend
  functionality, UI debugging, screenshots, browser logs, and repeatable checks.
  Routes tasks to authorized browser tools or existing project test tooling;
  standalone Python automation is conditional. Does not establish installed
  tooling, active MCP access, or runtime qualification.
license: Complete terms in LICENSE.txt
metadata:
  category: development
  source:
    repository: 'https://github.com/ComposioHQ/awesome-claude-skills'
    path: webapp-testing
    license_path: webapp-testing/LICENSE.txt
---

# Web Application Testing

Prefer existing project test tooling and tracked process supervision. Reuse an
authorized running app instead of starting another server. Standalone helpers
are only for unavailable supervision and authorized repeatable automation;
they are not the default for a one-off browser check.

**Runtime unverified:** Skill/source presence, configuration seeding, executable
or browser-cache presence, and test source do not prove active tool access,
successful browser launch, helper runtime safety, or completed qualification.
Distinguish source implementation, local testing, and live qualification; use
actual authorized evidence and report missing receipts rather than repeating
historical claims. Reading this skill or its references grants no execution authority.

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

## Capability Checks — Not Live Provisioning Claims

Bootstrap configuration, per-user binaries, system libraries, and active agent
tool visibility are separate evidence questions. Do not infer current host state
from a bootstrap step name or the presence of this skill. A disabled capability
is not proof that previously installed tools were removed.

Retrieve only evidence needed for the selected task, within current authority:

- Check whether `playwright_browser_*` tools are available **to this agent**.
  Missing tools may reflect permissions, customized/stale configuration, or MCP
  startup failure, not missing browsers. Configuration alone proves neither
  discovery nor connection. Inspect live configuration only when authorized;
  do not expose credentials or server arguments in reports.
- If execution is authorized, `command -v playwright` and `playwright --version`
  can check the current user's CLI. If absent from PATH, bounded inspection of
  `~/.nvm/alias/default` and executable paths can resolve a PATH ambiguity.
  Selecting nvm or launching a CLI requires execution authority. An editor
  server predating provisioning may need an operator restart; do not restart it
  without specific authority.
- Authorized inspection of the current user's `~/.cache/ms-playwright` can
  establish cache presence, not launch success. If launch side effects are
  authorized and relevant, report the actual browser launch result.
- Missing shared libraries require manual operator root-tier provisioning on
  a supported distro. Agents must not attempt privilege escalation.
- Python package/environment availability must be checked independently;
  missing Python Playwright does not establish missing Node/project tooling.
  Do not prepare a Python environment implicitly.

Distinguish **not provisioned for this user** (requires provisioning evidence
and absent executable/cache), **MCP unavailable** (permissions/config/startup),
**system libraries missing** (actual launch error), **browser installed but
unavailable** (other launch error), **app/server blocked**, and **Python
Playwright absent**. Do not collapse these into “Playwright is missing.”
Historical step references `37-kilo-settings`, `39-playwright`, and
`06-playwright-deps` identify possible configuration/tool/library owners, not
proof that those steps ran successfully on the current host. Inspection or
provisioning of those owners requires its own scope and authority.

## Toolkit 1 (preferred): Playwright MCP Browser Tools

Use available, permitted MCP tools for one-off frontend checks, UI debugging,
screenshots, console logs, and network requests. The transport manages browser
lifecycle, but connection, launch, navigation, and artifacts remain consequential
authorized operations. Configuration seeding is not a capability guarantee.

**Workflow (reconnaissance-then-action):**

1. Discover the actual app URL/port from project configuration or screened
   server evidence. Prefer existing supervision/project tooling. If the server
   is unavailable, start it through tracked supervision only when authorized,
   or report the server blocker. Verify HTTP/app identity, not just a TCP port.
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

## Toolkit 2: Repeatable Automation

Use only for authorized saved/repeatable checks when existing project/Node
tooling is unsuitable. Server lifecycle should still use tracked supervision
if available, independently of the choice of browser transport.

Prefer an existing project/Node test harness or already-prepared Python
environment. Run with its already-prepared interpreter, without dependency
resolution. If preparation is missing, report the blocker; a separately
approved preparation step is not part of these helpers:

```bash
"$PREPARED_PYTHON" "$AUTOMATION_SCRIPT"
```

`scripts/with_server.py` is conditional standalone Linux supervision, standard
library only, Python 3.10+. It performs no installation or browser startup
itself, but its supplied commands can have those and other side effects.
Inspect relevant source/local usage when needed to establish invocation effects.
Use `--help` only when known safe and authorized; do not treat scripts as opaque
black boxes when their effects are uncertain.

### Standalone Platform and Safety Gate

The declared supported helper platform is Python 3.10+ on 64-bit glibc Linux
x86_64/aarch64, with Linux `waitid`/`WNOWAIT` and POSIX signal masking. Other
platforms/ABIs, including macOS, are unsupported; do not introduce or assume a
less-safe fallback. It is a single-thread standalone CLI with no external
reaper, not an embedding API. Do not use Python/native SIGCHLD handlers,
concurrent `wait*` calls, signal-action races, or threaded/native-thread hosts.
Non-default SIGCHLD and native `SA_NOCLDWAIT` are rejected by source preflight.

Commands must keep descendants in owned groups: daemonization, `setsid`, and
escaping groups are unsupported, not sandboxed. Missing/reaped leader identity
must fail closed, not trigger numeric-group, listener, or name-based cleanup.
EOF is not proof that all descendants are dead. SIGKILL of the helper or host
failure cannot run cleanup; use tracked supervision for stronger guarantees.
These source restrictions are not evidence of successful runtime qualification.

Before conditional helper/example use, read
[standalone-helper-mechanics.md](references/standalone-helper-mechanics.md) for
explicit command inputs, reviewed HTTP identity, port admission, cleanup
limitations, output suppression, example invocations, and source links. This
reference is on-demand, not mandatory context for MCP-only tasks.

## Decision Tree: Choosing Your Approach

```text
Underlying test action and side effects authorized?
  No -> report blocker; do not switch transport to bypass it.
  Yes -> reuse existing supervision and project tests first.
      -> one-off and MCP permitted -> MCP snapshot/action/verify.
      -> repeatable or MCP unavailable -> existing project/Node harness,
         or already-prepared Python environment with independently allowed Bash/network.
      -> package/environment preparation needed -> obtain specific authority
         or report unavailable; no implicit npx/uv installation.
      -> standalone lifecycle needed -> verify declared platform and authority,
         read helper mechanics, or report blocker; no unsupported fallback.
```

## Common Pitfalls and Script Practices

- Do not require a Python script for a one-off interactive check.
- Do not assume Python Playwright exists or prepare it implicitly. A stdlib-only
  supervisor can still start mutating server/test operations.
- Do not use compulsory `networkidle`, elapsed sleeps, or TCP connection
  success as app readiness. Dynamic apps may never become network-idle.
- Assert app-specific locator visibility/state and expected results; take a
  fresh MCP snapshot before acting on current refs.
- Use bundled scripts only when invocation effects are understood and authorized.
- Use `sync_playwright()` for synchronous scripts; always close the browser.
- Prefer role/test-id locators and Playwright auto-waiting interactions.
- Assert observable results with `expect(locator)`, rather than fixed sleeps.

## Maintenance Reference — Not a Browser-task Queue

[maintenance-qualification.md](references/maintenance-qualification.md) owns the
retained patch record, upstream-refresh cautions, and required qualification
coverage. Preserve local helper/example repairs, test source, upstream metadata,
and both licenses on refresh. Load maintenance detail only for an explicitly
assigned maintenance/qualification task. **Its coverage is non-executable during
ordinary browser tasks unless explicitly assigned and separately authorized.**
No source/static record establishes local runtime acceptance or live qualification.
