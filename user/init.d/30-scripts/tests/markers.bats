#!/usr/bin/env bats
# Marker-format contract tests: exact greps against a failing run's log.

setup() {
  load test_helper
  repo="$(mk_go_repo FAIL)"
  cp "$(mk_node_repo)/package.json" "$repo/package.json"
  CI_TEST_SKIP=ruff,pytest run_ci_test "$repo"
  [ "$status" -ne 0 ]
  log="$BATS_TEST_TMPDIR/run.log"
  printf '%s\n' "$output" > "$log"
}

@test "digest header '^## CI-TEST DIGEST ##$' present exactly once" {
  [ "$(grep -c '^## CI-TEST DIGEST ##$' "$log")" -eq 1 ]
}

@test "digest header appears after all check output" {
  local digest_line last_check_line
  digest_line="$(grep -n '^## CI-TEST DIGEST ##$' "$log" | cut -d: -f1)"
  last_check_line="$(grep -nE '^(PASS|FAIL|SKIP) [a-z0-9-]+( \(exit [0-9]+\))?$' "$log" | tail -n1 | cut -d: -f1)"
  [ -n "$last_check_line" ]
  [ "$digest_line" -gt "$last_check_line" ]
}

@test "banners '^== [a-z]+: .+ ==$' present per detected family" {
  grep -qE '^== go: .+ ==$' "$log"
  grep -qE '^== node: .+ ==$' "$log"
}

@test "digest '^FAIL [a-z0-9-]+: ' line per failed check" {
  local digest_fail_count run_fail_count
  digest_fail_count="$(awk '/^## CI-TEST DIGEST ##$/{f=1} f && /^FAIL [a-z0-9-]+: /{c++} END{print c+0}' "$log")"
  # go-test is the only failing check in this fixture run
  [ "$digest_fail_count" -eq 1 ]
  run_fail_count="$(grep -cE '^FAIL [a-z0-9-]+ \(exit [0-9]+\)$' "$log")"
  [ "$digest_fail_count" -eq "$run_fail_count" ]
}

@test "digest FAIL lines are at most 1000 chars (cut -c1-1000)" {
  local over
  over="$(awk '/^## CI-TEST DIGEST ##$/{f=1} f && /^FAIL / && length($0) > 1000 {c++} END{print c+0}' "$log")"
  [ "$over" -eq 0 ]
}

@test "digest FAIL line count equals number of failed checks in the run" {
  local failed_checks digest_fails
  failed_checks="$(grep -cE '^FAIL [a-z0-9-]+ \(exit [0-9]+\)$' "$log")"
  digest_fails="$(awk '/^## CI-TEST DIGEST ##$/{f=1} f && /^FAIL [a-z0-9-]+: /{c++} END{print c+0}' "$log")"
  [ "$failed_checks" -gt 0 ]
  [ "$failed_checks" -eq "$digest_fails" ]
}
