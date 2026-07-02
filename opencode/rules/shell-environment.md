---
description: Shell environment ownership, init.d idempotency, and config file lifecycle for the netbird stack
---
<ownership>
Each shell config target and host resource in the netbird stack has exactly one owner. No other init script or agent may append to or overwrite a target it does not own.

| Target | Owner |
|---|---|
| `init.d/01-groups/` | group memberships for the deploy user |
| `init.d/03-packages/` | apt-installable packages (`packages.txt`) |
| `init.d/05-passwordless-sudo/` | `/etc/sudoers.d/` |
| `init.d/5-direnv/` | project-level `direnv allow .` |
| `init.d/10-cloudflare/` | `.env.secrets` validation against Cloudflare API |
| `init.d/12-secrets/` | generation of `NETBIRD_AUTH_SECRET`, `NETBIRD_STORE_ENCRYPTION_KEY`, `NETBIRD_ADMIN_PASSWORD` |
| `init.d/20-render/` | rendering of `*.tmpl` -> `config.yaml`, `dashboard.env`, `Caddyfile` |
| `init.d/30-docker/` | Docker CE install |
| `init.d/31-lazydocker/` | lazydocker binary install |
| `init.d/45-build-caddy/` | `caddy-custom:latest` image |
| `init.d/50-stack/` | `docker compose up -d` and its teardown |
| `init.d/60-health/` | `NETBIRD_BOOTSTRAP_PAT` capture |
| `init.d/80-verify/` | read-only summary printout |
</ownership>

<env_file_lifecycle>
The `.env` and `.env.secrets` files in the stack root are GENERATED, not hand-maintained.

- `cp .env.example .env` is the only valid way to seed `.env`.
- `.env` values that have a `.env.example` entry must be changed by editing `.env.example` and re-running `20-render` — not by editing `.env` directly.
- Empty `NETBIRD_AUTH_SECRET`, `NETBIRD_STORE_ENCRYPTION_KEY`, `NETBIRD_ADMIN_PASSWORD` are auto-filled by `12-secrets` on next run.
- `.env` is gitignored. Confirm before committing.

NEVER: edit `.env` to set a value that has a `.env.example` entry. The hand-edit will be clobbered on next `20-render` and will diverge from the documented surface.
NEVER: commit `.env` or any rendered template (`config.yaml`, `dashboard.env`, `Caddyfile`).
</env_file_lifecycle>

<template_render>
Templates live next to their rendered counterparts with a `.tmpl` suffix. Rendering uses `envsubst`:

- `config.tmpl.yaml`     -> `config.yaml`       (mounted into `netbird-server`)
- `dashboard.env.tmpl`   -> `dashboard.env`     (loaded by `dashboard` container)
- `Caddyfile.tmpl`       -> `Caddyfile`         (mounted into `caddy` container)

NEVER: edit a rendered file when a `.tmpl` exists. Edit the `.tmpl` and re-run `20-render`.

Rendered files are typically gitignored. Confirm by checking the relevant `.gitignore` line before any commit.
</template_render>

<machine_scope>
The following affect machine-wide state and must only be touched by their owning init.d step:

- Group memberships for the deploy user → `01-groups`
- `/etc/sudoers.d/` → `05-passwordless-sudo`
- Docker engine install → `30-docker`
- The rendered files mounted into compose containers → `20-render`, then `50-stack`

ALL host provisioning changes belong in the owning init.d step. Never edit these from app-tier scripts or from agent sessions.
</machine_scope>

<idempotency_checks>
After any change to an init.d step that touches shell config or host state, run a sanity check appropriate to the change:

```bash
# Group memberships
id <user>                       # confirm groups added by 01-groups are present

# Passwordless sudo
sudo -n -l <user>               # should list NOPASSWD commands

# Docker
docker compose config            # from the stack root, syntax-check the compose file

# Render step
diff -q <file> <file>.tmpl.rendered    # if you kept the rendered copy, must be byte-identical
                                       # to what envsubst would produce

# Stack health (post `docker compose up -d`)
docker compose ps -a             # services should report `healthy` once 60-health passes
```

NEVER: run an init.d step that needs root from a deploy-user shell — the step will fail loudly. Always `sudo ./init.sh <NN>` for host-tier steps.
</idempotency_checks>
