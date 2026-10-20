# caddy-route Security Review

Date: 2026-10-06
Subject: `~/infra/caddy/bin/caddy-route` (source: `user/init.d/60-caddy/stack/bin/caddy-route`)

## Summary

No remote-exploit-class issues. The Caddy admin API is unix-socket-only inside the
container, and anyone who can run `caddy-route` already has `docker` group access
(root-equivalent on the host). The trust boundary is "the deploy user and app repos."
Within that boundary the script is careful:

- App names cannot path-traverse (`/` excluded from the name regex).
- Rollback on failed `/load` push.
- Zero-snippet reconcile edge case handled (pushes global-only config).
- Global blocks rejected by first-token check (Caddyfile global blocks must be first).

The real exposure is the **snippet trust model**: anything that can get a snippet
registered (app repo `init.sh`, buggy template, compromised app pipeline) controls
edge config with no further checks.

## Findings

### 1. No hostname ownership / namespace enforcement

Validation is "site blocks only + adapts." A snippet can claim **any** hostname,
including one already served by another app. Most-specific match wins in Caddy, so
a snippet containing `ci.broadminde.org { reverse_proxy somewhere-else }` would
hijack that site.

### 2. Catch-all site blocks permitted

A snippet can define `:443 { ... }` or multiple site blocks, intercepting traffic
for the whole edge. Unchecked.

### 3. `file_server` can expose container secrets

`file_server` is a documented allowed directive, and the container mounts `/data`
(ACME account keys, certificates) and `/etc/caddy/acmedns.json` (DNS-01 credentials).
A snippet like:

```caddy
files.example.com {
    root * /
    file_server
}
```

would publish the ACME account key and acme-dns creds to the internet. The
"allowed directives" list in the docs is **not enforced** — `validate()` performs
no directive checking at all.

### 4. `{env.*}` secrets are renderable

Snippets may reference env vars "for secrets," but nothing prevents
`respond {env.CROWDSEC_BOUNCER_KEY}` from serving the bouncer key on a public route.

### 5. `tls { on_demand }` not blocked

A snippet enabling on-demand TLS creates an unbounded certificate-issuance oracle,
abusable to burn the Let's Encrypt rate limits for the shared ACME account.

### 6. Rollback is best-effort

If the rollback `reconcile` also fails, disk and live state diverge silently
(error path just exits 1).

### 7. No audit trail

`register` / `deregister` don't log who registered what, when. Will matter for
multi-host / CI-driven registration.

## Possible hardening (deferred)

Add a linter to `validate()`:

- Enforce the documented directive allowlist (matchers, `handle`, `route`, `tls`,
  `log`, `header`, `respond`, `redir`, `reverse_proxy`, `file_server`).
- Require site addresses to match an approved suffix (e.g. `*.broadminde.org`) or
  a per-app assigned name.
- Reject `on_demand`.
- Restrict `root` / `file_server` to `/srv/edge/*`.
- Append-only audit log of register/deregister actions.

## Current risk assessment

Acceptable today: single operator, first-party app repos only. Worth documenting
in `docs/central-caddy.md` that "any registered snippet is fully trusted edge
config," and revisiting hardening before third-party apps or CI-driven
registration are introduced.
