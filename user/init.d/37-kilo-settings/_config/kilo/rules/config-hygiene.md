# Config Hygiene

## Scope
All agent work that touches configuration, environment variables, or deployment parameters. Deployment-input rules below apply to app-managed runtime configuration, not every literal in every file.

## Rules
- ENV_CONFIG: App-managed deployment inputs come from the project's supported configuration interface, usually environment variables and a gitignored `.env`. Preserve documented portable defaults and existing configuration formats; do not introduce another parser or convert user configuration merely to satisfy this rule.
- NO_SECRETS: Never commit `.env` files, tokens, passwords, or private keys. Never print secret values into logs, reports, or chat replies.
- EXAMPLE_TRACKED: Every app-managed project `.env` has a tracked `.env.example` (or equivalent template) documenting all keys with placeholder values. When adding a key, update the example; never copy local/user secrets into it.
- NO_HARDCODE: Do not embed deployment-specific domains, ports, hosts, URLs, or credentials in application source. Documentation/registry endpoints, documented portable defaults, and synthetic non-sensitive fixtures are not deployment inputs. Never use real credentials in examples or fixtures.
- TEMPLATE_SOURCE: Tracked templates (`.env.example`, `*.example`, config templates) own generated configuration. Only explicitly rendered outputs are regenerable; manually maintained local/user configs are not disposable. Preserve their values and extras, require applicable write authority, and never reverse-import secrets into tracked templates.
