#!/usr/bin/env bash

ci_test_run_node() {
  ci_test_banner node "check · lint · test · build"
  local failed=0

  if [[ -f svelte.config.js || -f svelte.config.ts || -f svelte.config.mjs ]]; then
    if ! ci_test_skip svelte-check && ! ci_test_run svelte-check npx svelte-check; then failed=1; fi
  fi
  if ! ci_test_skip eslint && ! ci_test_run eslint npm run lint --if-present; then failed=1; fi
  if ! ci_test_skip vitest && ! ci_test_run vitest npm run test --if-present; then failed=1; fi
  if ! ci_test_skip build && ! ci_test_run build npm run build --if-present; then failed=1; fi

  return "$failed"
}
