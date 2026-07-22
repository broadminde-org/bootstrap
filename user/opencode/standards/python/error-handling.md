# Python Error Handling

## Rules
- BASE_CLASS: Define `AppError(Exception)` base class + specific subclasses (NotFoundError, ValidationError, UnauthorizedError, etc.). Map to HTTP status codes at the framework boundary, not in business logic.
- CATCH_SPECIFIC: Catch specific exception types. No bare `except:` or `except Exception:` unless re-raising.
- CHAIN: `raise NewError("context") from original`. Preserve the traceback chain.
- NO_SWALLOW: Every caught exception must either be handled (logged, fallback applied) or re-raised. No silent `except: pass`.
- GENERIC_CLIENT: Client-facing error messages must be generic. Never leak stack traces, SQL, file paths, or internal IDs.

## API Error Envelope
```
{"data": null, "error": {"code": "RESOURCE_NOT_FOUND", "message": "The requested resource was not found"}, "meta": {"requestId": "abc123"}}
```

## Async Error Patterns
- task.result() raises exceptions from the task. Always wrap in try/except.
- `asyncio.gather(return_exceptions=True)` collects exceptions instead of raising.
- Unhandled task exceptions get logged at `ERROR` level via the event loop exception handler.
