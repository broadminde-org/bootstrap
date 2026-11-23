---
name: webapp-testing
description: >-
  Toolkit for interacting with and testing local web applications. Playwright
  MCP is seeded in Kilo config; Node Playwright and browser binaries
  are installed for the deploy user on dev hosts. Verify current state before
  claiming they are missing.
  Uses the Playwright MCP browser tools for interactive testing, debugging UI
  behavior, screenshots, and browser logs. Prefer existing supervision and
  project test tooling; standalone Python automation is conditional.
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

**Local patch record (2026-11-23):** Bootstrap modified this guidance,
`scripts/with_server.py`, and all three upstream examples; added
`examples/_support.py` and unexecuted `tests/test_supervision.py` regression
source. Retain these repairs on upstream refresh, along with
the source metadata above and both original license files. The repairs add
owned Linux process groups, HTTP app identity, output suppression, explicit
inputs, and locator assertions. Q12 additionally replaces reaping observations
with `waitid(..., WNOWAIT)`, pins leaders through all group signalling, rejects
native SIGCHLD auto-reaping before spawn, and adds UNRUN call-order/reuse and
real-fixture failure source. Source/static checks are not runtime evidence.

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
  missing tools can mean MCP permission is denied, a stale or customized Kilo
  config, or MCP startup
  failure, not missing browsers.
- Run `command -v playwright` and `playwright --version` as the deploy user.
  If absent from PATH, inspect `~/.nvm/alias/default` and installed executable
  paths. Selecting nvm or launching a CLI still requires execution authority.
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
`playwright_browser_*`. The transport manages browser lifecycle, but connection,
launch, navigation, and artifacts remain consequential authorized operations.

Use it for: verifying frontend functionality, debugging UI behavior,
capturing screenshots, reading console logs and network requests.

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

## Toolkit 2: Python Playwright scripts (repeatable automation)

Use only for authorized saved/repeatable checks when existing project/Node
tooling is unsuitable. Server lifecycle should still use tracked supervision
if available, independently of the choice of browser transport.

**Bootstrap does not pre-install Python `playwright`** (`39-playwright`
provisions Node tooling on dev hosts; `20-python` provides uv + interpreter).
Prefer an existing project/Node test harness or already-prepared Python
environment. Run with its already-prepared interpreter, without dependency
resolution. If preparation is missing, report the blocker; a separately
approved preparation step is not part of these helpers:

```bash
"$PREPARED_PYTHON" "$AUTOMATION_SCRIPT"
```

**Helper scripts available**:
- `scripts/with_server.py` - Conditional standalone Linux server supervision;
  standard library only, Python 3.10+, no installation or browser startup by
  the helper itself. Its supplied commands can have all those side effects.

Inspect relevant source/local usage before execution when needed to establish
side effects. Use `--help` only when known safe and authorized; do not treat
scripts as opaque black boxes when their effects are uncertain.

## Decision Tree: Choosing Your Approach

```
Underlying test action and side effects authorized?
  No -> report blocker; do not switch transport to bypass it.
  Yes -> reuse existing supervision and project tests first.
      -> one-off and MCP permitted -> MCP snapshot/action/verify.
      -> repeatable or MCP unavailable -> existing project/Node harness,
         or already-prepared Python environment with independently allowed Bash/network.
      -> package/environment preparation needed -> obtain specific authority
         or report unavailable; no implicit npx/uv installation.
```

## Server Lifecycle Examples

Only when tracked supervision is unavailable and standalone lifecycle is
authorized, use the helper by absolute skill path from the intended project
CWD. Server shell commands are trusted operator input and inherit that CWD;
prefer explicit project commands over shell `cd`. The test command is argv,
not a shell expression. No helper installs or prepares dependencies. Variables
below are operator-supplied placeholders, not shared-runner configuration keys:

```bash
"$PREPARED_PYTHON" "$WEBAPP_SKILL/scripts/with_server.py" \
  --server "$FRONTEND_DEV_CMD" \
  --ready-url "$FRONTEND_READY_URL" --ready-sha256 "$FRONTEND_READY_SHA256" \
  --timeout 30 --command-timeout 120 -- \
  "$PREPARED_PYTHON" "$AUTOMATION_SCRIPT"
```

**Multiple servers (e.g., backend + frontend):**
```bash
"$PREPARED_PYTHON" "$WEBAPP_SKILL/scripts/with_server.py" \
  --server "$BACKEND_DEV_CMD" \
  --ready-url "$BACKEND_READY_URL" --ready-sha256 "$BACKEND_READY_SHA256" \
  --server "$FRONTEND_DEV_CMD" \
  --ready-url "$FRONTEND_READY_URL" --ready-sha256 "$FRONTEND_READY_SHA256" -- \
  "$PREPARED_PYTHON" "$AUTOMATION_SCRIPT"
```

