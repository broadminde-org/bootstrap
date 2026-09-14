#!/usr/bin/env bash

ci_test_run_python() {
  ci_test_banner python "lock · lint · test"
  local failed=0

  if ! ci_test_skip uv-lock && ! ci_test_run uv-lock uv lock --check; then failed=1; fi
  if ! ci_test_skip ruff && ! ci_test_run ruff ruff check .; then failed=1; fi
  if ! ci_test_skip pytest && ! ci_test_run pytest uv run pytest; then failed=1; fi

  return "$failed"
}
