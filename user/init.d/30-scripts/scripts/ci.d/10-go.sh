#!/usr/bin/env bash

ci_test_run_go() {
  ci_test_banner go "test · lint · gosec · vulncheck"
  local failed=0

  if ! ci_test_skip test && ! ci_test_run go-test go test ./...; then failed=1; fi
  if ! ci_test_skip lint && ! ci_test_run golangci-lint golangci-lint run ./...; then failed=1; fi
  if ! ci_test_skip gosec && ! ci_test_run gosec gosec ./...; then failed=1; fi
  if ! ci_test_skip vulncheck && ! ci_test_run govulncheck govulncheck ./...; then failed=1; fi

  return "$failed"
}
