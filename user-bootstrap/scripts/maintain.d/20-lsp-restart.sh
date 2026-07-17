#!/usr/bin/env bash
# Restart language servers ONLY. Does NOT touch windsurf-server / vscode-server / codeium —
# that would invalidate the file index and force a slow reindex on reconnect.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

# Match only LSP binaries by executable name. Anchored patterns prevent
# matching anything that merely mentions "gopls" in its argv.
LSP_PATTERNS=(
  'bin/gopls( |$)'
  'bin/typescript-language-server( |$)'
  '/tsserver( |$)'
  'bin/svelte-language-server( |$)'
  'bin/pyright( |$)'
  'bin/pyright-langserver( |$)'
  # VSCodium built-in language servers
  '/jsonServerMain( |$)'
  '/cssServerMain( |$)'
  '/htmlServerMain( |$)'
  '/markdownServerMain( |$)'
)

killed=0
for pat in "${LSP_PATTERNS[@]}"; do
  # pgrep -f -a prints "PID command" — filter and act per-pid for safety.
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    pid="${line%% *}"
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
      log_info "killing pid=$pid ($pat)"
      run_cmd kill -TERM "$pid" 2>/dev/null || true
      killed=$((killed + 1))
    fi
  done < <(pgrep -fa "$pat" 2>/dev/null || true)
done

# Grace period then SIGKILL stragglers
if [[ $killed -gt 0 && "${DRY_RUN:-0}" != "1" ]]; then
  sleep 1
  for pat in "${LSP_PATTERNS[@]}"; do
    pkill -KILL -f "$pat" 2>/dev/null || true
  done
fi

if [[ $killed -eq 0 ]]; then
  log_info "no LSP processes found"
else
  log_ok "signaled $killed LSP process(es); Windsurf will respawn on demand"
fi
