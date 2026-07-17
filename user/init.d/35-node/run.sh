#!/usr/bin/env bash
# 35-node — Node.js via nvm + global npm packages
#
# User tier: runs as the deploy user (non-root).
# Installs nvm, then Node.js (pinned via EE_NODE_VERSION), adds nvm sourcing
# to ~/.bashrc, and installs global npm packages from packages.txt.
#
# Idempotent: skips nvm install if nvm.sh exists; skips node install if
# version matches; skips npm packages if already installed.

set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

# Resolve the node version pin to a full major.minor.patch version.
#
#   "latest"  → newest stable even-major (LTS) from nodejs.org
#   "24"      → newest 24.x.y
#   "24.18"   → newest 24.18.y
#   "24.18.0" → returned unchanged (no API call)
#
# The nodejs.org dist index is sorted newest-first, so the first match
# for any prefix is always the latest release in that series.
resolve_node_version() {
  local pin="$1"

  # Fully-specified pin — no API call needed.
  if [[ "$pin" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$pin"
    return
  fi

  local index
  index="$(curl -fsSL "https://nodejs.org/dist/index.json" 2>/dev/null)"
  if [[ -z "$index" ]]; then
    echo "$pin"
    return
  fi

  # All version numbers, newest first (strip leading "v").
  # Use `v[0-9]` not `v[0-9.]*` to avoid matching the bare `v` in
  # the literal word "version" which grep -o would also emit.
  local all_versions
  all_versions="$(printf '%s' "$index" \
    | grep -o '"version":"v[^"]*"' \
    | grep -oE 'v[0-9][0-9.]*' \
    | sed 's/^v//')"

  if [[ "$pin" == "latest" ]]; then
    # First even-major entry is the latest LTS.
    local ver major
    while IFS= read -r ver; do
      major="${ver%%.*}"
      if (( major % 2 == 0 )); then
        echo "$ver"
        return
      fi
    done <<< "$all_versions"
    echo "24.0.0"
    return
  fi

  # Partial pin: anchor with a trailing dot so "24" does not match "240".
  local escaped="${pin//./\\.}"
  local ver
  ver="$(printf '%s' "$all_versions" | grep "^${escaped}\." | head -1)"
  # If there is no match let nvm handle the error with the original value.
  echo "${ver:-$pin}"
}

_original_node_version="$EE_NODE_VERSION"
if [[ ! "$EE_NODE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  EE_NODE_VERSION="$(resolve_node_version "$EE_NODE_VERSION")"
  echo "Resolved node ${_original_node_version} -> ${EE_NODE_VERSION}"
fi

NVM_DIR="$HOME/.nvm"

# ---------------------------------------------------------------------------
# nvm + Node.js
# ---------------------------------------------------------------------------

install_node() {
  # EE_NODE_VERSION (from bootstrap.conf.yml versions:, exported by common.sh) is the sole source of truth
  # for the Node.js pin. No .nvmrc lookup — that file belongs to individual
  # app repos, not to the bootstrap step.
  echo "--- Installing Node.js v${EE_NODE_VERSION} via nvm"

  # Install nvm — download nvm.sh, nvm-exec, and bash_completion directly
  # (avoids install.sh's git auto-detection and SSH config issues)
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    echo "Installing nvm..."
    mkdir -p "$NVM_DIR"
    curl -fLo "$NVM_DIR/nvm.sh" https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/nvm.sh
    curl -fLo "$NVM_DIR/nvm-exec" https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/nvm-exec
    curl -fLo "$NVM_DIR/bash_completion" https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/bash_completion
    chmod a+x "$NVM_DIR/nvm-exec"
  fi

  source "$NVM_DIR/nvm.sh" --no-use

  # Add nvm sourcing to .bashrc for interactive shells
  if ! grep -qF 'NVM_DIR' "$HOME/.bashrc" 2>/dev/null; then
    printf '\n%s\n%s\n%s\n' \
      'export NVM_DIR="$HOME/.nvm"' \
      '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm' \
      '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion' \
      >> "$HOME/.bashrc"
  fi

  # Resolve the exact pinned version
  RESOLVED_VERSION="$(nvm version "v${EE_NODE_VERSION}" 2>/dev/null || echo "N/A")"
  if [[ "$RESOLVED_VERSION" == "v${EE_NODE_VERSION}" ]]; then
    echo "Node.js ${EE_NODE_VERSION} already installed via nvm."
  else
    if [[ "$RESOLVED_VERSION" != "N/A" ]]; then
      echo "Node.js ${RESOLVED_VERSION} installed via nvm, but pin requires ${EE_NODE_VERSION}; reinstalling."
    else
      echo "Installing Node.js ${EE_NODE_VERSION} via nvm..."
    fi
    nvm install "${EE_NODE_VERSION}"
  fi

  # Final guard: verify the active version matches the pin exactly
  nvm use "$EE_NODE_VERSION"
  INSTALLED_VERSION="$(node --version | sed 's/^v//')"
  if [[ "$INSTALLED_VERSION" != "$EE_NODE_VERSION" ]]; then
    echo "ERROR: requested Node.js ${EE_NODE_VERSION} but installed ${INSTALLED_VERSION}" >&2
    exit 1
  fi

  nvm alias default "$EE_NODE_VERSION"

  echo "Node.js v$(node --version) installed."
  echo "npm $(npm --version) / npx $(npx --version)"
}

# ---------------------------------------------------------------------------
# Global npm packages (required by scripts)
# ---------------------------------------------------------------------------

install_packages() {
  local packages_file
  packages_file="$(cd "$(dirname "$0")" && pwd)/packages.txt"

  echo "--- Installing global npm packages"

  source "$NVM_DIR/nvm.sh" >/dev/null 2>&1
  nvm use "$EE_NODE_VERSION" >/dev/null 2>&1

  local has_playwright=false
  npm_list=$(npm list -g --depth=0 2>/dev/null || true)

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    pkg_spec="$line"
    # Strip trailing version (@version) to get the bare package name.
    # For scoped packages like @playwright/test (no trailing @version), the
    # name is the full spec — ${pkg%@*} would strip from the leading @ yielding
    # empty. Only strip if there is a non-leading @ (i.e. a version suffix).
    if [[ "$pkg_spec" =~ ^(@[^@/]+/[^@]+|[^@]+)@.+ ]]; then
      pkg_name="${pkg_spec%@*}"
    else
      pkg_name="$pkg_spec"
    fi

    if [ "$pkg_name" = "@playwright/test" ]; then
      has_playwright=true
    fi

    if echo "$npm_list" | grep -q " ${pkg_name}@"; then
      echo "${pkg_name} already installed globally"
      continue
    fi

    echo "Installing ${pkg_spec}..."
    npm install -g "$pkg_spec"
  done < "$packages_file"

  if [ "$has_playwright" = true ]; then
    echo "--- Installing Playwright browsers"
    npx playwright install --with-deps chromium firefox webkit
    echo "Playwright browsers installed."
  fi
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

install_node
install_packages

echo "--- Node.js summary"
source "$NVM_DIR/nvm.sh" >/dev/null 2>&1
echo "Node.js: $(node --version)  (npx $(npx --version))"
echo ""
