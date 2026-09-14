#!/usr/bin/env bash
# HTTPS reachability checks for common development-service endpoints.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

declare -A TARGETS=(
  ["https://codeium.com"]="Codeium API"
  ["https://windsurf-stable.codeiumdata.com"]="Windsurf binaries"
  ["https://marketplace.visualstudio.com"]="VS Code Marketplace"
  ["https://update.code.visualstudio.com"]="VS Code updates"
)

if ! require_cmd curl; then
  log_skip "curl not installed"
  exit 0
fi

for url in "${!TARGETS[@]}"; do
  status="$(curl -IsL -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || printf '000')"
  case "$status" in
    200|301|302|401)
      log_ok "[$status] ${TARGETS[$url]} ($url)"
      ;;
    *)
      log_err "[$status] ${TARGETS[$url]} ($url) - likely firewall/proxy"
      ;;
  esac
done
