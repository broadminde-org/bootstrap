#!/usr/bin/env bash
# version.sh — Shared helpers for per-project version + build-number display.
#
# Generalized from the ee monorepo's infra/mcp/lib/version.sh (EE_ROOT →
# PROJECT_DIR). Installed by user/init.d/30-scripts into
# $HOME/scripts/lib/version.sh.
#
# Source from any script that needs to read/bump/print a project's version
# info. Requires the sourcing script to have PROJECT_DIR set.
#
# Functions:
#   read_build_number <dir>         → echo current build#, or 0 if file missing
#   next_build_number <dir>         → echo (current + 1); does NOT write
#   write_build_number <dir> <n>    → write n to <dir>/.build-number
#   app_version_string <name> <dir> → echo "<name> v<semver> build <N> (<sha>)"
#                                     or "<name> (<sha>)" if no VERSION file
#   print_app_version <name> <dir>  → prints banner via the caller's log helper
#
# Both version functions take a directory (not a name) so callers don't have
# to hardcode project paths. The "tolerate missing VERSION" guard lives
# inside app_version_string — callers no longer need to know about it.

_appver_read_file() {
  # $1 = path. Echoes trimmed content, or empty if file missing.
  local path="$1"
  [[ -f "$path" ]] || { echo ""; return; }
  tr -d '[:space:]' < "$path"
}

read_build_number() {
  local app_dir="$1"
  local raw
  raw=$(_appver_read_file "${app_dir}/.build-number")
  [[ -z "$raw" || ! "$raw" =~ ^[0-9]+$ ]] && raw=0
  echo "$raw"
}

next_build_number() {
  local app_dir="$1"
  local cur
  cur=$(read_build_number "$app_dir")
  echo $((cur + 1))
}

write_build_number() {
  local app_dir="$1"
  local n="$2"
  printf '%s\n' "$n" > "${app_dir}/.build-number"
}

app_version_string() {
  # $1 = project name (used in the banner)
  # $2 = project directory (where to look for VERSION / .build-number)
  # Tolerates missing VERSION — non-versioned projects get a minimal
  # "<name> (<git_sha>)" banner instead of "<name> v0.0.0 ...".
  local name="$1"
  local app_dir="$2"
  local semver build_num git_sha
  semver=$(_appver_read_file "${app_dir}/VERSION")
  git_sha=$(git -C "${PROJECT_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)
  if [[ -z "$semver" ]]; then
    # No VERSION file → minimal banner. Don't fabricate "v0.0.0".
    echo "${name} (${git_sha})"
    return 0
  fi
  build_num=$(read_build_number "$app_dir")
  echo "${name} v${semver} build ${build_num} (${git_sha})"
}

print_app_version() {
  # $1 = project name. $2 = project directory.
  # Uses caller's `log` helper if defined; otherwise plain echo.
  local name="$1"
  local dir="$2"
  local msg
  msg=$(app_version_string "$name" "$dir")
  if declare -F log >/dev/null 2>&1; then
    log "$msg"
  else
    echo "==> $msg"
  fi
}