Readiness URLs must be credential-free local HTTP, without query/fragment, on
distinct ports. Supply the reviewed SHA-256 of a deterministic, non-sensitive
HTTP 200 health/identity body (at most 64 KiB); do not learn the expected digest
from whichever listener happens to answer. Redirects, wrong bodies, early
server exit, startup deadline and command deadline fail the run. All ports are
admitted before startup; occupied listeners are never killed or reused. Port
admission cannot reserve ownership through the later bind race; use a distinct
app identity and private isolated ports for qualification.

The helper drains merged stdout/stderr in bounded chunks and suppresses all
child content, command strings and HTTP bodies before emission/storage. This
fail-closed choice sacrifices diagnostics rather than promising a complete
secret detector. Helper status messages are fixed and value-free. Child-owned
file logs and external tooling remain outside this screening boundary: disable
them or independently authorize/protect them. No raw subprocess log is saved.

Every created server and test command has its own session/process group. On
success, failure, partial startup, SIGINT or SIGTERM, all owned groups receive
TERM then KILL, even if a shell leader exited. Non-reaping Linux
`waitid(P_PID, ..., WEXITED | WNOHANG | WNOWAIT)` observations keep each leader's
identity pinned, including exited test leaders. Exit status is kept separate
from `Popen.returncode` until actual reaping. Each group's leader must still be
waitable immediately before every TERM/KILL; all group signalling finishes
before any leader is reaped, once, via `waitpid`. No `Popen.poll()`/early wait,
numeric-group fallback, `killpg(..., 0)` ownership probe, or port/name cleanup
is used. Missing/reaped identity fails closed for that group and reports
incomplete cleanup rather than risking an unrelated reused identifier.
After KILL, registered output is drained to EOF under a five-second deadline
before reaping; startup-unregistered owned pipes are admitted to cleanup where
possible. Missing EOF fails cleanup instead of treating an exited leader as
descendant completion. EOF establishes only that these inherited writers are
closed: descendants that close/redirect output or escape groups are not proven
dead by it. This is bounded supervision, not descendant containment.

The supported platform is Python 3.10+ on 64-bit glibc Linux x86_64/aarch64,
with Linux waitid WNOWAIT and POSIX signal masking. Preflight runs before
startup and every spawn, rejects missing primitives and non-default SIGCHLD,
and queries the declared libc `sigaction` ABI to reject native `SA_NOCLDWAIT`
even when Python reports SIG_DFL. Other ABIs/platforms are unsupported and
fail before spawn, without a less-safe fallback. The helper is explicitly a
single-thread standalone CLI with no external reaper, not an embedding API.
No Python/native SIGCHLD handlers, concurrent `wait*` calls, or signal-action
changes may race ownership checks. Under a violated external-reaper contract,
validation cannot prevent a reap between observation and signalling; this is
not a concurrency-safe sandbox.
`spawn` rejects non-main-thread calls and multiple Python threads. While the
parent blocks SIGINT/SIGTERM through ownership registration, child pre-exec
setup resets their dispositions and unblocks them before exec, so children do
not inherit the parent's temporary blocked mask. This narrow `preexec_fn` use
is unsafe with threads, including native threads the Python guard cannot see;
do not embed it in threaded hosts or introduce threading into this helper.
The original executable shebang is retained; direct absolute-path invocation
uses an already-available `python3` from PATH, without preparing dependencies.
Commands must keep descendants in their group: daemonization, `setsid`, and
escaping groups are unsupported, not sandboxed. SIGKILL of the helper/host
failure cannot run cleanup; use tracked supervision for stronger guarantees.

Examples take explicit URLs/local HTML, ready/action/result selectors, and a
new output file under existing nonredirected directories. They never print or
retain console payloads, app text, URLs, attributes or screenshots; output is
fixed-key bounded counts only, created privately without overwriting. An
existing output is refused. File URLs are constructed with `Path.as_uri()`
for correct escaping. Local HTML can execute scripts/network calls and is not
automatically safe. Inspect inputs and authorize browser/network/output effects.

```bash
"$PREPARED_PYTHON" "$WEBAPP_SKILL/examples/console_logging.py" \
  --url "$APP_URL" --ready-selector "$READY_SELECTOR" \
  --action-selector "$ACTION_SELECTOR" --result-selector "$RESULT_SELECTOR" \
  --output "$NEW_METADATA_OUTPUT"
"$PREPARED_PYTHON" "$WEBAPP_SKILL/examples/element_discovery.py" \
  --url "$APP_URL" --ready-selector "$READY_SELECTOR" \
  --output "$NEW_DISCOVERY_OUTPUT"
"$PREPARED_PYTHON" "$WEBAPP_SKILL/examples/static_html_automation.py" \
  --html "$REVIEWED_HTML" --ready-selector "$READY_SELECTOR" \
  --action-selector "$ACTION_SELECTOR" --result-selector "$RESULT_SELECTOR" \
  --output "$NEW_STATIC_OUTPUT"
```

## Common Pitfalls

- **Don't** require a Python script for a one-off interactive check;
  prefer authorized MCP or independently authorized existing tooling.
