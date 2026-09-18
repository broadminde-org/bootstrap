#!/usr/bin/env bash

ci_test_run_go() {
  ci_test_banner go "test · lint · gosec · vulncheck"
  local failed=0

  if ! ci_test_skip test && ! ci_test_run go-test go test ./...; then failed=1; fi
  if ! ci_test_skip lint && ! ci_test_run golangci-lint golangci-lint run ./...; then failed=1; fi

  # gosec / govulncheck are optional dev tools (user/init.d/25-go) —
  # absent means SKIP, not FAIL.
  if ci_test_skip gosec; then
    :
  elif command -v gosec >/dev/null 2>&1; then
    if ! ci_test_run gosec gosec ./...; then failed=1; fi
  else
    printf 'SKIP gosec (not installed)\n'
  fi

  if ci_test_skip vulncheck; then
    :
  elif command -v govulncheck >/dev/null 2>&1; then
    if ! ci_test_run govulncheck govulncheck ./...; then failed=1; fi
  else
    printf 'SKIP govulncheck (not installed)\n'
  fi

  return "$failed"
}
