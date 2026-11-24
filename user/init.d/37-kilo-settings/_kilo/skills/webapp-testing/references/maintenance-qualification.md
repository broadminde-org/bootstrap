# Web-testing Maintenance — Patch Record and Required Qualification

**Disposition: maintenance reference, not an ordinary browser-task execution queue.** Load only for explicitly assigned helper/example maintenance or qualification. Do not implement or run the cases below during ordinary browser tasks. Assignment does not grant execution: tests, process creation, signals, browser/network activity, dependency preparation, and artifacts each require applicable operator authority. [SKILL.md](../SKILL.md) owns task routing and safety restrictions; [standalone helper mechanics](standalone-helper-mechanics.md) describes conditional use.

## Patch Record and Upstream Refresh

**Retained local patch record (2026-11-23; historical label, not a qualification receipt):** Bootstrap modified this guidance,
`scripts/with_server.py`, and all three upstream examples; added
`examples/_support.py` and unexecuted `tests/test_supervision.py` regression
source. Retain these repairs on upstream refresh, along with
the source metadata in SKILL.md and both original license files. The repairs add
owned Linux process groups, HTTP app identity, output suppression, explicit
inputs, and locator assertions. Q12 additionally replaces reaping observations
with `waitid(..., WNOWAIT)`, pins leaders through all group signalling, rejects
native SIGCHLD auto-reaping before spawn, and adds UNRUN call-order/reuse and
real-fixture failure source. Q12 is a retained patch identifier, not current task authority. Source/static checks are not runtime evidence.

This documentation separation did not execute helpers, examples, tests, or qualification. Presence of implementation/test source does not prove local testing or live qualification; require authentic receipts before asserting either. Historical UNRUN labels are not a claim about inaccessible subsequent runs.

Preserve [helper source](../scripts/with_server.py), [support source](../examples/_support.py), the [three examples](standalone-helper-mechanics.md#source-references), [regression source](../tests/test_supervision.py), [LICENSE](../LICENSE), [LICENSE.txt](../LICENSE.txt), and upstream source/license metadata when refreshing. Do not replace local repairs silently with upstream originals.

## Required Isolated Qualification Coverage — Non-executable Unless Assigned and Authorized

These are required coordinator cases, not executed by the source/static repair:

`tests/test_supervision.py` contains regression source reported as unexecuted in the retained patch record.
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

The retained record identifies these cases as still unimplemented in that suite: IPv6/wildcard occupied listeners, redirects,
oversized/trickle HTTP, threaded embedding refusal, direct shebang execution, and
browser/console/example URL/output/locator cases below. Revalidate source status only when assigned maintenance requires it; this list is required coverage, not authority to add tests now. Existing test
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
  must be refused before spawning. The retained record reports none of these runtime cases run; no runtime receipt was established by this documentation task.
- Sustained stdout/stderr noise never blocks lifecycle progress; synthetic
  secrets, split across chunks and console messages, never reach helper/example
  stdout/stderr or metadata outputs. Child-created files require separate review.
- Invoke the production helper/examples from project and unrelated CWDs with
  prepared dependencies only. Cover encoded local-file names, invalid/credential
  URLs, output parent/leaf symlinks, traversal, existing outputs and permission
  errors; assert no overwrite. Browser exceptions must close the browser and
  emit no raw diagnostics. Verify explicit ready/action/result locator behavior.
- Cover direct shebang invocation with an already-available `python3` on PATH, without dependency preparation.
