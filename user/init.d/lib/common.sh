#!/usr/bin/env bash
set -euo pipefail

# Common environment and privilege setup for user init.d scripts.
#
# Sources the unified conf.sh (bootstrap/init.d/lib/conf.sh), calls load_conf
# to populate toolchain version pins from the versions: section of
# bootstrap.conf.yml, then refuses to run as root.
#
# The user-side steps install per-user tooling into $HOME — they MUST run as
# the deploy user, not as root. Each step locates its own bundled assets
# relative to its own BASH_SOURCE[0].

if [ "$(id -u)" -eq 0 ]; then
  echo "Error: user scripts must NOT be run as root." >&2
  echo "Log in as the deploy user (e.g., luke) and rerun." >&2
  exit 1
fi

# Source the unified config reader AFTER the non-root check so root callers
# fail fast without inheriting its exports.
# conf.sh honors $BOOTSTRAP_CONFIG_FILE (exported by user/init.sh) and
# otherwise auto-locates bootstrap.conf.yml relative to its own path.
# shellcheck source=../../../init.d/lib/conf.sh
. "$(dirname "${BASH_SOURCE[0]}")/../../../init.d/lib/conf.sh"

# Load the config in this shell process. We read _TOOL_VERSION directly below
# (not via $() subshells) so that load_conf runs exactly once and only one
# "Using bootstrap config:" line appears per step invocation.
load_conf

# Environment-variable overrides take precedence over bootstrap.conf.yml.
# Export toolchain version pins for steps that reference them directly.
# Steps that receive "latest" resolve the concrete version themselves via
# their own API calls.
export EE_UV_VERSION="${EE_UV_VERSION:-${_TOOL_VERSION[uv]:-latest}}"
export EE_PYTHON_VERSION="${EE_PYTHON_VERSION:-${_TOOL_VERSION[python]:-latest}}"
export KILO_VERSION="${KILO_VERSION:-${_TOOL_VERSION[kilo]:-latest}}"
export EE_GO_VERSION="${EE_GO_VERSION:-${_TOOL_VERSION[go]:-latest}}"
export EE_NODE_VERSION="${EE_NODE_VERSION:-${_TOOL_VERSION[node]:-latest}}"
export CGO_ENABLED="${CGO_ENABLED:-0}"

# sync_dir_preserve() — copy source files into an existing directory without
# ever deleting anything in the target. For each regular file in src:
#   - If dest file does not exist: copy it in (new bootstrap addition).
#   - If dest file exists and differs from source: copy it in (update).
#   - If dest file exists and is identical: skip.
# Files in dest that are not in src are left untouched — user-installed
# extras survive re-runs. Destination-only executables are reported for
# manual review; symlinks are never traversed and __pycache__ is ignored.
sync_dir_preserve() {
  local src="$1"
  local dst="$2"

  if [[ -L "$src" || ! -d "$src" ]]; then
    echo "    sync_dir_preserve: required source $src not found" >&2
    return 1
  fi
  if [[ -L "$dst" ]]; then
    echo "    sync_dir_preserve: refusing symlink destination $dst" >&2
    return 1
  fi
  mkdir -p "$dst"

  local added=0 updated=0 skipped=0 unsafe=0
  local item rel_path dst_path mode parent path_part current
  local -a _parts=()
  declare -A managed_paths=()

  while IFS= read -r -d '' item; do
    rel_path="${item#"$src"/}"
    managed_paths["$rel_path"]=1
    dst_path="$dst/$rel_path"

    # Do not copy through a symlink at any destination path component.
    current="$dst"
    IFS='/' read -ra _parts <<< "$rel_path"
    for path_part in "${_parts[@]}"; do
      current="$current/$path_part"
      if [[ -L "$current" ]]; then
        echo "    sync_dir_preserve: skipping unsafe symlink $current" >&2
        ((unsafe++)) || true
        break
      fi
    done
    [[ -L "$current" ]] && continue

    if [[ -f "$item" ]]; then
      if [[ -x "$item" ]]; then mode=0755; else mode=0644; fi
      if [[ ! -f "$dst_path" ]]; then
        parent="$(dirname "$dst_path")"
        mkdir -p "$parent"
        cp "$item" "$dst_path"
        chmod "$mode" "$dst_path"
        ((added++)) || true
      elif ! cmp -s "$item" "$dst_path"; then
        cp "$item" "$dst_path"
        chmod "$mode" "$dst_path"
        ((updated++)) || true
      else
        chmod "$mode" "$dst_path"
        ((skipped++)) || true
      fi
    fi
  done < <(find "$src" -type f -print0)

  local extra
  while IFS= read -r -d '' extra; do
    rel_path="${extra#"$dst"/}"
    if [[ -z "${managed_paths[$rel_path]+x}" ]]; then
      echo "    sync_dir_preserve: unmanaged destination executable: ${rel_path}" >&2
    fi
  done < <(find "$dst" -type d -name __pycache__ -prune -o -type f -perm /111 -print0)

  echo "    sync_dir_preserve $dst: ${added} added, ${updated} updated, ${skipped} unchanged, ${unsafe} unsafe symlink(s) skipped"
  (( unsafe == 0 ))
}
