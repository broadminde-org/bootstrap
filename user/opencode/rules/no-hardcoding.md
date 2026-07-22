# No Hardcoding

## Scope
All languages. Apply to every task that writes configuration, constants, or runtime values.

## Rules
- ENV_VARS: Runtime config goes in environment variables. Use `_FILE` suffix pattern for secret values.
- DOTENV: Track `.env.example` in git. `.env` is ALWAYS gitignored and NEVER committed.
- TEMPLATES: Template files (`.tpl`, `.example`, `.template`) are source of truth. Rendered files are output, not hand-edited.
- NO_HARDCODED: Never hardcode domains, ports, URLs, paths, or credentials in source files. Use env vars, config files, or flag defaults.
- DEFAULT_PORTS: Port defaults in config are acceptable only as fallbacks. Env var must override.
