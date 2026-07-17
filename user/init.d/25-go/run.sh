#!/usr/bin/env bash
# 25-go — Go toolchain (binary + dev tools + environment)
#
# User tier: runs as the deploy user (non-root).
# Installs the Go binary in ~/.local/go/ (pinned via EE_GO_VERSION), writes
# the Go shell environment block to ~/.profile, installs dev tools
# (golangci-lint, gosec, govulncheck, air) to ~/go/bin/, persists go env
# settings to ~/.config/go/env, and prunes orphan go toolchain binaries.
#
# Idempotent: skips Go binary install if version matches; skips tool installs
# if binaries already exist; shell env block is marker-guarded and self-healing.

set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

# Resolve the Go version pin to a full major.minor.patch version.
#
#   "latest"  → newest stable from go.dev/dl
#   "1.26"    → newest 1.26.x from go.dev/dl
#   "1"       → newest 1.x.y (equivalent to "latest")
#   "1.26.5"  → returned unchanged (no API call)
#
# go.dev/dl?mode=json returns the current stable release(s) for each
# supported Go series (typically the last 2-3 minor versions). For partial
# pins against older series not in this list the download step will fail
# with a clear error; use an exact version pin for those cases.
resolve_go_version() {
  local pin="$1"

  # Fully-specified pin — no API call needed.
  if [[ "$pin" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$pin"
    return
  fi

  local releases
  releases="$(curl -fsSL "https://go.dev/dl/?mode=json" 2>/dev/null)"
  if [[ -z "$releases" ]]; then
    echo "$pin"
    return
  fi

  # All version numbers from the response, newest first (strip "go" prefix).
  # Use `go[0-9]` not `go[0-9.]*` to avoid matching bare "go" words in the
  # JSON that grep -o would otherwise also emit as zero-length matches.
  local all_versions
  all_versions="$(printf '%s' "$releases" \
    | grep -o '"version": *"go[^"]*"' \
    | grep -oE 'go[0-9][0-9.]*' \
    | sed 's/^go//')"

  if [[ "$pin" == "latest" ]]; then
    echo "$all_versions" | head -1
    return
  fi

  # Partial pin: anchor with a trailing dot so "1.2" does not match "1.20".
  local escaped="${pin//./\\.}"
  local ver
  ver="$(printf '%s' "$all_versions" | grep "^${escaped}\." | head -1)"
  # If there is no match let the download step fail with a clear error.
  echo "${ver:-$pin}"
}

_original_go_version="$EE_GO_VERSION"
if [[ ! "$EE_GO_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  EE_GO_VERSION="$(resolve_go_version "$EE_GO_VERSION")"
  echo "Resolved go ${_original_go_version} -> ${EE_GO_VERSION}"
fi

GO_VERSION="$EE_GO_VERSION"
GO_TOOLCHAIN_PIN="go${EE_GO_VERSION}"

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  GOARCH="amd64" ;;
  aarch64) GOARCH="arm64" ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Path to the freshly-installed Go binary. install_go() always ends up with
# this file on disk, so it is safe to reference from any later step.
GO_BIN="${HOME}/.local/go/bin/go"

# ---------------------------------------------------------------------------
# Go binary
# ---------------------------------------------------------------------------

install_go() {
  echo "--- Installing Go ${GO_VERSION} (${GOARCH})"

  if command_exists go; then
    CURRENT_GO=$(go version | awk '{print $3}' | sed 's/go//')
    if [ "$CURRENT_GO" = "$GO_VERSION" ]; then
      echo "Go ${GO_VERSION} already installed. Skipping."
      write_go_shell_env
      return 0
    fi
    echo "Upgrading Go from ${CURRENT_GO} to ${GO_VERSION}..."
  fi

  TARBALL="go${GO_VERSION}.linux-${GOARCH}.tar.gz"
  URL="https://go.dev/dl/${TARBALL}"

  mkdir -p "$HOME/.cache"
  echo "Downloading ${URL}..."
  curl -fsSL -o "${HOME}/.cache/${TARBALL}" "$URL"

  GO_INSTALL_DIR="${HOME}/.local/go"
  echo "Installing to ${GO_INSTALL_DIR}..."
  rm -rf "$GO_INSTALL_DIR"
  mkdir -p "$(dirname "$GO_INSTALL_DIR")"
  tar -C "$(dirname "$GO_INSTALL_DIR")" -xzf "${HOME}/.cache/${TARBALL}"
  rm -f "${HOME}/.cache/${TARBALL}"

  write_go_shell_env

  echo "Go ${GO_VERSION} installed."
}

# write_go_shell_env writes the canonical Go environment block to ~/.profile.
# It is self-healing: any prior marker-bounded block is removed, then stray
# bare exports left by older versions are stripped, then a single fresh block
# is appended. Only .profile is targeted (bootstrap does not use .bash_profile
# for Go env, and .bashrc is never written — bootstrap has no env.sh).
write_go_shell_env() {
  echo "--- Writing Go shell environment for $(whoami)"

  # Build the marker block. $HOME / $PATH are intentionally literal — they
  # must only expand when .profile is sourced by the user's shell.
  # shellcheck disable=SC2016
  local go_block='# --- Go environment (managed by user/init.d/25-go/run.sh) ---
export GOROOT="$HOME/.local/go"
export GOPATH="$HOME/go"
export GOPROXY="https://proxy.golang.org,direct"
export GOSUMDB="sum.golang.org"
export GOPRIVATE="github.com/broadminde-org/*"
# Strip any prior Go paths from PATH to keep this block idempotent
case ":$PATH:" in
  *":$HOME/.local/go/bin:"*) ;;
  *) PATH="$HOME/.local/go/bin:$PATH" ;;
esac
case ":$PATH:" in
  *":$HOME/go/bin:"*) ;;
  *) PATH="$HOME/go/bin:$PATH" ;;
esac
export PATH
# --- End Go environment ---'

  # Ensure .profile exists
  [ -f "$HOME/.profile" ] || : > "$HOME/.profile"

  # 1. Delete any prior marker-bounded block
  sed -i '/^# --- Go environment ---$/,/^# --- End Go environment ---$/d' "$HOME/.profile"
  sed -i '\|^# --- Go environment (managed by |,\|^# --- End Go environment ---$|d' "$HOME/.profile"

  # 2. Delete stray bare exports left by older script versions
  sed -i '\|^# --- Go environment (managed by |,\|^# --- End Go environment ---$|!{/^export \(GOPRIVATE\|GOPROXY\|GOSUMDB\)=/d;}' "$HOME/.profile"

  # 3. Normalize trailing newlines
  if [ -s "$HOME/.profile" ] && command -v perl >/dev/null 2>&1; then
    perl -i -pe 'BEGIN{$/=undef} s/\n+\z/\n/' "$HOME/.profile"
  fi

  # 4. Ensure the file ends with a newline
  if [ -s "$HOME/.profile" ] && [ "$(tail -c1 "$HOME/.profile" 2>/dev/null | wc -l | tr -d ' ')" = "0" ]; then
    printf '\n' >> "$HOME/.profile"
  fi

  # 5. Append the fresh marker block
  printf '\n%s\n' "$go_block" >> "$HOME/.profile"
  echo "Wrote Go environment block to $HOME/.profile"
}

