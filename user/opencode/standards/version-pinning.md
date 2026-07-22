# Version Pinning

## Scope
Adding or updating dependencies across all ecosystems (Go, Python, npm, Docker, Debian/Alpine packages).

## Methodology
1. LIVE_LOOKUP: Query the package registry for the latest version before pinning. Never rely on memory.
2. EXACT_PIN: Prefer exact version pins (`==X.Y.Z`, `vX.Y.Z`) over floating ranges.
3. LOCKFILE: All ecosystems must commit lockfiles (`go.sum`, `uv.lock`, `package-lock.json`).
4. DOCKER_BASE: Verify base image tag is the latest patch release within the target minor version.
5. OS_PACKAGES: Version-pin `apt-get install <pkg>=<version>` and `apk add <pkg>=<version>` in Dockerfiles.
6. NOTIFY: Commit messages must mention version updates explicitly (e.g., "build(deps): bump caddy to 2.9.1").

## Registry Endpoints
- PyPI: `curl -s "https://pypi.org/pypi/<pkg>/json" | python3 -c "import sys,json; print(json.load(sys.stdin)['info']['version'])"`
- npm: `curl -s "https://registry.npmjs.org/<pkg>/latest" | python3 -c "import sys,json; print(json.load(sys.stdin)['version'])"`
- Go: look up releases at `https://proxy.golang.org/<module>/@v/list`
- RubyGems: `curl -s "https://rubygems.org/api/v1/gems/<gem>.json"`
- Debian: `apt-cache policy <pkg>` (bookworm-backports aware)
- Alpine: `apk policy <pkg>`
- DockerHub: `curl -s "https://hub.docker.com/v2/repositories/<org>/<image>/tags/?page_size=5"`
- GHCR: `curl -s "https://ghcr.io/v2/<org>/<image>/tags/list"`

## Anti-Patterns
- MEMORY_VERSION: Pinning a version from memory without live lookup
- FLOATING_BASE_TAG: `FROM python:3` without a minor version
- EOL_BASE: Using a base image that is end-of-life
- IGNORE_LOCKFILE_DIFF: Making dependency changes without committing the lockfile update
- UNPINNED_TRANSITIVE: Not reading the lockfile to check transitive dependency freshness
