---
description: "Python error handling: exceptions, chaining, logging, API envelope (generic, framework-agnostic)"
---
<exceptions>
- Define an `AppError` base exception in your application package and specific
  subclasses (e.g. `NotFoundError`, `ValidationError`, `UnauthorizedError`).
  Use HTTP status mapping at the framework boundary, not in business code.
</exceptions>
<rules>
- catch specific exceptions; no bare `except`
- chain with `raise ... from e`
- no silent swallows; handle, log, or re-raise
- generic client messages; no tracebacks leaked to API consumers
</rules>
<envelope>
- API responses: `{"data": ..., "error": {"code": ..., "message": ...}, "meta": ...}`
  when the framework allows envelope shaping.
- Never leak stack traces, SQL, file paths, or internal IDs to API responses.
</envelope>
