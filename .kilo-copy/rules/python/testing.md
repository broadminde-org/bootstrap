---
description: >-
  Python test conventions: pytest, fixtures, parametrize, async testing, and
  race-condition debugging. Generic, framework-agnostic.
---

## Python Test Conventions

### File Naming

- Test files: `test_*.py` in the `tests/` directory, mirroring `src/` structure.
- Test functions: `test_` prefix — `test_create_user`, `test_get_user_not_found`.
- Fixtures: defined in `conftest.py` at the appropriate level (root `tests/`,
  or per-package).
- Slow / external-dep tests: mark with `@pytest.mark.slow` (or
  `@pytest.mark.integration`) and `-m "not slow"` to skip in pre-commit.

### Parametrize (Table-Driven Tests)

```python
import pytest

@pytest.mark.parametrize(
    "input_value,expected,raises",
    [
        ("123.45", "123.45", None),
        ("-50.00", "-50.00", None),
        ("", None, ValueError),
        ("abc", None, ValueError),
    ],
    ids=["positive", "negative", "empty", "invalid"],
)
def test_parse_amount(input_value, expected, raises):
    if raises:
        with pytest.raises(raises):
            parse_amount(input_value)
    else:
        assert parse_amount(input_value) == expected
```

### Async Testing

- **Must** use `pytest-asyncio` with `asyncio_mode = "auto"` in `pyproject.toml`.
- **Do not** mix `asyncio` and `anyio` markers — pick one per project.
- Use `pytest_asyncio.fixture` for async fixtures.

### Async Race Condition Debugging

When an async test fails intermittently or a shared value isn't set when
expected, the cause is almost always task scheduling order. Use these tools:

**Give scheduled tasks one turn before reading shared state:**

```python
task = asyncio.create_task(coro())
await asyncio.sleep(0)   # yield — the task runs up to its first await
assert task.done() or shared_state == expected
```

**Gate a stub to control interleaving:**

```python
gate = asyncio.Event()

async def blocking_stub(**kwargs):
    await gate.wait()   # holds until test releases it
    return sentinel_result

task = asyncio.create_task(tool_under_test())
await asyncio.sleep(0)   # let task start and reach gate.wait()
# assert mid-flight state here
gate.set()              # release the stub
result = await task
# assert final state here
```

**Sequence diagram before the 3rd rewrite.** Draw the event-loop order
explicitly before adding more code:

```
T=0  test task:  create_task(coro), await sleep(0)
T=1  coro:       starts, sets rec.state = RUNNING, hits await runner.run()
T=2  test task:  resumes, asserts rec.state == RUNNING  ← safe
T=3  coro:       runner.run() returns, sets rec.result, fires done_event
T=4  test task:  waits done_event, wakes, reads rec.result  ← safe
```

**Do not busy-poll:**

```python
# BAD — adds latency and hides race conditions
for _ in range(40):
    await asyncio.sleep(0.05)
    if rec.result is not None:
        break

# GOOD — one yield is sufficient if the event fires on the same tick
await rec.done_event.wait()
await asyncio.sleep(0)   # one tick for the setter to finish post-set work
result = rec.result
```

### Coverage

- Use `pytest-cov`: `pytest --cov=src --cov-report=term-missing`.
- **Must** aim for >80% line coverage on new code.
- **Do not** write tests solely to hit coverage targets — test behavior, not implementation.
