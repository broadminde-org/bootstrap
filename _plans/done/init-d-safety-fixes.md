# Plan: init.d Safety Fixes — Eliminate Destructive High/Medium Risk Steps

Status: **done**

## Background

Audit of `user/init.d/` identified three scripts that destroy or overwrite
user data on re-run. The gold-standard script `12-bashrc/run.sh` demonstrates
the desired pattern: marker-bounded blocks, content-diff guards, atomic writes,
and no deletion outside managed regions.

## Fixes

### 1. `23-kilo-settings/run.sh` — HIGH: stop wiping directories and clobbering JSON

**Current behavior**: `deploy_dir()` does `rm -rf "$dst"` then `cp -r`.
`kilo.json`/`kilo.jsonc` are overwritten unconditionally. Any user-installed
agents, commands, skills, or accumulated permissions are silently destroyed.

**Fix**:

- **agents/ and commands/** (line 72-92): Replace `deploy_dir()` with
  `sync_dir_preserve()`. Iterates source files, copies each to target if it
  doesn't exist or differs from source. Never deletes files not in source.
  This means user-installed agents/commands survive re-runs, bootstrap updates
  to existing files propagate, and new bootstrap files are added.

- **kilo.json / kilo.jsonc** (lines 94-116): If target doesn't exist, copy
  source as before. If target exists, emit a diff (`diff -u target source`)
  and a warning telling the user to review and merge manually. Never silently
  overwrite. This protects accumulated permissions and user-added MCP servers.

- **skills/** (lines 118-136): Same `sync_dir_preserve()` as agents/commands.
  User-installed marketplace skills survive.

- **mcp-server/** (lines 138-172): Leave as-is. This directory is fully
  bootstrap-managed (Docker Compose + standards volume mount); no
  user-customizable content lives there.

### 2. `25-go/run.sh` — MEDIUM: stop deleting user exports outside managed block

**Current behavior**: Line 168 does a stray-export cleanup on `~/.profile`
that reaches outside the marker-bounded Go block:

```bash
sed -i '\|^# --- Go environment (managed by |,\|^# --- End Go environment ---$|!{
  /^export \(GOPRIVATE\|GOPROXY\|GOSUMDB\)=/d;
}' "$HOME/.profile"
```

This deletes any `export GOPRIVATE=/GOPROXY=/GOSUMDB=` line anywhere in
`~/.profile` that falls outside the Go managed block. A user who manually
added these exports for other tooling (or pinned their own values) loses them.

**Fix**: Remove line 168 entirely. The marker-bounded block removal on lines
164-165 already handles cleaning up the block between runs. User-set exports
outside the block are theirs to manage — don't touch them.

### 3. `30-scripts/run.sh` — MEDIUM: stop rm -rf of ~/scripts/

**Current behavior**: Line 42 does `rm -rf "$SCRIPTS_DST"` (which is
`~/scripts/`) before copying the skeleton. Any scripts the user placed there
that aren't in the bootstrap source are destroyed.

**Fix**: Use the same `sync_dir_preserve()` pattern as `23-kilo-settings`.
The runner copy loop (lines 58-66) is already safe — it only touches files
that match source names, not the whole directory.

---

## Implementation Tasks

1. Implement `sync_dir_preserve()` in `lib/common.sh` (shared helper).
2. Rewrite `23-kilo-settings/run.sh` directories to use `sync_dir_preserve()`.
3. Add create-if-missing + diff-guard for kilo.json/kilo.jsonc in `23-kilo-settings/run.sh`.
4. Remove line 168 (stray-export cleanup) from `25-go/run.sh`.
5. Rewrite `30-scripts/run.sh` scripts copy to use `sync_dir_preserve()`.
6. Review and update header comments reflecting new idempotency guarantees.

## File manifest

| File | Change |
|---|---|
| `user/init.d/lib/common.sh` | Add `sync_dir_preserve()` |
| `user/init.d/23-kilo-settings/run.sh` | Replace deploy_dir, add diff-guard for JSON |
| `user/init.d/25-go/run.sh` | Remove line 168 |
| `user/init.d/30-scripts/run.sh` | Replace `rm -rf` + `cp -r` with sync_dir_preserve |
