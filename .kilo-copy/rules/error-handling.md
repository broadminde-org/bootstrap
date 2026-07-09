---
description: "Universal error handling: wrap, never swallow, no panic for expected conditions"
---
<rules>
- return errors up the stack; handle at handler level
- wrap with fmt.Errorf("doing X: %w", err)
- use errors.Is/As; never == on wrapped errors
- lowercase error strings; no trailing punctuation
- generic client messages; do not expose internals
- never silently ignore errors; use _ only when explicit
- panic only for programmer bugs
</rules>
<logging>
- slog.Error("action", "err", err, ...) in Go
- console.log('Component: action failed', e) in frontend
</logging>