- **Don't** assume Python `playwright` exists or prepare it implicitly.
  Inspect existing tooling first. Missing Python tooling does not mean that
  bootstrap-managed Node packages or browser binaries are missing; a
  stdlib-only helper can still start mutating server/test operations.
- **Don't** use compulsory `networkidle`, elapsed sleeps, or TCP connection
  success as app readiness. Dynamic apps may never become network-idle.
- **Do** assert app-specific locator visibility/state and expected results;
  take a fresh MCP snapshot before acting on current refs.

## Best Practices (script path)

- Use bundled scripts only when their invocation effects are understood and authorized; read relevant source when needed rather than executing first by default.
- Use `sync_playwright()` for synchronous scripts
- Always close the browser when done
- Prefer role/test-id locators and Playwright auto-waiting interactions.
- Assert observable results with `expect(locator)`, rather than fixed sleeps.

## Reference Files

- `examples/element_discovery.py` - bounded element counts after app readiness.
- `examples/static_html_automation.py` - local-file action/result assertions.
- `examples/console_logging.py` - bounded suppressed-console message count.
- `examples/_support.py` - explicit inputs, private new-file output and screened
  top-level failure reporting; sibling imports work from unrelated CWDs.

## Pending Isolated Qualification

These are required coordinator cases, not executed by the source/static repair:

`tests/test_supervision.py` contains unexecuted stdlib runtime regression source.
It invokes the production helper from unrelated and skill-project CWDs, uses
private temporary HOME/output, synthetic HTTP identities/secrets, and
fixture-owned ports. It
checks occupied/wrong app, early exit, sustained noise, partial multi-server
startup, descendant cleanup across success/failure/timeouts/interruption,
TERM-resistant grandchildren, graceful TERM, inherited signal masks, and real
first/second registration, partial-spawn exceptions, server exit during a
running command and signal-derived command status. Deterministic helper
definition sentinels assert non-reaping observation, return-code conversion,
no early reap before TERM/KILL, no signal after any final reap, and zero signals
to simulated externally reaped/reused/unknown identities. Preflight source
cases cover missing WNOWAIT, ignored SIGCHLD, native SA_NOCLDWAIT, LP64/layout
rejection and native-query failure, plus delayed post-KILL EOF and its deadline.
Real signal fixture source covers pending SIGINT/SIGTERM after creation and
during registration, and verifies previous mask/handler restoration on fault
and interruption. Its
fallback fixture cleanup uses recorded Linux start identities and pidfds, never
listener discovery or broad group/name killing. Runtime requires separate
authorization and the declared helper platform plus Linux pidfd support; the
suite prepares no dependencies. Mandatory platform absence raises `BLOCKED`
as a suite error, never a passing skip. Pidfds are fixture-emergency safeguards
only, not a claim that leader-only pidfd signals clean production descendants.
The inherited-parent-mask case executes the real helper `__main__` via runpy
inside a subprocess to set/inspect the launcher's mask without changing the
test runner's mask. Injected-fault launchers also execute the real `__main__`;
ordinary fixture cases use its normal subprocess entry. Sentinels load only
helper definitions inside the separately authorized suite, not during static
checks; fake numeric identities never reach a real signal syscall.

Still unimplemented in that suite: IPv6/wildcard occupied listeners, redirects,
oversized/trickle HTTP, threaded embedding refusal, direct shebang execution, and
browser/console/example URL/output/locator cases below. Existing test
source is not evidence that any runtime acceptance passed.

- Occupied IPv4/IPv6/wildcard port leaves unrelated listener alive and starts
  nothing; wrong HTTP app, redirects, wrong digest, oversized body, slow/trickle
  response and early server exit never admit the test command.
- Multi-server partial `Popen`/pipe-registration failure and signal delivery
  during startup clean previously registered groups. Assert no surviving owned
  children/grandchildren on success, command failure, server failure, startup
  deadline, command timeout, SIGINT and SIGTERM, including an exited leader and
  a TERM-resistant descendant. Separately document unsupported escaping daemons.
- Assert exec'd servers/test commands have SIGINT/SIGTERM unblocked and can
  terminate gracefully on group TERM, including when the parent initially had
  either signal blocked. Inject parent interruption between child creation and
  ownership registration; cleanup must still own the child. Threaded embedding
  must be refused before spawning. None of these runtime cases have been run.
- Sustained stdout/stderr noise never blocks lifecycle progress; synthetic
  secrets, split across chunks and console messages, never reach helper/example
  stdout/stderr or metadata outputs. Child-created files require separate review.
- Invoke the production helper/examples from project and unrelated CWDs with
  prepared dependencies only. Cover encoded local-file names, invalid/credential
  URLs, output parent/leaf symlinks, traversal, existing outputs and permission
  errors; assert no overwrite. Browser exceptions must close the browser and
  emit no raw diagnostics. Verify explicit ready/action/result locator behavior.
