---
description: "Cross-cutting version-pinning patterns for non-Python ecosystems: Dockerfile OS packages, npm, Go modules, Ruby gems, Debian apt, Alpine apk."
---
<purpose>Ensure version pins in non-Python artifacts (Dockerfiles, package.json,
go.mod, Gemfile, apt sources) reflect current stable releases and that the
author can cite the source of every pin.</purpose>

<when_to_load>
- Editing a Dockerfile that runs pip install, apt-get install, apk add, or installs from a --from= image.
- Editing package.json, package-lock.json, or npm-shrinkwrap.json.
- Editing go.mod, go.sum, or any Go module manifest.
- Editing Gemfile, Gemfile.lock, or .ruby-version.
- Writing or updating a Debian package list, an Alpine apk command, or a Helm chart values.yaml.
</when_to_load>

<methodology>
1. LIVE_LOOKUP_BEFORE_PIN: before pinning, fetch the current stable version
   from the authoritative registry. State the source URL and release date in
   the commit message. Endpoints:

   | Ecosystem   | Endpoint                                                                            |
   |-------------|-------------------------------------------------------------------------------------|
   | PyPI        | https://pypi.org/pypi/<pkg>/json -> info.version                                    |
   | npm         | https://registry.npmjs.org/<pkg> -> dist-tags.latest                                 |
   | Go modules  | https://proxy.golang.org/<module>/@latest                                            |
   | RubyGems    | https://rubygems.org/api/v1/versions/<gem>.json -> [0].number                        |
   | crates.io   | https://crates.io/api/v1/crates/<crate> -> crate.max_stable_version                  |
   | Debian      | https://packages.debian.org/<distro>/<pkg> (HTML; apt-cache policy is preferred)     |
   | Alpine      | https://pkgs.alpinelinux.org/packages?name=<pkg>&branch=<vX.Y>                       |
   | Docker Hub  | https://hub.docker.com/v2/repositories/<repo>/tags/?page_size=10                     |
   | GHCR        | https://ghcr.io/token?scope=repository:<repo>:pull then /v2/<repo>/tags/list         |

2. FLOATING_RANGE_GUARD: prefer exact pins (pkg==1.2.3, pkg@1.2.3, pkg/v1.2.3)
   for runtime dependencies. For application-level libs where patch updates
   are wanted, use compatible-release (~1.2, ^1.2.3, ~> 1.2). Never use
   unbounded >=X.Y or * for a package whose major version has changed recently.
3. TRANSITIVE_LOCKFILES: respect the project's existing lockfile mechanism
   before adding manual bounds. npm -> package-lock.json, Go -> go.sum, Ruby
   -> Gemfile.lock. Do not hand-pin transitives; regenerate the lockfile and
   review the diff.
4. DOCKERFILE_BASE_IMAGE: when bumping a base image tag (e.g. python:3.11-slim
   -> python:3.13-slim), confirm:
   - The upstream tag exists at the registry (Docker Hub, GHCR, ECR).
   - The tag is not in a deprecated/unsupported branch (e.g. python:3.8-slim
     is past EOL).
   - The major bump is intentional and documented in the commit message.
5. OS_PACKAGE_PINS: apt-get install pkg=version and apk add pkg=version
   require knowing the version available in the target distribution release.
   Pin only when the version is locked by an upstream LTS / security
   requirement; otherwise prefer unpinned install plus a base-image pin so the
   whole layer is reproducible.
6. NODE_VERSION: FROM node:X should track a current LTS or current release
   (see https://nodejs.org/en/about/previous-releases). Verify the major
   version is still in active or maintenance support.
7. UPDATE_NOTIFICATION: when refreshing an existing pin, surface the diff:
   old -> new version, release date, and any changelog items that affect this
   project's usage.
</methodology>

<anti_patterns>
- MEMORY_VERSION: writing postgres:15 or redis:7 from training-data recall
  without checking the upstream. See code.md CUTOFF_AWARENESS.
- FLOATING_BASE_TAG: FROM python:slim (no version) or FROM node:latest --
  non-reproducible; layers shift silently on rebuild.
- EOL_BASE: python:3.8-slim, node:16, golang:1.19 -- past end-of-life;
  no security fixes.
- IGNORE_LOCKFILE_DIFF: merging package-lock.json / go.sum / Gemfile.lock
  changes without reading the diff.
- UNPINNED_TRANSITIVE: hand-editing a transitive dep bound without
  regenerating the lockfile.
</anti_patterns>

<verification_commands>
- PyPI: curl -s https://pypi.org/pypi/<pkg>/json | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['info']['version'], d['releases'][d['info']['version']][0]['upload_time'])"
- npm: curl -s https://registry.npmjs.org/<pkg> | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['dist-tags']['latest'])"
- Go: curl -s https://proxy.golang.org/<module>/@latest
- Ruby: curl -s https://rubygems.org/api/v1/versions/<gem>.json | python3 -c "import sys, json; print(json.load(sys.stdin)[0]['number'])"
- Docker Hub: curl -s 'https://hub.docker.com/v2/repositories/<repo>/tags/?page_size=10' | python3 -c "import sys, json; print([t['name'] for t in json.load(sys.stdin)['results'][:5]])"
</verification_commands>