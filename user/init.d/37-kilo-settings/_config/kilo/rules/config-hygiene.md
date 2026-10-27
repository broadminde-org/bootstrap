# Config Hygiene

## Scope
All agent work that touches configuration, environment variables, or deployment parameters.

## Rules
- ENV_CONFIG: Runtime configuration comes from environment variables (usually a gitignored `.env`), never from values hardcoded in source.
- NO_SECRETS: Never commit `.env` files, tokens, passwords, or private keys. Never print secret values into logs, reports, or chat replies.
- EXAMPLE_TRACKED: Every `.env` has a tracked `.env.example` (or equivalent template) documenting all keys with placeholder values. When adding a key, update the example.
- NO_HARDCODE: Never hardcode domains, ports, hosts, URLs, or credentials in source. Derive them from config; put deployment-specific values in the project's `.env`.
- TEMPLATE_SOURCE: Tracked template files (`.env.example`, `*.example`, config templates) are the source of truth; rendered/local configs are disposable outputs.
