#!/usr/bin/env bash
set -euo pipefail

# 05-packages (macOS) — Install the host package set via Homebrew.
#
# Reads packages.macos.txt (formulas) and packages.macos-casks.txt (casks),
# one package per line, `#` for comments, blank lines ignored. brew install
# is a no-op when a package is already installed, so this is safe to re-run.
#
# The GitHub CLI is folded in here (gh formula) — there is no separate
# 59-gh-cli/run.macos.sh; that step stays Linux-only.
#
# Build tooling: the macOS equivalent of build-essential is the Xcode
# Command Line Tools (`xcode-select --install`); brew prompts for them
# if they are missing.
#
# brew refuses to run as root — when invoked via sudo, the package list
# is applied as the invoking user (SUDO_USER), who must be an admin.

# Locate brew (Apple Silicon: /opt/homebrew, Intel: /usr/local).
if [[ -x /opt/homebrew/bin/brew ]]; then
  BREW=/opt/homebrew/bin/brew
elif [[ -x /usr/local/bin/brew ]]; then
  BREW=/usr/local/bin/brew
else
  echo "ERROR: Homebrew not found. Install it from https://brew.sh first." >&2
  exit 1
fi

# brew must not run as root — hand off to the invoking user.
if [[ $EUID -eq 0 ]]; then
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    exec sudo -u "$SUDO_USER" \
      env "HOME=$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory | awk '{print $2}')" \
      "$0"
  fi
  echo "ERROR: brew cannot run as root and no non-root SUDO_USER is set." >&2
  exit 1
fi

STEP_DIR="$(cd "$(dirname "$0")" && pwd)"

read_list() {
  grep -vE '^\s*(#|$)' "$1" || true
}

formulas_file="$STEP_DIR/packages.macos.txt"
casks_file="$STEP_DIR/packages.macos-casks.txt"

formulas="$(read_list "$formulas_file")"
if [[ -n "$formulas" ]]; then
  echo "==> Installing brew formulas from packages.macos.txt..."
  printf '%s\n' "$formulas" | xargs "$BREW" install
fi

casks="$(read_list "$casks_file")"
if [[ -n "$casks" ]]; then
  echo "==> Installing brew casks from packages.macos-casks.txt..."
  printf '%s\n' "$casks" | xargs "$BREW" install --cask
fi

echo "==> Done."
