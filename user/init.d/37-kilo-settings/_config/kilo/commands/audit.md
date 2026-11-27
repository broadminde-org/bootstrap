---
description: Audit project state — dependencies, security, configuration drift
agent: code
---

# Audit

## Usage
`/audit [scope]`

Scope options: `deps` (dependencies), `security` (CVEs), `config` (configuration drift), `all` (default).

## Scope
ALLOWED: Read only files necessary for the selected scope; inspect declarations/lockfiles, safe configuration key names, and already-available scanners whose exact invocation is proven nonmutating. Network queries require independent authorization.
DENIED: File/host mutation, implicit installation, environment synchronization, lockfile updates, image pulls, cache preparation, destructive scans, secret-value output, or registry publication. Audit scope is not authority for scanner side effects.

## Methodology
1. SELECT_SCOPE: Honor `deps`, `security`, `config`, or `all`; inventory/read only relevant sources. Establish tool availability and scanner side effects from local documentation/source before invoking them.
2. DEPS (when selected): Compare dependency declarations with existing lockfiles without synchronizing them. Use authorized live registry lookup (PyPI, npm, Go proxy) for latest direct versions, never memory; report freshness unavailable if network is not authorized. More than two major versions behind is informational maintenance data, not proof of a vulnerability.
3. SECURITY (when selected): Use only a proven nonmutating already-available scanner invocation. For Go/npm scanners, account for module downloads, caches, and lockfile effects before invocation. For Python, do not default to `uv run pip-audit`, which can prepare an environment; use an existing scanner/environment only when its exact invocation has no unauthorized side effects. For image scanners, require an already-local image and prevent pulls, database/cache preparation, and other writes. If no such invocation is established, report unavailable or request specific authority; do not install or prepare tools implicitly.
4. CONFIG (when selected): Compare parsed `.env` and `.env.example` key names only; never raw-diff, shell-source, or print values. Verify rendered configuration freshness with safe existing metadata where available. Flag missing non-secret tracked templates only under explicitly applicable template policy; do not propose tracking arbitrary gitignored files.

## Output
- Findings first: rank demonstrated vulnerabilities/configuration risks separately from dependency age and optional maintenance
- Dependency table: pkg / current / latest / behind_by
- Vulnerabilities: CVE ID / severity / package / fixed_version
- Config drift: files with mismatches, keys present in env but not example or vice versa
- Evidence/limits: selected scope, exact safe checks and results, unavailable scanners/network, and unexamined risks; no secrets or unqualified health claim
