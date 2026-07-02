---
description: "Python project structure: pyproject.toml, src layout, tooling (generic, framework-agnostic)"
---

<layout>
- `pyproject.toml`: deps, build-system, tool configs
- `src/<package>/`: code; `tests/` mirrors `src/`
- Subpackages follow responsibility grouping: `routes` / `services` / `repositories`
  / `models` / `schemas` / `core` / `middleware` are common partitions, but use
  what fits the application
- `alembic/` (or equivalent) for migrations, only if a relational DB is used
</layout>
<dependencies>
- Pin direct deps in `[project.dependencies]` or `[tool.uv]` pinned groups
- Use the chosen dependency manager (`uv`, `poetry`, `pip-tools`) consistently
- Commit the lockfile
</dependencies>
<tooling>
- Use `[tool.ruff]`, `[tool.mypy]` (or `pyright`), `[tool.pytest.ini_options]`
- Run `ruff check`, `mypy`, `pytest` before declaring a change complete
</tooling>