# ---------------------------------------------------------------------------
# Go dev tools (linters, scanners)
# ---------------------------------------------------------------------------

install_go_tools() {
  echo "--- Installing Go dev tools"

  mkdir -p "$HOME/go" "$HOME/go/bin" "$HOME/go/pkg/mod" "$HOME/.cache"

  # Go install as the current user with explicit env
  go_install_as_user() {
    local pkg="$1"
    env \
      "HOME=$HOME" \
      "XDG_CACHE_HOME=$HOME/.cache" \
      "GOROOT=$HOME/.local/go" \
      "GOPATH=$HOME/go" \
      "GOTOOLCHAIN=${GO_TOOLCHAIN_PIN}+auto" \
      "GOPROXY=https://proxy.golang.org,direct" \
      "GOSUMDB=sum.golang.org" \
      "PATH=${HOME}/.local/go/bin:${HOME}/go/bin:$PATH" \
      "${GO_BIN}" install "$pkg"
  }

  # golangci-lint
  echo "Installing golangci-lint..."
  go_install_as_user github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest

  # gosec
  echo "Installing gosec..."
  go_install_as_user github.com/securego/gosec/v2/cmd/gosec@latest

  # govulncheck
  echo "Installing govulncheck..."
  go_install_as_user golang.org/x/vuln/cmd/govulncheck@latest

  # air (hot reload for Go)
  echo "Installing air..."
  go_install_as_user github.com/air-verse/air@latest

  echo "Go dev tools installed to $HOME/go/bin/"
}

# Remove orphan go1.X.Y toolchain binaries left by prior installs of older
# Go versions. Only matches the standalone toolchain shape (e.g. go1.26.1);
# user-installed tools (golangci-lint, gosec, air, ...) are untouched.
prune_orphan_gotoolchains() {
  echo "--- Pruning orphan go toolchain binaries in $HOME/go/bin/"
  local old
  while IFS= read -r -d '' old; do
    echo "Removing orphan toolchain: $old"
    rm -f -- "$old"
  done < <(find "$HOME/go/bin" \
            -maxdepth 1 -type f -name 'go1.*' \
            ! -name "go${GO_VERSION}" -print0)
}

# Persist GOPROXY / GOSUMDB / GOPRIVATE / GOTOOLCHAIN via `go env -w` so
# non-interactive shells (CI, scripts, MCP-launched dev stack) inherit them
# from ~/.config/go/env.
persist_go_env() {
  echo "--- Persisting go env"
  mkdir -p "$HOME/.config/go"

  # Remove any stale GOROOT written by Go's toolchain auto-management.
  local go_env_file="$HOME/.config/go/env"
  if [ -f "$go_env_file" ]; then
    sed -i '/^GOROOT=/d' "$go_env_file"
  fi

  env \
    "HOME=$HOME" \
    "PATH=${HOME}/.local/go/bin:${HOME}/go/bin:/usr/bin:/bin" \
    "${GO_BIN}" env -w \
    GOPROXY="https://proxy.golang.org,direct" \
    GOSUMDB="sum.golang.org" \
    GOPRIVATE="github.com/broadminde-org/*" \
    "GOTOOLCHAIN=${GO_TOOLCHAIN_PIN}+auto"
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

install_go
install_go_tools
prune_orphan_gotoolchains
persist_go_env

echo "--- Go summary"
if command_exists "$GO_BIN"; then
  echo "Go:            $($GO_BIN version)"
  echo "go env:"
  "$GO_BIN" env GOPROXY GOSUMDB GOPRIVATE | sed 's/^/  /'
fi
[ -x "$HOME/go/bin/golangci-lint" ] && echo "golangci-lint: $($HOME/go/bin/golangci-lint version --short 2>/dev/null || echo 'installed')"
[ -x "$HOME/go/bin/gosec" ]         && echo "gosec:         installed"
[ -x "$HOME/go/bin/govulncheck" ]   && echo "govulncheck:   installed"
[ -x "$HOME/go/bin/air" ]           && echo "air:           installed"
if [ -n "${GOSUMDB:-}" ] && [ "${GOSUMDB}" = "sum.golang.org" ]; then
  echo "GOSUMDB active in shell: yes"
else
  echo "GOSUMDB active in shell: no"
fi
echo ""
