#!/usr/bin/env bash
set -euo pipefail

STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$STEP_DIR/../../.." && pwd)"
CONFIG="$STEP_DIR/_config/kilo/kilo.jsonc"
RULE="$STEP_DIR/_config/kilo/rules/privilege-escalation.md"
MAINTAINER="$STEP_DIR/_config/kilo/agents/system-maintainer.md"
RUNNER="$STEP_DIR/run.sh"
MIGRATOR="$STEP_DIR/migrate-kilo-jsonc.sh"
COMMANDS="$STEP_DIR/privilege-commands.txt"
FIXTURES="$STEP_DIR/tests/fixtures"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_literal() {
  local file="$1" text="$2"
  grep -Fq "$text" "$file" || fail "$file is missing: $text"
}

assert_policy() {
  local file="$1" command
  require_literal "$file" '"instructions": ["~/.config/kilo/rules/*.md"]'
  while IFS= read -r command; do
    [[ -n "$command" && "$command" != \#* ]] || continue
    require_literal "$file" "\"$command\": \"deny\""
    require_literal "$file" "\"$command *\": \"deny\""
  done < "$COMMANDS"
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME/.config/kilo" "$tmp/bin"
cat > "$tmp/bin/kilo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == config && "${2:-}" == check ]] || exit 2
[[ "${KILO_TEST_FAIL:-0}" != 1 ]] || exit 1
[[ -f "$HOME/.config/kilo/kilo.jsonc" ]]
EOF
chmod +x "$tmp/bin/kilo"
export PATH="$tmp/bin:$PATH"

run_success_case() {
  local fixture="$1" live="$HOME/.config/kilo/kilo.jsonc" before_second
  cp "$FIXTURES/$fixture" "$live"
  "$MIGRATOR" "$CONFIG" "$live" >/dev/null
  assert_policy "$live"
  before_second="$(sha256sum "$live")"
  "$MIGRATOR" "$CONFIG" "$live" >/dev/null
  [[ "$(sha256sum "$live")" == "$before_second" ]] || fail "$fixture changed on its second migration"
}

run_conflict_case() {
  local fixture="$1" live="$HOME/.config/kilo/kilo.jsonc" before
  cp "$FIXTURES/$fixture" "$live"
  before="$(sha256sum "$live")"
  if "$MIGRATOR" "$CONFIG" "$live" >"$tmp/conflict.out" 2>&1; then
    fail "$fixture unexpectedly migrated"
  fi
  [[ "$(sha256sum "$live")" == "$before" ]] || fail "$fixture changed after rejection"
  require_literal "$tmp/conflict.out" 'Manual merge required:'
}

[[ -f "$RULE" ]] || fail "global privilege-escalation rule not found"
assert_policy "$CONFIG"

# Missing instructions, wildcard-only denials, comments, unrelated permissions,
# and custom indexing all survive while the managed subset is added.
run_success_case no-instructions.jsonc
require_literal "$HOME/.config/kilo/kilo.jsonc" '// Keep this local comment.'
require_literal "$HOME/.config/kilo/kilo.jsonc" '"git status": "allow"'
require_literal "$HOME/.config/kilo/kilo.jsonc" '"edit": "ask"'
require_literal "$HOME/.config/kilo/kilo.jsonc" '"indexing": { "enabled": false, "provider": "local-custom" }'

run_success_case missing-pkexec.jsonc
run_success_case fully-migrated.jsonc

# A managed key that appears only in a comment must not count as configured:
# the real denial is added while the comment survives untouched.
run_success_case comment-key.jsonc
require_literal "$HOME/.config/kilo/kilo.jsonc" '// "sudo": "deny",'
[[ "$(grep -Fc '"sudo": "deny"' "$HOME/.config/kilo/kilo.jsonc")" == 2 ]] ||
  fail "comment-key.jsonc did not gain a real sudo denial"

# A commented-out anchor must not count as a second anchor.
run_success_case comment-anchor.jsonc
require_literal "$HOME/.config/kilo/kilo.jsonc" '// "*": "allow",'

# First installation uses the source and validates it in the isolated HOME.
rm -f "$HOME/.config/kilo/kilo.jsonc"
"$MIGRATOR" "$CONFIG" "$HOME/.config/kilo/kilo.jsonc" >/dev/null
cmp -s "$CONFIG" "$HOME/.config/kilo/kilo.jsonc" || fail "first installation did not copy the source"

# An anchor-less allowlist (common on existing hosts) migrates safely: the
# denials are inserted at the top of the bash object and existing entries and
# $schema URLs containing // survive.
run_success_case no-anchor.jsonc
require_literal "$HOME/.config/kilo/kilo.jsonc" '"curl *": "allow"'
require_literal "$HOME/.config/kilo/kilo.jsonc" '"systemctl status *": "deny"'
# shellcheck disable=SC2016
require_literal "$HOME/.config/kilo/kilo.jsonc" '"$schema": "https://app.kilo.ai/config.json"'

for fixture in incompatible-instructions.jsonc managed-allow.jsonc duplicate-managed.jsonc missing-bash.jsonc ambiguous-bash.jsonc two-anchors.jsonc; do
  run_conflict_case "$fixture"
done

# A symlink is rejected without changing its target.
cp "$FIXTURES/no-instructions.jsonc" "$tmp/symlink-target.jsonc"
rm -f "$HOME/.config/kilo/kilo.jsonc"
ln -s "$tmp/symlink-target.jsonc" "$HOME/.config/kilo/kilo.jsonc"
target_before="$(sha256sum "$tmp/symlink-target.jsonc")"
if "$MIGRATOR" "$CONFIG" "$HOME/.config/kilo/kilo.jsonc" >"$tmp/symlink.out" 2>&1; then
  fail "symlink destination unexpectedly migrated"
fi
[[ "$(sha256sum "$tmp/symlink-target.jsonc")" == "$target_before" ]] || fail "symlink target changed"

# Failed validation rolls the exact original content and mode back.
rm -f "$HOME/.config/kilo/kilo.jsonc"
cp "$FIXTURES/no-instructions.jsonc" "$HOME/.config/kilo/kilo.jsonc"
chmod 0640 "$HOME/.config/kilo/kilo.jsonc"
rollback_before="$(sha256sum "$HOME/.config/kilo/kilo.jsonc")"
if KILO_TEST_FAIL=1 "$MIGRATOR" "$CONFIG" "$HOME/.config/kilo/kilo.jsonc" >"$tmp/rollback.out" 2>&1; then
  fail "validation failure unexpectedly succeeded"
fi
[[ "$(sha256sum "$HOME/.config/kilo/kilo.jsonc")" == "$rollback_before" ]] || fail "validation failure did not restore content"
[[ "$(stat -c %a "$HOME/.config/kilo/kilo.jsonc")" == 640 ]] || fail "validation failure did not restore mode"
require_literal "$tmp/rollback.out" 'Restored the original'

# Successful replacement also preserves the destination mode.
"$MIGRATOR" "$CONFIG" "$HOME/.config/kilo/kilo.jsonc" >/dev/null
[[ "$(stat -c %a "$HOME/.config/kilo/kilo.jsonc")" == 640 ]] || fail "migration did not preserve mode"

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
require_literal "$RUNNER" '"$STEP_DIR/migrate-kilo-jsonc.sh" "$cfg_src" "$cfg_dst"'
require_literal "$REPO_ROOT/AGENTS.md" 'Chat LLM sessions must never execute privilege escalation'
require_literal "$REPO_ROOT/README.md" 'Chat LLM sessions never execute privilege escalation'
require_literal "$REPO_ROOT/docs/codemap.md" 'privilege-escalation policy'

echo "PASS: Kilo privilege-escalation policy and migration invariants"
