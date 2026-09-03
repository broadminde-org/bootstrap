# Kilo Codebase Indexing Exclusions

Date: 2026-09-03
Scope: Host-wide Kilo indexing configuration, with comparisons between
`~/ee` and `~/bootstrap`.
Status: Review report. No indexing or ignore-file changes are applied by this
report.

## Executive Summary

The host-wide Kilo configuration currently enables indexing and selects Kilo's
hosted embedding service:

- Provider: `kilo`
- Model: `mistralai/mistral-embed-2312`
- Vector store: LanceDB default
- Global file-extension allowlist: not configured
- Global watcher exclusions: not configured

Kilo therefore uses its built-in language/file list, then applies its built-in
filters and workspace-level ignore rules.

The main exclusion issue is in `~/ee/.kilocodeignore`: it excludes generated
result directories and then re-includes them at the end. The current Kilo
cache contains files from `ee/shared/test-results/`, confirming that those
generated artifacts are candidates for indexing.

`~/bootstrap` has no `.kilocodeignore` file. It currently relies on Kilo's
built-in exclusions and the repository's `.gitignore`, which is not an
adequate explicit indexing policy for the new host standard.

## Configuration Sources

### Global Kilo configuration

File: `~/.config/kilo/kilo.jsonc`

```json
{
  "$schema": "https://app.kilo.ai/config.json",
  "permission": {
    "bash": "allow"
  },
  "indexing": {
    "enabled": true,
    "provider": "kilo",
    "model": "mistralai/mistral-embed-2312"
  }
}
```

`kilo debug config` resolves the provider and model, but does not display the
`enabled` property. The indexing UI/plugin appears to handle that toggle
separately. `kilo config check` reports no warnings.

The Kilo logs show indexing initialization for both workspaces:

- `/home/luke/bootstrap` at approximately `20:26` on 2026-09-03
- `/home/luke/ee` at approximately `20:36` on 2026-09-03

The live state directory contains LanceDB data under:

```text
~/.local/state/kilo/indexing/lancedb/
```

### Project configuration

No project-level `kilo.json`, `kilo.jsonc`, or `.kilo/kilo.jsonc` indexing
override was found in either `~/ee` or `~/bootstrap`.

No `watcher.ignore` configuration was found. `watcher.ignore` is a separate
file-watcher setting and should not be treated as the semantic-index
exclusion mechanism.

### VS Code settings

`~/bootstrap/user/vscode/settings.json` contains:

- `search.exclude`
- `files.watcherExclude`

These affect VS Code text search and VS Code file watching. They do not define
Kilo semantic-index exclusions.

## Kilo's Built-in Behavior

According to the current Kilo Codebase Indexing documentation, when
`indexing.fileExtensions` is omitted, Kilo uses its built-in language list.
Supported formats include Go, Python, JavaScript, TypeScript, Svelte, Vue,
CSS, HTML, YAML, TOML, JSON, Markdown, Rust, Java, C-family languages, and
others.

The indexer then automatically excludes:

- Binary files and images
- Files larger than 1 MB
- `.git/` repositories
- Dependency directories such as `node_modules/` and `vendor/`
- Files matching `.gitignore` and `.kilocodeignore` patterns
- Additional hardcoded directory and file patterns

Kilo parses supported source files with Tree-sitter, uses a Markdown parser for
documentation, and uses line-based chunking for supported text formats that do
not have a Tree-sitter parser.

## Current `ee` Exclusions

File: `~/ee/.kilocodeignore`

The file currently excludes these categories:

### Dependencies and build output

```gitignore
node_modules/
vendor/
dist/
build/
.svelte-kit/
.output/
bin/
pkg/
```

### Locks and generated checksums

```gitignore
package-lock.json
yarn.lock
pnpm-lock.yaml
go.sum
go.work.sum
```

### Test and coverage output

```gitignore
coverage.out
coverage.html
*.cover
test-results/
```

### Environment and secrets

```gitignore
*.pem
*.key
*.p12
*.pfx
```

The `.env.example` negation intentionally allows example environment files:

