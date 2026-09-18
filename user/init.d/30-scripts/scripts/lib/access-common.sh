#!/usr/bin/env bash
# access-common.sh — shared helpers for the interactive access scripts
# (bootstrap-access, github-access). Sourced, not executed.
#
# Lives at user/init.d/30-scripts/scripts/lib/access-common.sh in the
# bootstrap checkout and is deployed to ~/scripts/lib/ by the 30-scripts
# step alongside the scripts themselves.
#
# Functions:
#   log / ok / warn / fail           colored status output
#   require_deploy_user              abort when running as root
#   resolve_bootstrap_root           print the bootstrap checkout root
#                                    (requires SCRIPT_DIR from the caller)
#   file_env_value <file> <name>     print the last NAME=value in <file>
#   write_env_value <file> <n> <v>   atomically replace/add NAME=value (0600)
#   delete_env_value <file> <name>   atomically remove NAME=value entries
#   read_token_file <file>           print the token stored in <file>
#   write_token_file <file> <token>  atomically write a token file (0600)
#   delete_token_file <file>         remove a token file if present

# Guard against double-sourcing (same pattern as lib/env.sh).
[ -n "${_ACCESS_COMMON_SH_LOADED:-}" ] && return 0
_ACCESS_COMMON_SH_LOADED=1

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

log()  { echo -e "\033[1;34m==>\033[0m $*"; }
ok()   { echo -e "\033[1;32m  ✓\033[0m $*"; }
warn() { echo -e "\033[1;33m  ⚠\033[0m $*"; }
fail() { echo -e "\033[1;31m  ✗\033[0m $*" >&2; }

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------

# Refuse to run as root. $0 is the sourcing (main) script, so the message
# names the command the operator actually ran.
require_deploy_user() {
  if [[ $EUID -eq 0 ]]; then
    fail "$(basename "$0") must run as the deploy user, not root."
    echo "  Run it without sudo from an interactive SSH session." >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Bootstrap checkout resolution
# ---------------------------------------------------------------------------

# resolve_bootstrap_root — print the bootstrap checkout root:
#   1. $BOOTSTRAP_ROOT when set;
#   2. the source checkout, when the script runs from
#      <repo>/user/init.d/30-scripts/scripts/;
#   3. ~/bootstrap (deployed layout: ~/scripts/).
# Requires the sourcing script to have set SCRIPT_DIR.
resolve_bootstrap_root() {
  if [[ -n "${BOOTSTRAP_ROOT:-}" ]]; then
    printf '%s\n' "$BOOTSTRAP_ROOT"
    return 0
  fi

  local source_checkout
  if source_checkout="$(cd "$SCRIPT_DIR/../../../.." 2>/dev/null && pwd)"; then
    if [[ -x "$source_checkout/user/init.sh" ]]; then
      printf '%s\n' "$source_checkout"
      return 0
    fi
  fi

  printf '%s\n' "$HOME/bootstrap"
}

# ---------------------------------------------------------------------------
# KEY=value file helpers
# ---------------------------------------------------------------------------

# file_env_value <file> <name> — print the last NAME=value entry in <file>.
# Returns 1 when the file is missing or the value is empty.
file_env_value() {
  local file="$1" name="$2" value=""

  [[ -f "$file" ]] || return 1
  value="$(sed -n "s/^${name}=//p" "$file" | tail -n 1)"
  [[ -n "$value" ]] || return 1
  printf '%s\n' "$value"
}

# write_env_value <file> <name> <value> — atomically replace or add a
# NAME=value entry, keeping the file at mode 0600. Other entries (and their
# order) are preserved.
write_env_value() {
  local file="$1" name="$2" value="$3" tmp=""

  mkdir -p "$(dirname "$file")"
  touch "$file"
  chmod 600 "$file"

  tmp="$(mktemp "$(dirname "$file")/.env.XXXXXX")"
  trap 'rm -f "$tmp"' RETURN

  grep -vE "^${name}=" "$file" > "$tmp" || true
  printf '%s=%s\n' "$name" "$value" >> "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$file"
  trap - RETURN
}

# delete_env_value <file> <name> — atomically remove every NAME= entry from
# <file>. Succeeds silently when the file or the entry does not exist. Mode
# 0600 is preserved on the rewritten file.
delete_env_value() {
  local file="$1" name="$2" tmp=""

  [[ -f "$file" ]] || return 0
  grep -qE "^${name}=" "$file" || return 0

  tmp="$(mktemp "$(dirname "$file")/.env.XXXXXX")"
  trap 'rm -f "$tmp"' RETURN

  grep -vE "^${name}=" "$file" > "$tmp" || true
  chmod 600 "$tmp"
  mv -f "$tmp" "$file"
  trap - RETURN
}

# ---------------------------------------------------------------------------
# Token file helpers
#
# Dedicated token files under ~/.config/gh/ are the authoritative store for
# the Broadminde classic PATs (see docs/adr/0001-github-pat-storage.md).
# One token per file, mode 0600. The bootstrap checkout .env is never a
# store for these tokens.
# ---------------------------------------------------------------------------

# read_token_file <file> — print the token (first line) stored in <file>.
# Returns 1 when the file is missing or the value is empty.
read_token_file() {
  local file="$1" value=""

  [[ -f "$file" ]] || return 1
  value="$(<"$file")"
  value="${value%%$'\n'*}"
  value="${value%$'\r'}"
  [[ -n "$value" ]] || return 1
  printf '%s\n' "$value"
}

# write_token_file <file> <token> — atomically write <token> to <file> with
# mode 0600. Creates the parent directory (mode 0700) when missing; an
# existing directory's permissions are left alone (gh manages ~/.config/gh).
write_token_file() {
  local file="$1" token="$2" dir tmp=""

  dir="$(dirname "$file")"
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
    chmod 700 "$dir"
  fi

  tmp="$(mktemp "$dir/.token.XXXXXX")"
  trap 'rm -f "$tmp"' RETURN

  printf '%s\n' "$token" > "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$file"
  trap - RETURN
}

# delete_token_file <file> — remove <file> when present.
delete_token_file() {
  local file="$1"

  [[ -e "$file" ]] || return 0
  rm -f "$file"
}
