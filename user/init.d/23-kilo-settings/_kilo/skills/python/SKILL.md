---
name: python
description: Core Python engineering standards — project structure, uv tooling, style, error handling, async, testing, and shared-module reuse. Use when writing, reviewing, or refactoring any Python code.
---

# Python Standards

## Shared-First
Before writing utilities, middleware, auth helpers, env loaders, logging setup, retry, or error handlers:
1. INVENTORY: scan `src/shared/`, `lib/`, `common/`, `utils/` for existing modules
2. READ_SOURCE: understand the candidate's API, deps, and test coverage
3. CHECK_IMPORT: `uv run python -c "import <module>"`
4. EVALUATE: meets the need → reuse. Partial → extend. Neither → write new.

Extract to shared only when ALL hold: used in 2+ places, no app-data-model dependency, configurable via parameters, infrastructure-level concern (logging, auth, error handling, retry). Never change a shared module's API without updating all call sites.

## Structure & Tooling
- `pyproject.toml` at root, `src/<package>/` layout, `tests/` mirrors `src/`. Pin direct deps; commit `uv.lock`.
- UV_ONLY: `uv add <pkg>`, `uv sync`, `uv run <cmd>`. Never `pip install`. Never bare `python` for tooling.
- Toolchain: ruff (format + lint + import sort), mypy strict (pyright acceptable if already configured), pytest (+pytest-asyncio, pytest-cov). Config in `pyproject.toml`.
- DONE_GATE: work is complete only when `uv run ruff check && uv run ruff format --check && uv run mypy && uv run pytest` all pass (swap `pyright` for `mypy` if that is the project's checker).

## Style
- 88-char lines, 4-space indent. snake_case files/functions/vars, PascalCase classes, UPPER_CASE constants.
- Type hints on all public signatures and returns. `X | Y` unions, built-in generics (`list[str]`, not `List[str]`).
- Google-style docstrings (summary, Args/Returns/Raises); skip for obvious one-liners.
- Imports: absolute, stdlib → third-party → local, no wildcards.
- Idioms: `if x:` not `if x == True:`, `is None` checks, `with` for all resources, `match/case` for discriminated unions, f-strings, pathlib, httpx.

## Error Handling
- BASE_CLASS: `AppError(Exception)` + specific subclasses (NotFoundError, ValidationError, ...). Map to HTTP status codes at the framework boundary (exception middleware/handlers), never in business logic.
- CATCH_SPECIFIC: no bare `except:` or `except Exception:` unless re-raising.
- CHAIN: `raise NewError("context") from original` — preserve the traceback.
- NO_SWALLOW: every caught exception is handled (logged/fallback) or re-raised. No silent `except: pass`.
- GENERIC_CLIENT: client-facing messages never leak stack traces, SQL, file paths, or internal IDs. Error envelope shape:
  `{"data": null, "error": {"code": "RESOURCE_NOT_FOUND", "message": "The requested resource was not found"}, "meta": {"requestId": "abc123"}}`

## Async
- `create_task(coro)` schedules but does not run until the next `await`. `await asyncio.sleep(0)` yields exactly one loop tick.
- `Event.set()` wakes waiters on the next tick — the setter keeps running. Yield before reading state the setter modified.
- CONTENTION_GUARD: `await asyncio.wait_for(lock.acquire(), timeout=0.5)` — a lock not free in 500ms is a deadlock.
- Primitives: Event (one-shot signal), Lock (mutual exclusion), Semaphore (limit N), Queue (producer-consumer + backpressure).
- LOST_EXCEPTION: task exceptions surface only via `task.result()` or `gather()`. Set a loop exception handler; use `gather(return_exceptions=True)` to collect.
- Debugging races: add `sleep(0)` after `create_task`, gate interleavings with Events in tests. After 3 failed assertions, write out the event-loop timeline — which task runs at each tick (T=0, T=1, ...). After 5, stop and ask for human review.

## Testing
- Files `test_<module>.py`, functions `test_<behavior>`, fixtures in `conftest.py`.
- pytest-asyncio with `asyncio_mode = "auto"` in `pyproject.toml`; async fixtures via `pytest_asyncio.fixture`. Never mix asyncio and anyio markers in one suite.
- Parametrize with explicit `ids=[...]`; use `pytest.raises` inside parametrize for error cases.
- Unit tests <100ms each; mark slower ones `@pytest.mark.slow` (`uv run pytest -m "not slow"`).
- >80% line coverage on new code — measure with `uv run pytest --cov=src --cov-report=term-missing`. Test behavior (inputs → outputs), not implementation.

## Anti-Patterns
- REIMPLEMENT: writing a logger, HTTP client, or auth helper that already exists in shared
- PIP_INSTALL: any dependency or tool invocation that bypasses uv
- BUSY_POLL: `while not flag: await asyncio.sleep(0.05)` — use `Event.wait()`
- BLOCKING_IN_ASYNC: sync `time.sleep()`, file I/O, or HTTP in async functions — wrap with `asyncio.to_thread()`
- FORGOTTEN_AWAIT: calling a coroutine without `await` — it never runs
- SYNC_REQUESTS: `requests` in async code — use httpx
- SWALLOW: silent `except: pass`
