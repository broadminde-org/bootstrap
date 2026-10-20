#!/usr/bin/env bats
# Dispatcher contract tests: stack detection, check ordering, knobs.

setup() {
  load test_helper
}

@test "empty dir prints 'nothing to test' and exits 0" {
  local dir
  dir="$(mktemp -d "$BATS_TEST_TMPDIR/empty.XXXXXX")"
  run_ci_test "$dir"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; false; }
  [[ "$output" == *"nothing to test"* ]]
}

@test "ci-test resolves modules when invoked through a symlink" {
  local bin
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  ln -s "$_CI_TEST_SCRIPT" "$bin/ci-test"
  run env TMPDIR="$BATS_TEST_TMPDIR" "$bin/ci-test" --help
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; false; }
  [[ "$output" == *"Usage: ci-test [--e2e] [--fail-fast]"* ]]
}

@test "go fixture pass: '== go:' banner, 'PASS all checks', exit 0" {
  local repo
  repo="$(mk_go_repo PASS)"
  run_ci_test "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"== go: test · lint · gosec · vulncheck =="* ]]
  [[ "$output" == *"## CI-TEST DIGEST ##"* ]]
  [[ "$output" == *"PASS all checks"* ]]
}

@test "go fixture fail: FAIL go-test, digest last, exit non-zero" {
  local repo
  repo="$(mk_go_repo FAIL)"
  run_ci_test "$repo"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL go-test (exit 1)"* ]]
  [[ "$output" == *"## CI-TEST DIGEST ##"* ]]
  [[ "$output" == *"FAIL go-test: "* ]]
  # digest must be the last thing in the output
  local last_line
  last_line="$(printf '%s\n' "$output" | awk 'NF { line=$0 } END { print line }')"
  [[ "$last_line" == FAIL\ go-test:* ]]
}

@test "multi-stack fixture: go, node, python banners in order" {
  local repo
  repo="$(mk_go_repo PASS)"
  cp "$(mk_node_repo)/package.json" "$repo/package.json"
  local pyrepo
  pyrepo="$(mk_python_repo)"
  cp "$pyrepo/pyproject.toml" "$pyrepo/uv.lock" "$repo/"
  # keep python checks offline: uv lock --check has no lockfile requirement
  # beyond consistency, and ruff/pytest are skipped here.
  CI_TEST_SKIP=ruff,pytest run_ci_test "$repo"
  [ "$status" -eq 0 ]
  local go_line node_line python_line
  go_line="$(printf '%s\n' "$output" | grep -n '^== go:' | cut -d: -f1)"
  node_line="$(printf '%s\n' "$output" | grep -n '^== node:' | cut -d: -f1)"
  python_line="$(printf '%s\n' "$output" | grep -n '^== python:' | cut -d: -f1)"
  [ -n "$go_line" ] && [ -n "$node_line" ] && [ -n "$python_line" ]
  [ "$go_line" -lt "$node_line" ]
  [ "$node_line" -lt "$python_line" ]
}

@test "CI_TEST_SKIP=gosec,vulncheck removes those checks from output" {
  local repo
  repo="$(mk_go_repo PASS)"
  CI_TEST_SKIP=gosec,vulncheck run_ci_test "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" != *"PASS gosec"* ]]
  [[ "$output" != *"SKIP gosec"* ]]
  [[ "$output" != *"PASS govulncheck"* ]]
  [[ "$output" != *"SKIP govulncheck"* ]]
}

@test "--fail-fast on failing multi-stack suppresses later family banners" {
  local repo
  repo="$(mk_go_repo FAIL)"
  cp "$(mk_node_repo)/package.json" "$repo/package.json"
  run_ci_test "$repo" --fail-fast
  [ "$status" -ne 0 ]
  [[ "$output" == *"== go:"* ]]
  [[ "$output" != *"== node:"* ]]
}

@test "configured nested Node directory runs required check and build beside root Go" {
  local repo
  repo="$(mk_go_repo PASS)"
  mk_nested_node_repo "$repo" frontend
  CI_TEST_GO_DIR=. CI_TEST_NODE_DIR=frontend CI_TEST_SKIP=lint,gosec,vulncheck run_ci_test "$repo"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; false; }
  [[ "$output" == *"== go:"* ]]
  [[ "$output" == *"PASS check"* ]]
  [[ "$output" == *"PASS build"* ]]
}

@test "configured ui Node directory is honored" {
  local repo
  repo="$(mk_node_repo)"
  mk_nested_node_repo "$repo" ui
  CI_TEST_NODE_DIR=ui run_ci_test "$repo"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; false; }
  [[ "$output" == *"PASS check"* ]]
  [[ "$output" == *"PASS build"* ]]
}

@test "missing configured Node directory fails clearly" {
  local repo
  repo="$(mk_node_repo)"
  CI_TEST_NODE_DIR=frontend run_ci_test "$repo"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Configured Node directory or package.json is missing:"*frontend* ]]
}

@test "configured Node check failure fails the family" {
  local repo
  repo="$(mk_node_repo)"
  mk_nested_node_repo "$repo" frontend false true true
  CI_TEST_NODE_DIR=frontend run_ci_test "$repo"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL check"* ]]
}

@test "configured Node build failure fails the family" {
  local repo
  repo="$(mk_node_repo)"
  mk_nested_node_repo "$repo" frontend true false true
  CI_TEST_NODE_DIR=frontend run_ci_test "$repo"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL build"* ]]
}

@test "configured E2E script runs only when --e2e is supplied" {
  local repo
  repo="$(mk_node_repo)"
  mk_nested_node_repo "$repo" frontend true true "touch e2e-ran"
  CI_TEST_NODE_DIR=frontend run_ci_test "$repo"
  [ "$status" -eq 0 ]
  [ ! -f "$repo/frontend/e2e-ran" ]
  CI_TEST_NODE_DIR=frontend run_ci_test "$repo" --e2e
  [ "$status" -eq 0 ]
  [ -f "$repo/frontend/e2e-ran" ]
  [[ "$output" == *"PASS e2e"* ]]
}

@test "configured E2E script missing under --e2e fails instead of skipping" {
  local repo
  repo="$(mk_node_repo)"
  printf '{"name":"fixture-node","scripts":{"check":"true","build":"true"}}\n' > "$repo/package.json"
  CI_TEST_NODE_DIR=. run_ci_test "$repo" --e2e
  [ "$status" -ne 0 ]
  [[ "$output" == *"Required Node E2E script \"test:e2e\" is missing in "* ]]
}
