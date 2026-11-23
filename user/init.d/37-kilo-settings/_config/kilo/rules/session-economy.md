# Session Economy

## Scope
All agent sessions performing user-requested work.

## Rules
- TASK_BOUNDARY: For a new unrelated task, say so and suggest a fresh session; do not silently accumulate work.
- NO_MID_SESSION_MODEL_SWITCH: Do not change model or reasoning variant mid-session; if it fails, say so and stop.
- COMMIT_NEEDS_ASK: A plan does not authorize `git commit` or `git push`; commit only on explicit request in this session.
- LOCAL_TRUTH_FIRST: For dependency/tool versions and CLI syntax/flags, load `package-version-lookup` and inspect authorized local evidence first. For failures and log evidence, load `debug-with-logs`. Load both only when diagnosis also requires version/CLI verification; neither route authorizes execution, network access, or installation.
