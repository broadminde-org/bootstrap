---
name: audit
description: Track upstream security advisories for project dependencies. Use when checking for CVEs, vulnerabilities, or before updating dependencies.
---

# Audit: Upstream Security Advisories

## Workflow
1. IDENTIFY: List all external dependencies from build files, lockfiles, and Docker base images.
2. CHECK_VENDOR: Query vendor advisories (GitHub Security Advisories, Go vuln DB, npm audit, PyPA advisory DB, CVE database).
3. CROSS_CHECK: Run language-specific vulnerability scanners (`govulncheck`, `npm audit`, `uv run safety check`, `trivy`).
4. DOCUMENT: List all unfixed advisories with CVE IDs, severity, affected versions, and fixed versions.
5. PIN: For fixes available in newer versions, pin to the fixed version. For unfixed, document mitigation.

## Anti-Patterns
- BLANKET_SAFE: "No vulnerabilities found" without listing every surface checked
- BLIND_BUMP: Updating to latest without checking changelog for breaking changes
- IGNORE_TRANSITIVE: Only checking direct dependencies, missing transitive vulnerability chains
