---
description: "Python style: formatting, naming, type hints, docstrings, imports"
---
<formatting>
- use black/ruff; 88 char line; 4-space indent; trailing commas; blank lines per PEP8
</formatting>
<naming>
- snake_case for files/functions; PascalCase for classes; UPPER_CASE for constants
</naming>
<type_hints>
- annotate public signatures and return types; use | for unions; built-in generics
</type_hints>
<docstrings>
- Google-style: summary, blank line, Args/Returns/Raises sections
</docstrings>
<imports>
- stdlib → third-party → local; absolute imports; no wildcards
</imports>
<flow>
- truthiness: use `if x:` not `if x == True:`
- none_check: use `is None` / `is not None`, not `==`
- context_managers: use `with` for resources (files, DB sessions, locks)
</flow>
<modern_python>
- f-strings; pathlib; match/case; httpx; no requests for async
</modern_python>