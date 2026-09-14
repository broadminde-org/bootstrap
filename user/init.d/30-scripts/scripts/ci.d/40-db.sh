#!/usr/bin/env bash

ci_test_db_container=""

ci_test_prepare_db() {
  local hook="$PWD/scripts/test-db-setup"
  [[ -x "$hook" ]] || return 0
  command -v docker >/dev/null 2>&1 || {
    printf 'FAIL db: scripts/test-db-setup exists but docker is unavailable\n' >&2
    return 1
  }

  mkdir -p .ci
  if ! "$hook"; then
    printf 'FAIL db: scripts/test-db-setup\n' >&2
    return 1
  fi
  [[ -f .ci/db.env ]] || {
    printf 'FAIL db: setup hook did not create .ci/db.env\n' >&2
    return 1
  }
  set -a
  # shellcheck disable=SC1091
  source .ci/db.env
  set +a
  ci_test_db_container="${CI_TEST_DB_CONTAINER:-${TEST_DB_CONTAINER:-}}"
  return 0
}

ci_test_teardown_db() {
  if [[ -n "$ci_test_db_container" ]] && command -v docker >/dev/null 2>&1; then
    docker rm -f "$ci_test_db_container" >/dev/null 2>&1 || true
  fi
}
