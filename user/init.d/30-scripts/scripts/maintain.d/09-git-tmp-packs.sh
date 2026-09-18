#!/usr/bin/env bash
# Remove orphaned temporary pack files left by git-filter-repo.
# These are safe to delete — they are temp files from a completed
# history rewrite and are not referenced by any ref.
# @tier 1
# @sudo false
# @summary Remove orphaned git tmp_pack files
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

# ee-layout step: never run against the EE_ROOT=$HOME fallback.
require_ee_layout

PACK_DIR="$EE_ROOT/.git/objects/pack"

if [[ ! -d "$PACK_DIR" ]]; then
  log_skip ".git/objects/pack not found"
  exit 0
fi

removed=0
# -mmin +60: a temp pack younger than an hour may belong to an
# in-flight fetch/filter-repo — leave it alone.
while IFS= read -r -d '' tmp_pack; do
  size="$(human_size "$tmp_pack")"
  log_info "removing orphaned pack: $(basename "$tmp_pack") ($size)"
  run_cmd rm -f "$tmp_pack"
  (( removed++ )) || true
done < <(find "$PACK_DIR" -maxdepth 1 -type f -name 'tmp_pack_*' -mmin +60 -print0 2>/dev/null)

if [[ $removed -eq 0 ]]; then
  log_info "no orphaned tmp pack files found"
else
  log_ok "removed $removed orphaned pack file(s)"
fi
