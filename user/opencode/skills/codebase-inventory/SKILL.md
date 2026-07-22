---
name: codebase-inventory
description: Inventory all relevant source files before codemap or architecture document generation.
---

# Codebase Inventory

## Workflow
1. IDENTIFY_SCOPE: Determine what type of inventory is needed (ROOT, PIPELINE, CONFIG, STACK).
2. LIST_INITD: For pipeline projects, list every numbered init.d step in lexical order.
3. LIST_TEMPLATES: Find all template files (*.tpl, *.example, *.template) and their rendered counterparts.
4. LIST_CONFIG: Find all config files (docker-compose.yml, .env.example, build configs, CI configs).
5. LIST_DOCS: Find existing documentation (codemaps, ARCHITECTURE.md, README.md, ADRs).
6. NOTE_DOC_TYPES: For each doc found, note whether it's current/stale/missing.

## Format
One section per inventory scope. Each inventoried file maps to exactly one row in the final document.

## Scope Heuristics
- ROOT: Every top-level file, init.d step, *.tmpl
- PIPELINE: Every build/CI step or init.d run script
- CONFIG: Every *.tmpl with rendered counterpart + env var bindings
- STACK: Every named compose service + network + volume

## Completeness Rule
Every file listed in inventory must map to exactly one row in the final document. Zero unexplained files.
