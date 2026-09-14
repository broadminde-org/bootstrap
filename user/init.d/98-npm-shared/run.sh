#!/usr/bin/env bash
set -euo pipefail

# 98-npm-shared - configure user-level GitHub Packages npm auth.

# shellcheck source=../lib/common.sh
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
readonly REPO_ROOT
readonly NPMRC="$HOME/.npmrc"
readonly REGISTRY_KEY='@broadminde-org:registry='
readonly AUTH_KEY='//npm.pkg.github.com/:_authToken='

# Deploy the frontend-shared agent skill before token handling. The skill is
# useful for diagnosing either the source-repository or npm-package path, and
# sync_dir_preserve never deletes user-installed skills.
sync_dir_preserve "$SCRIPT_DIR/kilo/skills" "$HOME/.kilo/skills"

if [[ -f "$REPO_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  . "$REPO_ROOT/.env"
fi

if [[ -z "${GITHUB_PACKAGES_TOKEN:-}" ]]; then
  echo "GitHub Packages npm auth skipped: GITHUB_PACKAGES_TOKEN is not configured."
  echo "Create a classic PAT at https://github.com/settings/tokens/new"
  echo "with only the read:packages scope, then add it to:"
  echo "  $REPO_ROOT/.env"
  echo "as GITHUB_PACKAGES_TOKEN=ghp_... and re-run user/init.sh 98."
  exit 0
fi

if ! command -v npm >/dev/null 2>&1 && [[ -s "$HOME/.nvm/nvm.sh" ]]; then
  # Non-interactive shells do not source ~/.bashrc, where nvm is normally loaded.
  # --no-use avoids selecting a version before the default alias is available.
  # shellcheck disable=SC1091
  . "$HOME/.nvm/nvm.sh" --no-use
  nvm use default >/dev/null
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "ERROR: npm is required; run the 35-node step first." >&2
  exit 1
fi

tmp="$(mktemp "$HOME/.npmrc.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

if [[ -f "$NPMRC" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "$REGISTRY_KEY"*|"$AUTH_KEY"*) continue ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < "$NPMRC" > "$tmp"
fi

printf '%s\n' \
  '@broadminde-org:registry=https://npm.pkg.github.com' \
  "//npm.pkg.github.com/:_authToken=$GITHUB_PACKAGES_TOKEN" \
  >> "$tmp"
chmod 600 "$tmp"

if [[ -f "$NPMRC" ]] && cmp -s "$tmp" "$NPMRC" && [[ "$(stat -c %a "$NPMRC")" == 600 ]]; then
  rm -f "$tmp"
  trap - EXIT
else
  mv -f "$tmp" "$NPMRC"
fi

npm_bin_dir="$(dirname "$(command -v npm)")"
npm view @broadminde-org/frontend version || {
  echo "PAT lacks the read:packages scope, or the package is not published - fix ~/bootstrap/.env and re-run" >&2
  exit 1
}

env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/local/bin:$npm_bin_dir" \
  npm view @broadminde-org/frontend version || {
  echo "PAT lacks the read:packages scope, or the package is not published - fix ~/bootstrap/.env and re-run" >&2
  exit 1
}

if [[ "$(grep -cF '//npm.pkg.github.com/:_authToken=' "$NPMRC")" != 1 ]] || \
  [[ "$(stat -c %a "$NPMRC")" != 600 ]]; then
  echo "ERROR: ~/.npmrc verification failed." >&2
  exit 1
fi

echo "npm auth for @broadminde-org/* configured in ~/.npmrc and verified."
