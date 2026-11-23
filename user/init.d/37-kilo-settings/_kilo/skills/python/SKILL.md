---
name: python
description: Core Python engineering standards — project structure, uv tooling, style, error handling, async, testing, and shared-module reuse. Use when writing, reviewing, or refactoring any Python code.
---

# Python Standards

## Shared-First
In applicable repositories, before writing genuinely reusable infrastructure such as middleware, auth helpers, env loaders, logging, retry, or error handling:
1. INVENTORY: inspect relevant existing shared directories and dependency declarations; do not invent missing directories
2. READ_SOURCE: understand the candidate's API, deps, and test coverage
3. CHECK_SAFELY: prefer source/dependency inspection. Do not create/synchronize an environment, change a lockfile, install dependencies, provision access, or import modules with unknown side effects merely to check reuse.
4. EVALUATE: meets the need → reuse. Partial → propose an extension if outside the task; do not extend shared code merely for inventory. Neither → write the smallest in-scope implementation.

Extract to shared only when ALL hold: used in 2+ places, no app-data-model dependency, configurable via parameters, infrastructure-level concern (logging, auth, error handling, retry). Never change a shared module's API without updating all call sites.

## Structure & Tooling
- Preserve the project's package layout, dependency policy, environment manager, and lockfiles. In projects using the packaged `src/<package>/` convention, keep `pyproject.toml` at root and tests aligned with the actual layout. A standalone helper or narrow correction must not introduce a new layout, lockfile, or framework.
- UV_PROJECTS: use `uv add <pkg>`, `uv sync`, and `uv run <cmd>` only for applicable uv projects and authorized side effects; do not bypass their uv policy with pip. Existing non-uv projects retain their required tooling; do not convert them.
- Use configured formatting/linting, typing, and test tools (for example Ruff, mypy/pyright, pytest). Do not adopt uv, mypy, pytest, or coverage tooling merely for a narrow change.
- VALIDATION: use the existing harness for affected lint/format, typing, tests, and required milestone/CI checks under execution authority. Keep project-specific coverage, security, money-path, and release gates; report unavailable/failed checks and unrelated pre-existing failures without claiming full qualification or expanding scope.
- Where no harness or convention exists, a minimal relevant runnable regression is required under execution authority, not a replacement for other required checks or a reason to introduce a test framework. Report blocked execution rather than bypassing approval.

## Style
- 88-char lines, 4-space indent. snake_case files/functions/vars, PascalCase classes, UPPER_CASE constants.
- Type hints on public signatures and returns. Use `X | Y` unions (3.10+) and built-in generics (3.9+) when supported by the project's Python version; do not upgrade Python for a style correction.
- Google-style docstrings (summary, Args/Returns/Raises); skip for obvious one-liners.
- Imports: absolute, stdlib → third-party → local, no wildcards.
- Idioms: `if x:` not `if x == True:`, `is None` checks, `with` for all resources, `match/case` for discriminated unions, f-strings, pathlib, httpx.

## Error Handling
- BASE_CLASS: in applications with an exception hierarchy, use the existing base and specific subclasses. Do not add `AppError` or a framework to a helper solely for consistency. Map HTTP errors at an applicable framework boundary, never in business logic.
- CATCH_SPECIFIC: catch specific exceptions normally. A CLI/top-level or task-supervision boundary may catch `Exception` for screened failure reporting and an explicit failed result/nonzero exit, or cleanup followed by re-raising. Do not catch `BaseException` to swallow cancellation, `KeyboardInterrupt`, or `SystemExit`.
- CHAIN: `raise NewError("context") from original` — preserve the traceback.
- NO_SWALLOW: every caught exception is handled (logged/fallback) or re-raised. No silent `except: pass`.
- GENERIC_CLIENT: client-facing messages never leak stack traces, SQL, file paths, or internal IDs. Preserve the application's existing error contract; where this envelope convention applies, its shape is:
  `{"data": null, "error": {"code": "RESOURCE_NOT_FOUND", "message": "The requested resource was not found"}, "meta": {"requestId": "abc123"}}`

## Async
- `create_task(coro)` normally schedules execution when the loop next runs it. An eager task factory (3.12+) or supported eager-start setting can run it synchronously during creation. `await` does not necessarily suspend (an already-completed awaitable can return immediately); `await asyncio.sleep(0)` suspends the current task but guarantees neither an exact tick nor another task's completion.
- `Event.set()` sets the flag and makes waiters runnable; it does not wait for their work to finish. `Event.wait()` returns immediately when already set. Use explicit acknowledgement Events, Queues, task awaits, or Locks to establish the required ordering, not a sleep/yield guess.
- CONTENTION_GUARD: choose timeouts from actual contention expectations and operation limits. A slow lock acquisition alone does not prove deadlock; inspect ownership, waiting tasks, and observed interleavings.
- Primitives: Event (resettable signal), Lock (mutual exclusion), Semaphore (limit N), Queue (producer-consumer + backpressure). Asyncio primitives are not OS-thread synchronization primitives.
- TASK_FAILURES: keep strong references and observe every owned task's outcome via `await`, `TaskGroup` (3.11+), `gather`, or a done callback that inspects `result()`/`exception()` and handles cancellation. With `gather(return_exceptions=True)`, inspect every result and explicitly handle/report failures; collection alone is not handling. Default `gather` propagates the first failure without cancelling siblings, unlike `TaskGroup`; supervise/await remaining owned tasks and clean up on cancellation.
- A loop exception handler is a diagnostic backstop for unobserved failures, not a replacement for task ownership. Propagate cancellation after cleanup and screen exception text before reporting; no silent swallowing.
- Debugging races: gate relevant interleavings with Events in tests and inspect ownership/waiters rather than assuming a scheduling order.

Official semantics: [tasks, eager execution, suspension, and failure propagation](https://docs.python.org/3/library/asyncio-task.html), [synchronization](https://docs.python.org/3/library/asyncio-sync.html). Consult the documentation matching the project's Python version before using newer APIs.

## Testing
- Files `test_<module>.py`, functions `test_<behavior>`, fixtures in `conftest.py`.
- Where pytest-asyncio is already used, follow its project configuration (such as `asyncio_mode = "auto"`) and fixture conventions. Preserve existing anyio suites; do not convert their markers or configuration.
- Parametrize with explicit `ids=[...]`; use `pytest.raises` inside parametrize for error cases.
- Use project-specific performance expectations and slow-test markers, not universal duration limits. A focused development run may omit unrelated slow tests, but never exclude required slow tests from final qualification.
- Preserve project coverage thresholds and derive coverage targets from actual package layout, not hardcoded `src`. Additional coverage improvement is optional unless required by instructions or demonstrated safety risk. Test behavior (inputs → outputs), not implementation.

## Anti-Patterns
- REIMPLEMENT: writing a logger, HTTP client, or auth helper that already exists in shared
- UV_BYPASS: dependency/tool invocations bypassing an applicable project's uv policy
- BUSY_POLL: `while not flag: await asyncio.sleep(0.05)` — use `Event.wait()`
- BLOCKING_IN_ASYNC: sync `time.sleep()`, file I/O, or HTTP in async functions — wrap with `asyncio.to_thread()`
- FORGOTTEN_AWAIT: calling a coroutine without `await` — it never runs
- SYNC_REQUESTS: `requests` in async code — use httpx
- SWALLOW: silent `except: pass`
