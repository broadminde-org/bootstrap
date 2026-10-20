#!/usr/bin/env bash

ci_test_run_node() {
  cd "$CI_TEST_NODE_DIR" || return 1
  ci_test_banner node "check · lint · test · build"
  local failed=0

  if [[ "$CI_TEST_NODE_CONFIGURED" == true ]]; then
    if ci_test_node_has_script "$CI_TEST_NODE_DIR" "$CI_TEST_NODE_CHECK_SCRIPT"; then
      if ! ci_test_skip check && ! ci_test_run "$CI_TEST_NODE_CHECK_SCRIPT" npm run "$CI_TEST_NODE_CHECK_SCRIPT"; then failed=1; fi
    else
      printf 'Required Node check script "%s" is missing in %s\n' "$CI_TEST_NODE_CHECK_SCRIPT" "$CI_TEST_NODE_DIR" >&2
      printf 'Required Node check script "%s" is missing in %s\n' "$CI_TEST_NODE_CHECK_SCRIPT" "$CI_TEST_NODE_DIR" > "$CI_TEST_TMP_DIR/node-check.log"
      ci_test_record_failure node-check "$CI_TEST_TMP_DIR/node-check.log"
      failed=1
    fi
  fi

  if [[ "$CI_TEST_NODE_CONFIGURED" != true && ( -f svelte.config.js || -f svelte.config.ts || -f svelte.config.mjs ) ]]; then
    if ! ci_test_skip svelte-check && ! ci_test_run svelte-check npx svelte-check; then failed=1; fi
  fi
  if ! ci_test_skip eslint && ! ci_test_run eslint npm run lint --if-present; then failed=1; fi
  if ! ci_test_skip vitest && ! ci_test_run vitest npm run test --if-present; then failed=1; fi
  if [[ "$CI_TEST_NODE_CONFIGURED" == true ]]; then
    if ci_test_node_has_script "$CI_TEST_NODE_DIR" "$CI_TEST_NODE_BUILD_SCRIPT"; then
      if ! ci_test_skip build && ! ci_test_run "$CI_TEST_NODE_BUILD_SCRIPT" npm run "$CI_TEST_NODE_BUILD_SCRIPT"; then failed=1; fi
    else
      printf 'Required Node build script "%s" is missing in %s\n' "$CI_TEST_NODE_BUILD_SCRIPT" "$CI_TEST_NODE_DIR" >&2
      printf 'Required Node build script "%s" is missing in %s\n' "$CI_TEST_NODE_BUILD_SCRIPT" "$CI_TEST_NODE_DIR" > "$CI_TEST_TMP_DIR/node-build.log"
      ci_test_record_failure node-build "$CI_TEST_TMP_DIR/node-build.log"
      failed=1
    fi
  elif ! ci_test_skip build && ! ci_test_run build npm run build --if-present; then failed=1; fi

  return "$failed"
}
