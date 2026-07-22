# Documentation Quality Standards

## Scope
All documentation: codemaps, ARCHITECTURE.md, READMEs, API docs, ADRs.

## Rules
- DERIVE_DONT_INVENT: Copy names from source files. Never guess. Note ambiguity explicitly with `[CHECK]`.
- CITE_PATHS: Reference format: `path/to/file.sh:FunctionName`. Always repo-relative paths.
- NO_PLACEHOLDERS: Omit inapplicable sections entirely. Don't leave "Coming soon" or "TBD" blocks. `docs/archive/` for retired material only.
- ATOMIC_UPDATES: Rewrite whole sections when refreshing. Don't patch row-by-row. A stale row in the middle is worse than a missing section.
- NO_DUPLICATION: Each piece of information has exactly one canonical location. Architecture → ARCHITECTURE.md. Config → codemap-config. Pipeline → codemap-pipeline.
- VERIFY_BEFORE_CLOSE: Run completeness verification before declaring a doc task done. Count mismatches are hard errors — neither ignore nor handwave them.

## Structure Rules
- **ROOT_CODEMAP** (codemap.md): Every top-level file, init.d step, template → one row
- **PIPELINE** (codemap-pipeline.md): Step-by-step walkthrough of every init/cicd step
- **CONFIG** (codemap-config.md): Every template + rendered counterpart + env var bindings
- **ARCHITECTURE** (ARCHITECTURE.md): System boundaries, component responsibilities, data flow

## Anti-Patterns
- INVENTED_NAMES: "The config service" when the actual service is called `caddy`
- PATHLESS_REFERENCE: "See the config file" without a path
- STALE_ARCHIVE: Moving things to `archive/` without annotating the migration reason and date
