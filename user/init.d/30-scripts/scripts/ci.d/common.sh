#!/usr/bin/env bash
# Shared ci-test logging, parsing, and failure digest helpers.

set -u

CI_TEST_FAILED_CHECKS=()
CI_TEST_FAILURE_LINES=()
CI_TEST_TMP_DIR="${TMPDIR:-/tmp}/ci-test.$$.${RANDOM}"
mkdir -p "$CI_TEST_TMP_DIR"

ci_test_cleanup() {
  rm -rf "$CI_TEST_TMP_DIR"
}

ci_test_banner() {
  printf '\n== %s: %s ==\n' "$1" "$2"
}

ci_test_skip() {
  local step="$1" item
  IFS=',' read -r -a _ci_test_skips <<< "${CI_TEST_SKIP:-}"
  for item in "${_ci_test_skips[@]}"; do
    [[ "$item" == "$step" ]] && return 0
  done
  return 1
}

ci_test_record_failure() {
  local check="$1" log_file="$2" first_line
  first_line="$(awk 'NF { print; count++; if (count == 15) exit }' "$log_file" \
    | tr '\n' ' ' | cut -c1-1000)"
  CI_TEST_FAILED_CHECKS+=("$check")
  CI_TEST_FAILURE_LINES+=("${first_line:-no output}")
}

ci_test_run() {
  local check="$1"
  shift
  local log_file="$CI_TEST_TMP_DIR/${#CI_TEST_FAILED_CHECKS[@]}-${check//[^[:alnum:]_.-]/_}.log"

  printf '\n-- %s --\n' "$check"
  if "$@" > >(tee "$log_file") 2>&1; then
    printf 'PASS %s\n' "$check"
    return 0
  else
    local status=$?
    printf 'FAIL %s (exit %s)\n' "$check" "$status" >&2
    ci_test_record_failure "$check" "$log_file"
    return "$status"
  fi
}

ci_test_digest() {
  local i
  printf '\n## CI-TEST DIGEST ##\n'
  if (( ${#CI_TEST_FAILED_CHECKS[@]} == 0 )); then
    printf 'PASS all checks\n'
    return 0
  fi
  for i in "${!CI_TEST_FAILED_CHECKS[@]}"; do
    printf 'FAIL %s: %s\n' "${CI_TEST_FAILED_CHECKS[$i]}" "${CI_TEST_FAILURE_LINES[$i]}"
  done
}
