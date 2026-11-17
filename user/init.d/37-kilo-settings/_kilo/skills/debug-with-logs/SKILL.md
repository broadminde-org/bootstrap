---
name: debug-with-logs
description: Debugging errors, failing tests, non-2xx fetches, missing files, and failed patches by locating and filtering the real evidence first.
---

# Debug With Logs

## Rules
- LOCATE: Prefer existing logs and read-only inspection before guessing: compose logs, journals, captured stdout/stderr, and existing init/pipeline output. Read known paths directly; discover paths only when uncertain.
- FILTER: Search ERROR, WARN, stack traces, panic, and fatal lines first, then widen around the failure timestamp.
- SCREEN: Before reading or quoting output, consider tokens, passwords, connection URLs, expanded arguments, and other secrets. Filter/redact safely without printing secret values or copying them into reports.
- REPORT: Present safe relevant evidence, error codes, and timestamps before proposing fixes; do not quote a secret-bearing excerpt.

## Log Locations
- Use authorized read-only log access such as `docker compose logs --tail=100 <service>`; avoid capturing secret-bearing logs. If safe disposable output is needed and writing it is authorized, use `$HOME/.tmpdir/`.
- For init/pipeline failures, inspect existing output, scripts, and state. Repeatability/idempotency is not authorization: never rerun provisioning or another state-changing operation merely to obtain traces. State-changing reruns need separate specific authority; privileged provisioning is operator-only.
- Trace only when the operation is specifically authorized and after checking its command and environment for secret exposure. Do not trace if secrets could be printed. Use authorized browser console/network evidence for applicable frontend failures, with the same screening.

## Methodology
1. IDENTIFY_SOURCE: Determine the failed operation and symptom, its actual authority, and any operation-defined attempt budget.
2. READ_EVIDENCE: Inspect existing evidence through the correct authorized access method, screening for secrets.
3. APPLY_FILTER: Filter safe errors around the failure time; form a new hypothesis before any rerun.
4. VERIFY: Verify the original failure with evidence appropriate to it. Service health checks apply only to applicable services through authorized checks. Report missing or unrun verification rather than claiming success.

## Attempt Accounting

- Follow the operation's actual attempt budget; do not invent deadlines or failure counts. Read-only diagnostics and pre-submission harness failures do not consume a mutating-attempt budget.
- When the terms count submissions/admissions, those consume the budget, including rejected submissions. Initiated state changes consume their operation budget. If the counting unit is unclear, report the ambiguity before another consequential attempt.
- Stop the affected action on denial, unexpected sensitive data, changed scope/risk, or a warning affecting authority/safety; do not switch tools to circumvent it. An ordinary non-denial read-only diagnostic error does not consume a still-applicable grant at unchanged scope/risk. Do not repeat an unchanged failure.

## Verify Before Acting
- Read exact known paths directly; use glob or directory inspection when a path is uncertain.
- Before `webfetch`, confirm URL shape; prefer raw source over rendered HTML.
- Before `edit` or `apply_patch`, re-read the exact target lines.

## Anti-Patterns
- NO_LOG_CHECK: Proposing fixes without first reading logs.
- FALSE_SUCCESS: claiming the original failure is fixed without appropriate observed verification, or treating source inspection as service-health evidence.
