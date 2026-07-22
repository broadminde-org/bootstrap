# Error Handling

## Scope
All languages. Apply to every task that writes or reviews code.

## Rules
- RETURN_UP: Errors go up the stack. Handle at the outermost level that can meaningfully respond.
- WRAP: `fmt.Errorf("doing X: %w", err)` in Go. `raise ... from e` in Python. `new Error("...", { cause: e })` in JS.
- COMPARE: `errors.Is` / `errors.As` (Go). `isinstance` or exception class matching (Python). `instanceof` (JS). Never `==` on wrapped errors.
- FORMAT: Lowercase error strings. No trailing punctuation.
- CLIENT: Generic client-facing messages. Never leak stack traces, SQL, file paths, or internal IDs to users.
- NO_SILENT: Never silently ignore errors. `_` only when the intent is explicit and documented.
- PANIC: Panic/crash only for unrecoverable catastrophic state (corrupted internal data structure, mandatory invariant violated). Never panic on user input or external service failures.
- LOG: Go: `slog.Error("action", "err", err)`. Python: `logger.error("action", exc_info=True)`. JS: `console.error("Component:", action, e)`.
