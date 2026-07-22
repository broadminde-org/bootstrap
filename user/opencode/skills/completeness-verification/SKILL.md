---
name: completeness-verification
description: Final verification step for codemap/architecture documents. Run before closing any documentation task.
---

# Completeness Verification

## Verification Table
Run these checks and record PASS/FAIL for each:

1. **File coverage**: Count files inventoried vs files documented. Must match.
2. **Service coverage**: Count services in docker-compose.yml vs services in ARCHITECTURE.md. Must match.
3. **Template coverage**: Count *.tmpl / *.tpl / *.template files vs documented templates. Must match.
4. **Env var coverage**: Count KEY=value lines in .env.example vs documented env vars. Must match.
5. **Pipeline step coverage**: Count numbered init.d steps vs documented pipeline steps. Must match.
6. **Architecture component coverage**: Every named component in architecture diagram must exist in source.

## Counting Rules
- Regular files: `find . -maxdepth 1 -type f | wc -l` (adjust depth per project)
- Numbered dirs/files: Count lexically sorted entries matching `[0-9][0-9]-*`
- Templates: `find . -name "*.tpl" -o -name "*.template" -o -name "*.tmpl" | wc -l`
- Compose services: `docker compose config --services | wc -l`
- Env vars: `grep -c '^[A-Z_]\+=' .env.example`

## Discrepancy Resolution
- Any FAIL row must be resolved before closing
- Document intentional exclusions with reason
- Re-read source (don't adjust counts to match docs)
- If source is correct and doc is wrong → fix the doc
- If doc is correct and source changed → document the gap and plan the fix

## When to Run
- After creating a new codemap/ARCHITECTURE.md
- After updating an existing document
- Before closing any documentation task
- NEVER skip this step
