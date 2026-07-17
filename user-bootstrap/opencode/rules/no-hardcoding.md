---
description: Never hardcode domains, secrets, API keys, or env-specific values.
---
<env_vars>
- Use env vars for all runtime config; use `_FILE` suffix for secrets.
- Track `.env.example`; gitignore `.env`.
</env_vars>
<templates>
- Use template files (`.tpl`, `.example`) for deployment configs; provide `init.sh` to render.
</templates>
<prohibitions>
- Do not hardcode domains or ports; use `${VAR}` patterns.
</prohibitions>