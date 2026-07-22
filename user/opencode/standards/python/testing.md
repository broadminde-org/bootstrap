# Python Testing

## Naming & Organization
- Files: `test_<module>.py`. Functions: `test_<behavior>`. Fixtures in `conftest.py`.
- Mark slow tests: `@pytest.mark.slow`. Unit tests stay fast (<100ms each).
- Parametrize: `@pytest.mark.parametrize("a,b,expected", [...], ids=[...])`. Always provide ids. Use `pytest.raises` in parametrize for error case testing.
- Do NOT mix `asyncio` and `anyio` markers in the same test suite. Pick one async framework.

## Async Testing
- `pytest-asyncio` with `asyncio_mode = "auto"` in pyproject.toml
- `pytest_asyncio.fixture` for async fixtures
- Use Event gates to control concurrent interleaving in tests

## Coverage
- `pytest-cov` with target >80% line coverage on new code
- Test behavior (inputs → outputs), not implementation (internal method calls)
- One assertion per test is ideal; related assertions in one test are acceptable

## Commands
- `uv run pytest` — run all tests
- `uv run pytest -m "not slow"` — fast tests only
- `uv run pytest --cov=src --cov-report=term-missing` — with coverage
