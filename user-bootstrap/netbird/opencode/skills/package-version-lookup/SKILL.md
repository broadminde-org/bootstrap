---
name: package-version-lookup
description: >-
  Resolve the current stable version of a package across ecosystems (PyPI, npm,
  Go modules, RubyGems, crates.io, Debian, Alpine, Docker Hub, GHCR). Use this
  skill whenever a task requires pinning or bumping a package version, base
  image tag, or CLI tool version.
---
<purpose>Provide a single, consistent lookup interface for "what is the current
stable version of <pkg> in <ecosystem>?" so the answer is always grounded in a
live registry, not in model recall.</purpose>

<inputs>
- pkg (required): the package name. For scoped npm packages, include the
  scope (@scope/name). For Go modules, include the full module path.
- ecosystem (required): one of pypi, npm, go, rubygems, crates, debian,
  alpine, dockerhub, ghcr.
- distro_or_channel (optional, for debian/alpine/dockerhub): the distribution
  release (e.g. bookworm, v3.20, python).
- count (optional, default 5): how many recent releases to return.
</inputs>

<methodology>
1. SELECT_ENDPOINT: pick the authoritative JSON endpoint for the ecosystem.
   See <endpoints> below.
2. FETCH: invoke curl -s <endpoint>. If the request fails (HTTP non-200,
   timeout, DNS error), record the failure and surface it to the caller -- do
   not fall back to a memorized version.
3. PARSE: extract the relevant field:
   - pypi      -> info.version, then releases[info.version][0].upload_time
   - npm       -> dist-tags.latest, then time.modified
   - go        -> body is the version string; @v info endpoint for date
   - rubygems  -> first item in array: number, created_at
   - crates    -> crate.max_stable_version, crate.updated_at
   - debian    -> HTML; use apt-cache policy on a current host as primary
   - alpine    -> HTML; use apk search -e on a current Alpine image as primary
   - dockerhub -> list results, sort by last_updated
   - ghcr      -> tags[] sorted by last_updated
4. RECENT_RELEASES: list the most recent count releases with version and
   release date. This gives the operator a sense of release cadence.
5. RETURN: emit a structured result:
   - latest_version
   - release_date
   - source_url
   - recent_releases (list of {version, date})
   - lookup_status (ok | partial | failed)
   - notes (deprecation warnings, EOL signals, security advisories if
     visible in the response)
</methodology>

<endpoints>
| Ecosystem | Endpoint                                                                          | Field                          |
|-----------|-----------------------------------------------------------------------------------|--------------------------------|
| pypi      | https://pypi.org/pypi/<pkg>/json                                                  | info.version                   |
| npm       | https://registry.npmjs.org/<pkg>                                                  | dist-tags.latest               |
| go        | https://proxy.golang.org/<module>/@latest                                         | body (raw)                     |
| rubygems  | https://rubygems.org/api/v1/versions/<gem>.json                                   | [0].number                     |
| crates    | https://crates.io/api/v1/crates/<crate>                                           | crate.max_stable_version       |
| debian    | https://packages.debian.org/<distro>/<arch>/<pkg>                                 | scrape; apt-cache policy first |
| alpine    | https://pkgs.alpinelinux.org/packages?name=<pkg>&branch=<vX.Y>                    | scrape; apk search first       |
| dockerhub | https://hub.docker.com/v2/repositories/<repo>/tags/?page_size=<n>                | results[].name by last_updated |
| ghcr      | https://ghcr.io/token?scope=repository:<repo>:pull  ->  /v2/<repo>/tags/list     | tags[]                         |
</endpoints>

<fallback_chain>
1. Live HTTP fetch on the authoritative endpoint.
2. Cached index on the host (apt-cache policy, apk search, uv cache).
3. Operator query -- surface inability to the caller rather than fabricating
   a version.
</fallback_chain>

<anti_patterns>
- MEMORY_RECALL: do not answer from training data when a live fetch is
  possible. The model's cutoff may be months behind.
- SILENT_FALLBACK: if the live fetch fails, do not silently substitute a
  memorized version. Surface the failure.
- UNVERSIONED_PIN: never return just "latest" or "current" -- always return
  a concrete version string with a release date.
- SCOPE_OMISSION: for npm, @types/node != node and @babel/core != babel-core.
  Get the exact name right.
</anti_patterns>

<integration>
- Triggered by: code.md VERSION_CURRENCY and VERSION_LOOKUP rules and
  methodology step 12.
- Consults: per-language patterns in rules/version-pinning.md and
  rules/python/version-pinning.md for ecosystem-specific quirks.
- Used by: ee-docs (which has webfetch: allow) and by code.md directly
  via bash+curl when ee-docs delegation is undesirable.
</integration>