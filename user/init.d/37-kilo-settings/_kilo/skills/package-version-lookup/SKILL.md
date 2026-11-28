---
name: package-version-lookup
description: Pin or upgrade dependencies and research CLI flags or syntax using local ground truth and registry APIs.
---

# Package Version Lookup

## Inputs
- `pkg`, `ecosystem`, optional `distro_or_channel`, and release `count` (default 5).

## Registry Endpoints
- pypi: `https://pypi.org/pypi/<pkg>/json` -> `.info.version`
- npm: `https://registry.npmjs.org/<pkg>/latest` -> `.version`
- go (public modules only): `https://proxy.golang.org/<escaped-module>/@v/list` -> unordered tagged versions, not a latest-version result. Use the canonical module path (including applicable `/vN` suffix); proxy escaping replaces uppercase letters with `!` plus lowercase.
- rubygems: `https://rubygems.org/api/v1/gems/<gem>.json` -> `.version`
- crates: `https://crates.io/api/v1/crates/<crate>` -> `.crate.max_stable_version`
- debian: `apt-cache policy <pkg>`; alpine: `apk policy <pkg>`
- dockerhub: `https://hub.docker.com/v2/repositories/<org>/<image>/tags/?page_size=5`
- ghcr: `https://ghcr.io/v2/<org>/<image>/tags/list`

## Methodology
1. Inspect installed package metadata, lockfiles, configured channels, and local source first. Run an installed CLI's `--help` only when execution and its side effects are authorized; a manifest range is not an exact installed version.
2. For missing version/CLI facts, use the official registry/API or version-matched raw documentation under network authority. For an authorized public HTTP lookup, `curl --fail --silent --show-error --location --max-time 10` detects HTTP failures; validate payload type/schema/version before using it. Never treat an error page or malformed/empty result as a version or emit raw sensitive responses.
3. For Go, inspect effective `GOPRIVATE`, `GONOPROXY`, `GONOSUMDB`, `GOPROXY`, `GOSUMDB`, module replacements, and the existing private-access owner before a query. Never send private or unclassified module paths to a public proxy, index, checksum service, or search engine. `GOPRIVATE` does not protect a hand-built HTTP request. Use the approved private route only; missing access is a blocker, not permission to provision credentials.
4. Prefer an authorized `go list -m -json 'module/path@latest'` for Go's release/prerelease/pseudo-version and retraction semantics. `@v/list` has no ordering guarantee; semantic ordering is not lexical ordering. Go queries can contact the network, populate caches, load module metadata, or select/download a toolchain: inspect the command/environment and obtain side-effect authority, never run it merely as a supposedly read-only check.
5. Report the resolved version/channel, source URL, recency/cache status, and requested recent releases/date where verified. Mark unavailable fields explicitly. Route failures/log investigation to `debug-with-logs`; do not prepare dependencies or change pins as part of a lookup without authority.

Go semantics and privacy: [module proxy protocol](https://go.dev/ref/mod#goproxy-protocol), [version queries](https://go.dev/ref/mod#version-queries), and [private-module privacy](https://go.dev/ref/mod#private-module-privacy). Registry tags and cached indexes can be stale; do not equate their order or cache time with release order/date.

## Fallback Chain
1. Local ground truth; 2. live registry; 3. cached index; 4. ask the operator.

## Anti-Patterns
- MEMORY_RECALL: Pinning a version from memory.
- SILENT_FALLBACK: Guessing after a failed lookup.
- UNVERSIONED_PIN: Using `latest` or a floating range without a lockfile.
- SCOPE_OMISSION: Ignoring transitive dependencies.
- WEB_FIRST: Fetching rendered web pages for facts available locally; use raw sources only when local ground truth is absent.
