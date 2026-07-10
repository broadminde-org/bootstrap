---
description: Version-pinning patterns for Python projects using uv.
---
<purpose>Python version-pinning guidance.</purpose>

<when_to_load>
- Editing pyproject.toml dependencies.
- Adding a new Python package.
- Running uv add or uv lock.
</when_to_load>

<methodology>
1. ADD_VIA_UV: never hand-edit [project.dependencies]. Use uv add pkg.
2. LIVE_LOOKUP_BEFORE_PIN: verify latest via curl https://pypi.org/pypi/pkg/json.
3. FLOATING_RANGE_GUARD: prefer ==X.Y.Z for runtime deps.
4. TRANSITIVE_LOCKFILE: uv.lock is the source of truth.
5. PYTHON_VERSION: check devguide.python.org/versions/ before bumping interpreter.
6. OPTIONAL_GROUPS: use uv add --group name or --optional name.
7. UPDATE_NOTIFICATION: surface version diffs in commit messages.
</methodology>

<anti_patterns>
- HAND_EDIT_DEPENDENCY: pasting pins into pyproject.toml without uv add.
- MEMORY_VERSION: writing langchain>=0.3 from training recall.
- UNPINNED_FLOAT: leaving a transitive as >=X.Y after a major version release.
- IGNORE_LOCKFILE_DIFF: merging uv.lock without reading the diff.
- PYTHON_EOL_BASE: using python:3.X-slim where 3.X has reached EOL.
</anti_patterns>

<registry_endpoints>
- PyPI JSON: https://pypi.org/pypi/<pkg>/json -> info.version, info.release_url
- PyPI releases map: https://pypi.org/pypi/<pkg>/json -> releases dict
- PyPI simple: https://pypi.org/simple/<pkg>/
- uv cache: ~/.cache/uv/ (local, reflects last sync)
</registry_endpoints>