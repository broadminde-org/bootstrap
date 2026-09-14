#!/usr/bin/env bash
# Report common build artifacts in the current Git repository.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

repo_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  log_skip "current directory is not inside a Git repository"
  exit 0
fi

log_info "Repository: $repo_root"
found=0
while IFS= read -r artifact; do
  found=1
  log_info "  ${artifact#"$repo_root"/}: $(human_size "$artifact")"
done < <(find "$repo_root" -mindepth 1 -maxdepth 3 -type d \( -name node_modules -o -name .svelte-kit -o -name dist \) -prune -print 2>/dev/null | sort)

if [[ "$found" -eq 0 ]]; then
  log_info "  no common Node/build artifacts found"
fi
