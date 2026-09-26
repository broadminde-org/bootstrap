#!/usr/bin/env bash
# Gate for ci-test runner changes: shellcheck the runner + families, then
# run the bats contract suite. Run before committing changes to
# scripts/ci-test or scripts/ci.d/*.
set -euo pipefail

cd "$(dirname "$0")"

shellcheck ../scripts/ci-test ../scripts/ci.d/*.sh
shellcheck run.sh test_helper.bash ./*.bats
bats --tap .
