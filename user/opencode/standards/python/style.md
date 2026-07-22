# Python Project Standards

## Structure
- `pyproject.toml` at project root. `src/<package>/` for source. `tests/` mirrors `src/`.
- Subpackages organized by responsibility. Common patterns: routes, services, repositories, models, schemas, core, middleware.
- Uses `alembic/` (or equivalent) for migrations if a relational DB is used.
- Dependencies: pin direct deps in `[project.dependencies]` or uv dependency groups. Commit lockfile (`uv.lock`).

## Tooling
- **ruff**: `format`, `lint`, import sorting in `[tool.ruff]`
- **mypy** or **pyright**: strict mode in `[tool.mypy]` / `[tool.pyright]`
- **pytest**: `pytest-asyncio`, `pytest-cov` in `[tool.pytest.ini_options]`
- Run all three (`ruff check && ruff format --check && mypy && pytest`) before declaring work complete.

## uv-Only Rule
- ADD: `uv add <pkg>` or `uv add --group <grp> <pkg>`. Never hand-edit `pyproject.toml` dependency lists.
- SYNC: `uv sync` after dependency changes.
- RUN: `uv run <cmd>` for all tool invocations (`uv run pytest`, `uv run ruff check`).
- Never use `pip install`. Never use bare `python` for tooling without `uv run`.

## Style
- **Formatting**: ruff/black, 88-char line, 4-space indent, trailing commas, PEP8 blank lines
- **Naming**: snake_case files/functions/vars, PascalCase classes, UPPER_CASE constants
- **Type hints**: Annotate all public signatures and returns. `|` for unions. Built-in generics (`list[str]` not `List[str]`).
- **Docstrings**: Google-style (summary, Args/Returns/Raises). No docstring for obvious one-liners.
- **Imports**: stdlib → third-party → local. Absolute imports. No wildcards.
- **Flow**: `if x:` not `if x == True:`. `is None` / `is not None`. `with` for all resources. `match/case` for discriminated unions.
- **Modern**: f-strings, pathlib, httpx (async) — never `requests` in async code.
