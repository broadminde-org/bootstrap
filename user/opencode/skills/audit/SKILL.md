---
name: audit
description: Track upstream security advisories for the netbird stack's dependencies (Docker images, embedded Go binaries). Use when the user asks about CVEs, vulnerabilities, or "any open security issues?".
---
<purpose>General vulnerability-tracking workflow for the netbird stack. The stack has no MCP audit server; advisory tracking is done by reading vendor sources directly.</purpose>
<load_when>
- Task mentions CVEs, vulnerabilities, security advisories, "any open security issues?"
- Task touches the docker-compose image tags (`netbirdio/netbird-server`, `netbirdio/dashboard`, `caddy-custom:latest`)
- Task touches the Caddyfile TLS providers or the OIDC issuer configuration
- Before declaring a stack upgrade "secure" or the image supply chain "clean"
</load_when>
<sources>
The netbird stack has three image surfaces and one Go-binary surface. Each has its own advisory source:

| Surface | Source | URL |
|---|---|---|
| `netbirdio/netbird-server` | GitHub Security Advisories | `https://github.com/netbirdio/netbird/security/advisories` |
| `netbirdio/dashboard` | GitHub Security Advisories | `https://github.com/netbirdio/dashboard/security/advisories` |
| `caddy-custom:latest` | Built locally by `45-build-caddy`; inherits Caddy's deps | `https://github.com/caddyserver/caddy/security/advisories` |
| Go toolchain in caddy plugins | Go vuln DB | `https://pkg.go.dev/vuln/` |

For image scanning you can also run `docker scout` (built into Docker Desktop / Docker Engine plugin)
or pull `aquasecurity/trivy` and run `trivy image netbirdio/netbird-server:latest`. These are
optional and not required for every task.
</sources>
<workflow>
1. IDENTIFY: which dependency changed in the diff or PR?
2. CHECK_VENDOR: read the vendor's GitHub Security Advisories tab for that repo.
   Open each open advisory and judge by CVE severity whether it applies to the pinned tag.
3. CROSS_CHECK: for any Go-based image (caddy, netbird-server), run `govulncheck` against
   the source tree if available, or scan the binary with trivy.
4. DOCUMENT: in the task report, list any unfixed advisories that affect the pinned tags.
   Do NOT claim "no vulnerabilities" without listing the surfaces you checked.
5. PIN: when upgrading for a CVE fix, prefer digest pinning (`@sha256:...`) over mutable tags.
</workflow>
<anti_patterns>
- Claiming "no vulnerabilities" without listing the surfaces you checked.
- Bumping to `latest` blindly — the fix may not be in `:latest` yet, or may be coupled with breaking changes.
- Ignoring `caddy-custom` advisories because the image is built locally — Caddy's own CVE feed is what counts, not the `caddy:latest` upstream tag.
- Treating vendor "security" announcements as authoritative without checking the release notes — sometimes the "fix" is in a version that hasn't been pulled into `:latest` yet.
</anti_patterns>
<rules_of_thumb>
- "any CVEs in this stack?" -> check all four rows in <sources> -> report per image
- "is this upgrade safe?" -> check the new tag's release notes against the open advisories
- "what's affected by CVE-XXXX-YYYY?" -> identify the image(s) bundling the vulnerable package -> upgrade or pin-digest
