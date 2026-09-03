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
- go: `https://proxy.golang.org/<module>/@v/list` -> last line
- rubygems: `https://rubygems.org/api/v1/gems/<gem>.json` -> `.version`
- crates: `https://crates.io/api/v1/crates/<crate>` -> `.crate.max_stable_version`
- debian: `apt-cache policy <pkg>`; alpine: `apk policy <pkg>`
- dockerhub: `https://hub.docker.com/v2/repositories/<org>/<image>/tags/?page_size=5`
- ghcr: `https://ghcr.io/v2/<org>/<image>/tags/list`

## Methodology
1. Run the local command first: installed CLI `--help`, lockfiles, and `git show` are ground truth.
2. If absent, fetch the registry API with `curl -s -L --max-time 10`.
3. Return latest version, release date, source URL, recent releases, status, and notes.

## Fallback Chain
1. Local ground truth; 2. live registry; 3. cached index; 4. ask the operator.

## Anti-Patterns
- MEMORY_RECALL: Pinning a version from memory.
- SILENT_FALLBACK: Guessing after a failed lookup.
- UNVERSIONED_PIN: Using `latest` or a floating range without a lockfile.
- SCOPE_OMISSION: Ignoring transitive dependencies.
- WEB_FIRST: Fetching rendered web pages for facts available locally; use raw sources only when local ground truth is absent.
