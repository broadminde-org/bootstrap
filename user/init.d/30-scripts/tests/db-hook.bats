#!/usr/bin/env bats
# DB-hook contract tests: env sourcing + teardown (stub hook, no postgres —
# the contract under test is .ci/db.env handling, not postgres itself).

setup() {
  load test_helper
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    skip "docker unavailable"
  fi
}

@test "hook stub: .ci/db.env created, TEST_DB_URL visible in go test env" {
  local repo
  repo="$(mk_db_hook_repo)"
  run_ci_test "$repo"
  [ "$status" -eq 0 ]
  [ -f "$repo/.ci/db.env" ]
  grep -q '^TEST_DB_URL=' "$repo/.ci/db.env"
  # the fixture's TestDBEnv fails if TEST_DB_URL is unset; a green go-test
  # proves .ci/db.env was sourced into subsequent checks.
  [[ "$output" == *"PASS go-test"* ]]
}

@test "hook with container: ci-test teardown removes it, no leaks" {
  local repo container
  repo="$(mk_db_hook_repo)"
  container="ci-test-fixture-$BATS_TEST_NUMBER-$$"
  docker image inspect alpine:3 >/dev/null 2>&1 || \
    docker pull alpine:3 >/dev/null 2>&1 || \
    skip "cannot pull alpine:3 (offline?)"
  # extend the stub hook to also start a throwaway container and record its
  # name for ci_test_teardown_db via TEST_DB_CONTAINER.
  cat > "$repo/scripts/test-db-setup" <<EOF
#!/usr/bin/env bash
set -euo pipefail
mkdir -p .ci
{
  printf 'TEST_DB_URL=postgres://fixture:5432/db\n'
  printf 'TEST_DB_CONTAINER=%s\n' "$container"
} > .ci/db.env
docker run -d --name "$container" alpine:3 sleep 60 >/dev/null
EOF
  chmod +x "$repo/scripts/test-db-setup"
  run_ci_test "$repo"
  [ "$status" -eq 0 ]
  run docker ps -a --format '{{.Names}}'
  [ "$status" -eq 0 ]
  if grep -qx "$container" <<< "$output"; then
    printf 'leaked container: %s\n' "$container" >&2
    return 1
  fi
}
