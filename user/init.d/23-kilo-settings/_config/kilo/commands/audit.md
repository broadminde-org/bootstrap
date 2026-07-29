---
description: Audit project state — dependencies, security, configuration drift
agent: code
---

# Audit

## Usage
`/audit [scope]`

Scope options: `deps` (dependencies), `security` (CVEs), `config` (configuration drift), `all` (default).

## Scope
ALLOWED: Read all files, run audit/vulnerability scanners, check for stale config, compare lockfiles.
DENIED: Modify any files, run destructive scans, push to registries.

## Methodology
1. DEPS: For each dependency file (go.mod, pyproject.toml, package.json):
   - Check latest versions of direct deps via package-version-lookup
   - Flag any dependency >2 major versions behind
   - Verify lockfile matches dependency declarations
2. SECURITY: Run vulnerability scanners:
   - Go: `govulncheck ./...`
   - Python: `uv run safety check` or `pip-audit`
   - npm: `npm audit`
   - Docker: `trivy image <image>` or `docker scout`
3. CONFIG: Check for configuration drift:
   - Diff `.env.example` against `.env` keys
   - Verify rendered configs are fresh (template hash matches)
   - Check for gitignored files that should be tracked

## Output
- Summary: one sentence on overall health
- Dependency table: pkg / current / latest / behind_by
- Vulnerabilities: CVE ID / severity / package / fixed_version
- Config drift: files with mismatches, keys present in env but not example or vice versa