```gitignore
!.env.example
```

### Logs and databases

```gitignore
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.bolt/
*.db
*.sqlite
logs/
```

### Archives, old code, and editor state

```gitignore
*.tar.gz
*.tar
*.zip
*.gz
archive/
temp/
_apps_old/
.windsurf/
_copilot/
.DS_Store
.idea/
.vscode/
.history/
```

### Contradictory re-inclusions

The file ends with:

```gitignore
!**/feedback/
!**/test-results/
!**/build-results/
!**/update-results/
```

The last three rules re-include generated result trees that earlier rules and
comments describe as excluded. Because Kilo documents `.kilocodeignore` as an
indexing filter as well as an access filter, these negations allow generated
reports back into the indexing candidate set.

The current cache contains files under `ee/shared/test-results/`, including
Markdown reports and JSON lint output.

## Current `bootstrap` Exclusions

`~/bootstrap` has no `.kilocodeignore` file.

Its `.gitignore` excludes only a small set of repository artifacts:

```gitignore
**/llmdocs/_build/
**/llmdocs/ref/
**/llmdocs/llmdocs_examples/**/_build/
**/llmdocs/llmdocs_examples/**/ref/
__pycache__/
*.py[cod]
*.egg-info/
.pytest_cache/
.venv/
bootstrap.conf.yml
*deepseek-v4-plan*.md
.DS_Store
```

The repository is only about 11 MB and contains mostly shell scripts,
documentation, and provisioning code. It does not have the same dependency
and generated-output volume as `ee`, but it still benefits from explicit
exclusions for Python caches, generated documentation builds, Kilo/session
reports, and scratch runs.

The following directories exist or are relevant to bootstrap's tooling:

- `.kilo/`
- `.kilocode/`
- `context-workshop/_runs/`
- `kilo-session-reports/`
- `user/init.d/10-llmdocs/**/_build/`
- `user/init.d/10-llmdocs/**/ref/`

The project `.kilo/` and `.kilocode/` trees should not be excluded wholesale
without review. They contain agent context, skills, plans, and configuration
that may be useful to semantic search.

## Cache Evidence

The Kilo state directory contains `roo-index-cache-*.json` files and LanceDB
data. The cache files are incremental state, not the authoritative configured
file list, and some are historical.

Known cache observations:

- The cache hash for `/home/luke/ee` is
  `0d6d9c18a87baee102fa9c9a5d8a066392c222674e455391559cd276449b16bf`.
- A recent cache for that workspace contained 6 paths.
- An older cache contained 151 `~/ee` paths.
- Across cache files, at least 152 unique `~/ee` paths were observed.
- The observed `~/ee` paths included 72 JSON, 26 Markdown, 22 Python, 16 Go,
  10 CSS, 4 TypeScript, 1 JavaScript, and 1 YAML file.
- The observed top-level areas included `shared/backend`, `apps/enki`,
  `shared/py`, and several application frontends.
- Files under `ee/shared/test-results/` were present because of the explicit
  negation rules.

These numbers should be treated as evidence of prior indexing activity, not as
a claim that the cache is complete or current.

## Proposed Standard Changes

These are recommendations for review, not applied changes.

### Changes applicable to `ee`

Remove the re-inclusions for generated result directories:

```diff
- !**/test-results/
- !**/build-results/
- !**/update-results/
```

Add common generated/cache exclusions:

```gitignore
# Additional generated and tool caches
**/.cache/
**/.pytest_cache/
**/.ruff_cache/
**/.mypy_cache/
**/.tox/
**/.nox/
**/.eggs/
**/.direnv/
**/.dev/
**/.turbo/
**/.parcel-cache/
**/.next/
**/.nuxt/
**/playwright-report/
**/.playwright/
coverage/
*.pyc
*.pyo
*.pyd
*.map
*.sqlite3
*.dump
*.bak
*.backup
```

The `*.map` rule is appropriate if source-map debugging is not a normal
activity. Source maps are generated artifacts and generally duplicate source
content.

