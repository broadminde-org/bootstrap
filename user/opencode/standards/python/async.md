# Python Async & Concurrency

## Scheduling Rules
- `create_task(coro)` schedules but does NOT run immediately. The coroutine starts on the next `await` point.
- YIELD: `await asyncio.sleep(0)` forces exactly one event-loop tick. Use to let scheduled tasks run.
- Event.set() wakes waiters on the next tick, NOT synchronously inside set(). The setter keeps running. Do NOT read shared state modified by the setter immediately after set() — instead, `await asyncio.sleep(0)` to yield control first.
- CONTENTION_GUARD: `await asyncio.wait_for(lock.acquire(), timeout=0.5)` — if a lock isn't free within 500ms, something is stuck. Treat as deadlock.
- DEFER: `loop.call_later(0, fn)` defers execution to the next event-loop tick. Use for resource release after set()/notify().

## Coordination Primitives
- **Event**: one-shot signal. One writer calls `set()`, one or more readers call `wait()`. Not reusable unless `clear()` is called.
- **Lock**: mutual exclusion. `async with lock:` for critical sections.
- **Semaphore**: limit concurrency to N tasks.
- **Queue**: producer-consumer patterns with backpressure.

## Anti-Patterns
- BUSY_POLL: `while not flag: await asyncio.sleep(0.05)`. Use `Event.wait()` instead.
- BLOCKING_IN_ASYNC: sync `time.sleep()`, sync file I/O, sync HTTP calls in async functions. Wrap with `asyncio.to_thread()`.
- FORGOTTEN_AWAIT: calling a coroutine without `await` creates a warning but the coroutine never runs.
- LOST_EXCEPTION: Task exceptions are only raised when `task.result()` or `gather()` is called. Set an exception handler on the event loop.

## Debugging Race Conditions
1. Add `await asyncio.sleep(0)` after each `create_task` to yield control
2. Use Event gates to control interleaving in tests
3. After 3 consecutive assertion failures, draw event-loop order (T=0, T=1, ...)
4. After 5 consecutive assertion failures, stop and ask for human review
