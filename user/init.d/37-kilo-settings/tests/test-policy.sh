#!/usr/bin/env bash
set -euo pipefail

STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$STEP_DIR/../../.." && pwd)"
CONFIG="$STEP_DIR/_config/kilo/kilo.jsonc"
RULE="$STEP_DIR/_config/kilo/rules/privilege-escalation.md"
MAINTAINER="$STEP_DIR/_config/kilo/agents/system-maintainer.md"
RUNNER="$STEP_DIR/run.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_literal() {
  local file="$1" text="$2"
  grep -Fq "$text" "$file" || fail "$file is missing: $text"
}

[[ -f "$RULE" ]] || fail "global privilege-escalation rule not found"
require_literal "$CONFIG" '"instructions": ["~/.config/kilo/rules/*.md"]'

for command in sudo sudoedit su runuser doas pkexec; do
  require_literal "$CONFIG" "\"$command\": \"deny\""
  require_literal "$CONFIG" "\"$command *\": \"deny\""
done

# The following assertions intentionally match literal Markdown/code text.
# shellcheck disable=SC2016
require_literal "$RULE" 'Never execute `sudo`'
require_literal "$RULE" 'Do not bypass this restriction'
require_literal "$RULE" 'User approval authorizes the proposed change and scope; it does not authorize'
require_literal "$RULE" 'the user exact, copy-pasteable commands'
require_literal "$RULE" 'Never claim'
require_literal "$RULE" 'that a command handed to the user was executed.'

require_literal "$MAINTAINER" 'current non-root identity'
# shellcheck disable=SC2016
require_literal "$MAINTAINER" 'Approval never authorizes you to execute `sudo`'
require_literal "$MAINTAINER" 'Give the user exact manual commands'

require_literal "$RUNNER" 'for dir in agents commands rules; do'
# shellcheck disable=SC2016
require_literal "$RUNNER" 'sync_dir_preserve "$SRC_CONFIG/$dir" "$KILO_CONFIG/$dir"'
# shellcheck disable=SC2016
require_literal "$RUNNER" 'merge changes into $cfg_dst manually'

require_literal "$REPO_ROOT/AGENTS.md" 'Chat LLM sessions must never execute privilege escalation'
require_literal "$REPO_ROOT/README.md" 'Chat LLM sessions never execute privilege escalation'
require_literal "$REPO_ROOT/docs/codemap.md" 'privilege-escalation policy'

echo "PASS: Kilo privilege-escalation policy invariants"