The `feedback/` re-inclusion should remain for now because human-written
feedback may contain useful context. If completed feedback is predominantly
historical noise, consider adding:

```gitignore
**/feedback/done/
```

### Changes applicable to `bootstrap`

Add a root-level `~/bootstrap/.kilocodeignore` containing:

```gitignore
# Generated documentation builds
**/llmdocs/_build/
**/llmdocs/ref/

# Python caches and environments
**/__pycache__/
*.py[cod]
**/*.egg-info/
**/.pytest_cache/
**/.venv/

# Generated reports and local scratch
kilo-session-reports/
context-workshop/_runs/
.tmp/
temp/
```

Do not exclude `.kilo/` or `.kilocode/` as a whole in the initial standard.
Review their generated versus authored contents separately first.

## Global Extension Allowlist

Do not add `indexing.fileExtensions` globally in the first pass.

Kilo documents that a configured list replaces the built-in defaults rather
than extending them. A global allowlist could therefore silently omit useful
formats from unrelated workspaces. It is also not a directory exclusion
mechanism and cannot solve the generated-report problem by itself.

If exclusions are still insufficient after re-indexing, a later host-wide
allowlist could include source and documentation formats such as:

```json
"fileExtensions": [
  ".go",
  ".py",
  ".js",
  ".jsx",
  ".ts",
  ".tsx",
  ".svelte",
  ".vue",
  ".css",
  ".html",
  ".sql",
  ".sh",
  ".bash",
  ".yml",
  ".yaml",
  ".json",
  ".jsonc",
  ".toml",
  ".md",
  ".tf"
]
```

This should be treated as a deliberate second-stage optimization, not the
default standard.

## Tradeoffs

`.kilocodeignore` is not documented as an index-only ignore file. It also
affects Kilo Code's ability to access files. Removing the result-directory
negations will improve semantic-index quality, but may prevent agents from
reading those reports through Kilo file-access tools.

The choices are therefore:

1. Prioritize index quality: exclude generated results and accept that agents
   may need another route to inspect them.
2. Prioritize direct report access: retain the negations and accept that
   generated reports remain index candidates.
3. Use a narrower future Kilo feature or configuration if an index-only
   exclusion mechanism becomes available.

The recommended initial choice is option 1 for `test-results`,
`build-results`, and `update-results`, while retaining authored `feedback/`.

## Verification Plan After Approval

After deciding on the standard set:

1. Apply the selected `.kilocodeignore` changes to `~/ee` and add the new file
   to `~/bootstrap`.
2. Run `kilo config check`.
3. Restart Kilo Code or reload its configuration.
4. Confirm the indexing indicator reaches a stable state for each workspace.
5. Confirm generated result paths no longer appear in newly written cache
   entries.
6. Confirm representative source and documentation files remain indexed:
   Go, Python, TypeScript/Svelte, shell, YAML, JSON, and Markdown.
7. Test direct access to a recent test report so the `.kilocodeignore` access
   tradeoff is explicit.
8. Preserve or remove old LanceDB/cache state only as a separate cleanup
   decision; ignore-file changes alone may not purge historical vectors.

## Files Reviewed

- `~/.config/kilo/kilo.json`
- `~/.config/kilo/kilo.jsonc`
- `~/ee/.kilocodeignore`
- `~/ee/.gitignore`
- `~/bootstrap/.gitignore`
- `~/bootstrap/user/vscode/settings.json`
- `~/bootstrap/user/init.d/37-kilo-settings/_config/kilo/kilo.json`
- `~/bootstrap/user/init.d/37-kilo-settings/run.sh`
- `~/bootstrap/user/init.d/36-kilo/run.sh`
- `~/bootstrap/user/init.d/37-kilo-settings/CONTEXT-SET-GAPS.md`
- `~/.local/state/kilo/indexing/roo-index-cache-*.json`
- `~/.local/state/kilo/indexing/lancedb/`
- Kilo documentation: `https://kilo.ai/docs/customize/context/codebase-indexing`
- Kilo documentation: `https://kilo.ai/docs/customize/context/kilocodeignore`
