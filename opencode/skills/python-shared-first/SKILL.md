---
name: python-shared-first
description: Check existing Python code in the netbird stack before adding new infrastructure code
---
<scope>
USE_BEFORE: utilities, middleware, auth, env loaders, logging setup, retry/circuit-breaker helpers
</scope>
<methodology>
1. INVENTORY: scan the repo for any existing Python (default: none in netbird)
2. READ_SOURCE: inspect any `__init__.py` files and key modules in the candidate location
3. CHECK_IMPORT: ensure the candidate is installable (`uv pip install -e .` or `uv sync`)
4. EVALUATE: if a candidate is reusable and infra-level, prefer it. Otherwise, document why
   an addition is justified.
</methodology>
<extraction_criteria>
If/when the stack grows a shared Python directory, extract a module when ALL of:
- USED_IN_2_PLACES: the same logic is referenced from 2+ files or scripts
- NO_APP_DATA_DEP: no business-data shape dependency
- CONFIGURABLE: parameters come from config / env / DI, not hard-coded
- INFRA_LEVEL: HTTP middleware, env loader, retry/backoff, structured logging setup, etc.
</extraction_criteria>
<anti_patterns>
- REIMPLEMENT: do not copy-paste an existing helper into a new script when both scripts live in the same repo
- MODIFY_SHARED: do not edit any existing shared Python package without an explicit ask
- SKIP_MAP: do not skip reading the package README before adopting a helper
</anti_patterns>
