---
name: debug-with-logs
description: Debugging errors, failing tests, non-2xx fetches, missing files, and failed patches by locating and filtering the real evidence first.
---

# Debug With Logs

## Rules
- LOCATE: Find actual log output before guessing. Check compose logs, init reruns, journalctl, stdout, and stderr.
- FILTER: Search ERROR, WARN, stack traces, panic, and fatal lines first, then widen around the failure timestamp.
- REPORT: Present relevant log lines, error codes, and timestamps before proposing fixes.

## Log Locations
- Use `docker compose logs --tail=100 <service>` and capture workspace-local output in `<workspace>/.tmp/`.
- For init or pipeline failures, rerun with `bash -x` or `set -x`; use browser console and network tools for frontend failures.

## Methodology
1. IDENTIFY_SOURCE: Determine the failed service and symptom.
2. RUN_ACCESS: Fetch logs using the service's correct access method.
3. APPLY_FILTER: Filter errors around the failure time.
4. SUMMARIZE: Include the key lines and confirm health after a fix.

## Verify Before Acting
- Before `read`, confirm the path exists with glob; list a repository directory before guessing paths.
- Before `webfetch`, confirm URL shape; prefer raw source over rendered HTML.
- Before `edit` or `apply_patch`, re-read the exact target lines.

## Anti-Patterns
- NO_LOG_CHECK: Proposing fixes without first reading logs.
- NO_SUCCESS_REPORT: Fixing an error without confirming the service is healthy.
