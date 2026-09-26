# Shared fixture builders for the ci-test contract tests.
# Each builder creates a fixture repo inside $BATS_TEST_TMPDIR and echoes its
# path; callers do: repo="$(mk_go_repo PASS)".

_CI_TEST_SCRIPT="$BATS_TEST_DIRNAME/../scripts/ci-test"

# run_ci_test <dir> [args...] — run ci-test from the source tree inside <dir>.
run_ci_test() {
  local dir="$1"
  shift
  # shellcheck disable=SC2016  # runs in the child shell, not here
  run env TMPDIR="$BATS_TEST_TMPDIR" bash -c \
    'cd "$1" && shift && exec "$@"' _ "$dir" "$_CI_TEST_SCRIPT" "$@"
}

# mk_go_repo PASS|FAIL [extra file content marker]
mk_go_repo() {
  local mode="$1"
  local dir
  dir="$(mktemp -d "$BATS_TEST_TMPDIR/go-repo.XXXXXX")"
  cat > "$dir/go.mod" <<'EOF'
module fixture.local/go-repo

go 1.22
EOF
  cat > "$dir/main.go" <<'EOF'
package main

func main() {}
EOF
  if [[ "$mode" == PASS ]]; then
    cat > "$dir/main_test.go" <<'EOF'
package main

import "testing"

func TestOK(t *testing.T) {}
EOF
  else
    cat > "$dir/main_test.go" <<'EOF'
package main

import "testing"

func TestBroken(t *testing.T) { t.Fatal("intentional fixture failure") }
EOF
  fi
  printf '%s\n' "$dir"
}

# mk_node_repo — package.json with no scripts and no svelte config, so all
# npm run <x> --if-present checks are trivial passes.
mk_node_repo() {
  local dir
  dir="$(mktemp -d "$BATS_TEST_TMPDIR/node-repo.XXXXXX")"
  cat > "$dir/package.json" <<'EOF'
{
  "name": "fixture-node-repo",
  "private": true,
  "version": "0.0.0"
}
EOF
  printf '%s\n' "$dir"
}

# mk_python_repo — minimal pyproject; callers should skip ruff/pytest via
# CI_TEST_SKIP unless those checks are under test.
mk_python_repo() {
  local dir
  dir="$(mktemp -d "$BATS_TEST_TMPDIR/python-repo.XXXXXX")"
  cat > "$dir/pyproject.toml" <<'EOF'
[project]
name = "fixture-python-repo"
version = "0.0.0"
EOF
  # uv lock --check requires a committed lockfile; with zero dependencies
  # this resolves offline.
  (cd "$dir" && uv lock --quiet)
  printf '%s\n' "$dir"
}

# mk_db_hook_repo — go repo + executable scripts/test-db-setup that records
# the db.env values the go test sees, for env-sourcing assertions.
mk_db_hook_repo() {
  local dir
  dir="$(mk_go_repo PASS)"
  mkdir -p "$dir/scripts"
  cat > "$dir/scripts/test-db-setup" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p .ci
printf 'TEST_DB_URL=postgres://fixture:5432/db\n' > .ci/db.env
EOF
  chmod +x "$dir/scripts/test-db-setup"
  cat > "$dir/main_test.go" <<'EOF'
package main

import (
	"os"
	"testing"
)

func TestDBEnv(t *testing.T) {
	if os.Getenv("TEST_DB_URL") == "" {
		t.Fatal("TEST_DB_URL not visible in go test env")
	}
}
EOF
  printf '%s\n' "$dir"
}
