---
name: package-version-lookup
description: Resolve the current stable version of a package across ecosystems (PyPI, npm, Go, RubyGems, crates.io, Debian, Alpine, Docker Hub, GHCR). Use before pinning any dependency version.
---

# Package Version Lookup

## Inputs
- **pkg**: Package name (required)
- **ecosystem**: pypi | npm | go | rubygems | crates | debian | alpine | dockerhub | ghcr (required)
- **distro_or_channel**: For OS packages, the distribution codename (e.g., "bookworm"). For Docker, the tag filter.
- **count**: Number of recent releases to return (default: 5)

## Methodology
1. SELECT_ENDPOINT: Choose the registry endpoint for the given ecosystem (see endpoints table below).
2. FETCH: `curl -s -L --max-time 10 <endpoint>` with appropriate Accept header.
3. PARSE: Extract version, release date, and metadata using ecosystem-specific JSON paths.
4. RECENT_RELEASES: Return the latest version + N-1 recent releases.
5. RETURN: `latest_version`, `release_date`, `source_url`, `recent_releases` (array), `lookup_status` (ok/error/timeout), `notes`.

## Registry Endpoints
- pypi: `https://pypi.org/pypi/<pkg>/json` → `.info.version`
- npm: `https://registry.npmjs.org/<pkg>/latest` → `.version`
- go: `https://proxy.golang.org/<module>/@v/list` → last line
- rubygems: `https://rubygems.org/api/v1/gems/<gem>.json` → `.version`
- crates: `https://crates.io/api/v1/crates/<crate>` → `.crate.max_stable_version`
- debian: `apt-cache policy <pkg>` (requires Debian-based host)
- alpine: `apk policy <pkg>` (requires Alpine host or parse `https://pkgs.alpinelinux.org/`)
- dockerhub: `https://hub.docker.com/v2/repositories/<org>/<image>/tags/?page_size=5` → `.results[].name`
- ghcr: `https://ghcr.io/v2/<org>/<image>/tags/list` → `.tags[]`

## Fallback Chain
1. Live HTTP fetch from registry
2. Cached host index (if available)
3. Operator query: ask the user for the version

## Anti-Patterns
- MEMORY_RECALL: Pinning a version from memory without live lookup
- SILENT_FALLBACK: Failing to fetch and using a guess without telling the user
- UNVERSIONED_PIN: Pinning to `latest` or a floating range (`>=1.0`) without a lockfile
- SCOPE_OMISSION: Only checking direct dependencies, not transitive
