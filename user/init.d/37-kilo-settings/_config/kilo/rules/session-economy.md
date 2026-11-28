# Session Economy

## Scope
All agent sessions performing user-requested work.

## Rules
- TASK_BOUNDARY: For a new unrelated task, say so and suggest a fresh session; do not silently accumulate work.
- NO_MID_SESSION_MODEL_SWITCH: Do not change model or reasoning variant mid-session; if it fails, say so and stop.
- COMMIT_NEEDS_ASK: A plan does not authorize `git commit` or `git push`; commit only on explicit request in this session.
- LOCAL_TRUTH_FIRST: Validate consequential claims against relevant source and authorized local evidence; label unavailable evidence and uncertainty rather than repeating retained claims as facts. For dependency/tool versions and CLI syntax/flags, use `package-version-lookup` when skill invocation is permitted. For failure/log diagnosis, use `debug-with-logs` when permitted. If invocation is denied or unavailable, use bounded authorized reads instead and report any resulting evidence gap; do not override role permissions. Load both only when the task needs both procedures. Reading guidance does not authorize embedded commands, execution, network access, or installation.
- CONTEXT_CURATION: Retrieve only what resolves a named task ambiguity; do not preload all skills, historical handoffs, or reference-project queues. Prefer section-bounded reads where supported and stop when the ambiguity is resolved; before extending a read, identify the unresolved question and the specific material needed. Disclose incidental overreads, their actual scope, and whether they influenced the conclusion; do not report a broader read as only the requested section. Use only tools needed for the bounded operation within existing permissions; do not enable broader surfaces to obtain a fallback. Apply universal rules throughout, but load task procedures and their references only when relevant. Correct the existing instruction owner with write authority rather than adding a competing layer; report conflicts with applicable instructions or prior changes instead of silently overriding them.
