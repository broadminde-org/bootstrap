---
name: codebase-inventory
description: Inventory source files in the netbird stack before codemap generation
---
<purpose>Ensure documentation completeness by listing all relevant source, configuration, and doc types in the stack.</purpose>
<steps>
1. identify_scope: resolve target scope (root, pipeline, config, stack-runtime)
2. list_initd: list every numbered `init.d/<NN>-*` directory and `.sh` file
3. list_templates: list every `*.tmpl` file at the repo root
4. list_config: list `docker-compose.yml`, `Caddyfile`, `config.yaml`, `dashboard.env`, `.env.example`
5. list_docs: list existing `*.md` files in `docs/` (and the candidate doc paths)
6. note_doc_types: determine which docs apply (codemap, codemap-pipeline, codemap-config, ARCHITECTURE)
</steps>
<format>
- One section per inventory scope: init.d, templates, config, docs, applicable doc types
</format>
<completeness_rule>Every inventoried file must map to exactly one row in the final document.</completeness_rule>
<scope_heuristics>
- ROOT:        inventory every top-level file, every `init.d/` step, every `*.tmpl`
- PIPELINE:    inventory every `init.d/<NN>-*/run.sh` and `<NN>-*.sh` flat file
- CONFIG:      inventory every `*.tmpl` with its rendered counterpart and env-var dependencies
- STACK:       inventory every named service in `docker-compose.yml` plus its volumes, networks, and port mappings
</scope_heuristics>
