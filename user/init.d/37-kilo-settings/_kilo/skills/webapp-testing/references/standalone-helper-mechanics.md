# Standalone Helper Mechanics — On-demand Reference

Read only when conditional standalone supervision or the bundled examples are relevant. Reading this reference does not authorize execution. [SKILL.md](../SKILL.md) owns task routing, operator authority, platform restrictions, and runtime-evidence warnings. Prefer existing project tooling and tracked supervision.

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
success, failure, partial startup, SIGHUP, SIGINT or SIGTERM, all owned groups receive
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
The parent installs handlers with supervised signals blocked, then unblocks
them inside its cleanup-protected region, including inherited pending signals.
It restores the original handlers while blocked and restores the original mask
last, after cleanup. `spawn` rejects non-main-thread calls and multiple Python
threads. While the
parent blocks SIGHUP/SIGINT/SIGTERM through ownership registration, child pre-exec
setup resets their dispositions and unblocks them before exec, so children do
not inherit the parent's temporary blocked mask. This narrow `preexec_fn` use
is unsafe with threads, including native threads the Python guard cannot see;
do not embed it in threaded hosts or introduce threading into this helper.
The original executable shebang is retained; direct absolute-path invocation
uses an already-available `python3` from PATH, without preparing dependencies.
Commands must keep descendants in their group: daemonization, `setsid`, and
escaping groups are unsupported, not sandboxed. SIGKILL of the helper/host
failure cannot run cleanup; use tracked supervision for stronger guarantees.

These are source-described mechanics, not proof of runtime safety or completed qualification. See [maintenance qualification](maintenance-qualification.md) only for an explicitly assigned, separately authorized maintenance task.

## Bundled Browser Examples

Examples take explicit URLs/local HTML, ready/action/result selectors, and a
new output file under existing nonredirected directories. They never print or
retain console payloads, app text, URLs, attributes or screenshots; output is
fixed-key bounded counts only, created privately without overwriting. An
existing output is refused. File URLs are constructed with `Path.as_uri()`
for correct escaping. Local HTML can execute scripts/network calls and is not
automatically safe. Inspect inputs and authorize browser/network/output effects.
For interaction checks, the result selector must be hidden before the click and
visible afterward; an already-visible result is refused rather than verified.

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

## Source References

- [with_server.py](../scripts/with_server.py) — conditional standalone supervision.
- [element_discovery.py](../examples/element_discovery.py) — bounded element counts after app readiness.
- [static_html_automation.py](../examples/static_html_automation.py) — local-file action/result assertions.
- [console_logging.py](../examples/console_logging.py) — bounded suppressed-console message count.
- [_support.py](../examples/_support.py) — explicit inputs, private new-file output and screened top-level failure reporting; sibling imports work from unrelated CWDs.
