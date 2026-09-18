#!/usr/bin/env bash

ci_test_run_python() {
  ci_test_banner python "lock · lint · test"
  local failed=0

  if ! ci_test_skip uv-lock && ! ci_test_run uv-lock uv lock --check; then failed=1; fi

  # ruff runs via uv when this is a uv project (consistent with the other
  # python invocations), falling back to a PATH-installed ruff, else SKIP.
  if ci_test_skip ruff; then
    :
  elif command -v uv >/dev/null 2>&1 && [[ -f pyproject.toml ]]; then
    if ! ci_test_run ruff uv run ruff check .; then failed=1; fi
  elif command -v ruff >/dev/null 2>&1; then
    if ! ci_test_run ruff ruff check .; then failed=1; fi
  else
    printf 'SKIP ruff (not installed)\n'
  fi

  if ! ci_test_skip pytest && ! ci_test_run pytest uv run pytest; then failed=1; fi

  return "$failed"
}
