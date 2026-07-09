---
description: Python asyncio concurrency patterns and scheduling rules
---
<scheduling>
- asyncio.create_task(coro) schedules coro but does NOT run it immediately.
  The current coroutine continues until it hits an await. The new task
  starts on the first event-loop tick after the current coroutine yields.
- After spawning a background task, the task has NOT run yet. Do NOT read
  state the task is responsible for setting in the same synchronous block —
  yield first with `await asyncio.sleep(0)` or a real await.
- One event-loop yield: `await asyncio.sleep(0)` gives all ready tasks one
  turn. Use this in tests and coordination code that needs the just-scheduled
  task to run before proceeding.
</scheduling>

<events>
- asyncio.Event.set() marks the event set and wakes all waiters on the next
  event-loop tick. Waiters do NOT run synchronously inside set().
- asyncio.Event.wait() returns immediately if the event is already set, but
  the waiter still participates in the next event-loop tick — it does NOT
  skip ahead of other ready tasks.
- Do NOT read shared state modified by the setter immediately after set() in
  the same synchronous block. The setter's writes are visible, but if the
  reader is in a separate concurrent task, it may not see them until after
  its own next yield.
</events>

<blocking>
- A synchronous call inside an async def BLOCKS the event loop for its full
  duration. Anything that `await`s inside that coroutine is also blocked:
  SSE flushes, HTTP keep-alives, other tool calls.
- Identify blocking calls: subprocess.run(), time.sleep(), blocking file I/O,
  any CPU-bound loop, any third-party SDK that is not async-native.
- Wrap blocking calls in asyncio.to_thread():
    result = await asyncio.to_thread(blocking_function, arg1, arg2)
  This runs the function in the default thread-pool executor, leaving the
  event loop free to handle other work.
- loop.run_in_executor(None, fn, *args) is the lower-level equivalent.
  Prefer asyncio.to_thread() (Python 3.9+) for readability.
- Declaring a function `async def` does NOT make it non-blocking. An async
  def that calls subprocess.run() internally still blocks the event loop.
</blocking>

<task_coordination>
- Use asyncio.Event for one-shot "done" / "ready" signals.
- Use asyncio.Lock for mutual exclusion. Use asyncio.wait_for(lock.acquire(),
  timeout=0.5) to avoid blocking indefinitely on contended locks.
- loop.call_later(0, fn) defers fn to the next event-loop iteration. Use it
  to release shared resources AFTER waiters wake up, so concurrent tasks that
  were waiting can still observe the pre-release state in their first tick.
- NEVER busy-poll shared state: prefer Event.wait() over
  `while not condition: await asyncio.sleep(0.05)`.
- asyncio.gather(*coros) runs all coroutines concurrently. Use it for fan-out
  work; failures in one task raise and cancel the rest unless
  return_exceptions=True.
</task_coordination>

<test_debugging>
- To give all ready tasks one turn: `await asyncio.sleep(0)`.
- Use asyncio.create_task() + asyncio.Event gates in tests to control
  interleaving: gate.set() lets a blocking stub proceed; gate.wait() holds it.
- Add ONE debug print to trace task ordering; remove before committing.
- If a test fails after 3 rewrites, draw the event-loop execution order on
  paper before writing more code:
    T=0  task A starts, calls await X
    T=1  event loop runs task B
    T=2  X resolves, task A resumes
- After 5 consecutive failures on the same assertion, stop and ask the user.
</test_debugging>
