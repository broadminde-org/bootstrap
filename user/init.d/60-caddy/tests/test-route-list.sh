#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../../../.." && pwd)"
route="$repo_root/user/init.d/60-caddy/stack/bin/caddy-route"
mkdir -p "$repo_root/.tmp"

docker() {
  [[ "$1 $2 $3" == 'exec caddy curl' ]] || return 1
  case "$MOCK_CASE" in
    servers) printf '%s\n' '{"apps":{"http":{"servers":{"srv0":{}}}}}' ;;
    empty) printf '%s\n' '{"apps":{}}' ;;
    down) return 7 ;;
    error) printf '%s\n' '{"error":"admin unavailable"}' ;;
    malformed) printf '%s\n' '{bad' ;;
  esac
}
export -f docker

check() {
  local scenario="$1" expected_status="$2" expected_text="$3" output status
  if output="$(MOCK_CASE="$scenario" TMPDIR="$repo_root/.tmp" STACK_DIR="$repo_root/user/init.d/60-caddy/stack" bash "$route" list 2>&1)"; then
    status=0
  else
    status=$?
  fi
  if [[ ( "$expected_status" == success && "$status" -ne 0 ) ||
        ( "$expected_status" == failure && "$status" -eq 0 ) ||
        "$output" != *"$expected_text"* ]]; then
    printf 'FAIL %s (exit %s): %s\n' "$scenario" "$status" "$output" >&2
    exit 1
  fi
  printf 'PASS %s\n' "$scenario"
}

check servers success 'srv0'
check empty success '(no servers loaded)'
check down failure 'cannot read live Caddy config'
check error failure 'invalid live Caddy config'
check malformed failure 'invalid live Caddy config'
