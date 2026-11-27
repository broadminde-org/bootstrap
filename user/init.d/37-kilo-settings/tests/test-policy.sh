#!/usr/bin/env bash
set -euo pipefail

# Local regression checks use disposable non-root state and a stub validator.
# They do not invoke an installed client or prove tool permission enforcement.
[[ $EUID -ne 0 ]] || { echo 'Run as a non-root user.' >&2; exit 1; }

STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$STEP_DIR/../../.." && pwd)"
CONFIG="$STEP_DIR/_config/kilo/kilo.jsonc"
MAINTAINER="$STEP_DIR/_config/kilo/agents/system-maintainer.md"
RUNNER="$STEP_DIR/run.sh"
MIGRATOR="$STEP_DIR/migrate-kilo-jsonc.sh"
COMMANDS="$STEP_DIR/privilege-commands.txt"
PATTERNS="$STEP_DIR/managed-deny-patterns.txt"
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
  local file="$1" command pattern
  require_literal "$file" '"instructions": ["~/.config/kilo/rules/*.md"]'
  while IFS= read -r command; do
    [[ -n "$command" && "$command" != \#* ]] || continue
    require_literal "$file" "\"$command\": \"deny\""
    require_literal "$file" "\"$command *\": \"deny\""
  done < "$COMMANDS"
  while IFS= read -r pattern; do
    [[ -n "$pattern" && "$pattern" != \#* ]] || continue
    require_literal "$file" "\"$pattern\": \"deny\""
  done < "$PATTERNS"
  require_literal "$file" '"playwright_*": "deny"'
  require_literal "$file" '"svelte_*": "deny"'
  require_literal "$file" '"mcp:playwright:*": "deny"'
  require_literal "$file" '"mcp:svelte:*": "deny"'
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME/.config/kilo" "$tmp/bin"
cat > "$tmp/bin/kilo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == config && "${2:-}" == check ]] || exit 2
if [[ "${KILO_TEST_NO_CLIENT:-0}" == 1 ]]; then
  : > "$KILO_TEST_CLIENT_MARKER"
  exit 99
fi
if [[ "${KILO_TEST_FAIL:-0}" == 1 ]]; then
  printf 'ghp_%036d\n' 0
  printf 'ghp_%036d\n' 0 >&2
  exit 1
fi
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
  if KILO_TEST_NO_CLIENT=1 KILO_TEST_CLIENT_MARKER="$tmp/conflict-client-called" \
      "$MIGRATOR" --preflight "$CONFIG" "$live" >"$tmp/conflict-preflight.out" 2>&1; then
    fail "$fixture unexpectedly passed structural preflight"
  fi
  [[ ! -e "$tmp/conflict-client-called" ]] || fail 'conflict preflight invoked a client'
  [[ "$(sha256sum "$live")" == "$before" ]] || fail "$fixture changed during preflight rejection"
  require_literal "$tmp/conflict-preflight.out" 'Manual merge required:'
  if "$MIGRATOR" "$CONFIG" "$live" >"$tmp/conflict.out" 2>&1; then
    fail "$fixture unexpectedly migrated"
  fi
  [[ "$(sha256sum "$live")" == "$before" ]] || fail "$fixture changed after rejection"
  require_literal "$tmp/conflict.out" 'Manual merge required:'
}

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
run_success_case compact.jsonc
run_success_case unicode-preserved.jsonc
unicode_line="$(grep -F '"note"' "$FIXTURES/unicode-preserved.jsonc")"
require_literal "$HOME/.config/kilo/kilo.jsonc" "$unicode_line"
run_success_case inherited-ordered-read.jsonc
perl -0e '
  use JSON::PP ();
  my @texts = map { open my $fh, "<", $_ or die "fixture unavailable"; local $/; <$fh> } @ARGV;
  my $json = JSON::PP->new->utf8->canonical;
  my @permissions = map { $json->decode($_)->{permission} } @texts;
  exit 1 unless $json->encode($permissions[0]->{"r*"}) eq $json->encode($permissions[1]->{"r*"});
  # The fixture contains flat string-valued members. JSON grammar validates the
  # whole document; these parsed pair arrays retain serialization order, not policy evaluation.
  sub pairs {
    my ($text, $key) = @_;
    $text =~ /"\Q$key\E"\s*:\s*(\{[^{}]*\})/s or die "member missing";
    my $object = $1;
    my @pairs;
    while ($object =~ /("(?:[^"\\]|\\.)*"\s*:\s*"(?:[^"\\]|\\.)*")/g) {
      my $member = JSON::PP->new->decode("{" . $1 . "}");
      my ($name) = keys %$member;
      push @pairs, [$name, $member->{$name}];
    }
    return \@pairs;
  }
  exit 1 unless $json->encode(pairs($texts[0], "r*")) eq $json->encode(pairs($texts[1], "r*"));
  my $read = pairs($texts[1], "read");
  my $original = pairs($texts[0], "read");
  my @unrelated = grep { $_->[0] ne "mcp:playwright:*" && $_->[0] ne "mcp:svelte:*" } @$read;
  exit 1 unless $json->encode($original) eq $json->encode(\@unrelated);
  exit 1 unless @$read == @$original + 2 && $json->encode([@$read[0 .. $#$original]]) eq $json->encode($original);
  for my $key ("mcp:playwright:*", "mcp:svelte:*") {
    my @entries = grep { $_->[0] eq $key } @$read;
    exit 1 unless @entries == 1 && $entries[0]->[1] eq "deny";
  }
  for my $text (@texts) {
    my @positions = map { $text =~ /"\Q$_\E"\s*:/g or die "outer member missing"; $-[0] } ("r*", "bash", "read");
    exit 1 unless $positions[0] < $positions[1] && $positions[1] < $positions[2];
  }
' "$FIXTURES/inherited-ordered-read.jsonc" "$HOME/.config/kilo/kilo.jsonc" || fail 'complete inherited ordered read policy changed'

# These are ordering/splice regressions, not a permission evaluator. The stub
# validator above proves no client/tool enforcement, visibility or connection.
run_success_case later-overlapping-allows.jsonc
require_literal "$HOME/.config/kilo/kilo.jsonc" '"*.env": "ask"'
require_literal "$HOME/.config/kilo/kilo.jsonc" '"git status": "allow"'
perl -0ne '
  use JSON::PP ();
  my $permission = JSON::PP->new->utf8->relaxed->decode($_)->{permission};
  for my $pair ([$permission->{bash}, "s*", "sudo"],
                 [$permission->{read}, "*", "mcp:playwright:*"],
                 [$permission, "playwright_browser_*", "playwright_*"],
                 [$permission, "svelte_get_*", "svelte_*"]) {
    # JSON::PP hashes do not preserve source order; constrain offsets to the
    # respective serialized object rather than another tools wildcard.
    my $object = $pair->[0];
    exit 1 unless exists $object->{$pair->[1]} && exists $object->{$pair->[2]};
    my $scope = $_;
    if ($pair->[0] == $permission->{bash}) { $scope =~ /"bash"\s*:\s*(\{[^{}]*\})/s or exit 1; $scope = $1 }
    elsif ($pair->[0] == $permission->{read}) { $scope =~ /"read"\s*:\s*(\{[^{}]*\})/s or exit 1; $scope = $1 }
    my ($allow, $deny) = map { index($scope, JSON::PP->new->allow_nonref->encode($_)) } @$pair[1,2];
    exit 1 unless $allow >= 0 && $deny >= 0 && $allow < $deny;
  }
' "$HOME/.config/kilo/kilo.jsonc" || fail 'managed denial ordering regressed'

# Kilo's generated schema-only file has no local policy to preserve.
run_success_case schema-only.jsonc
cmp -s "$CONFIG" "$HOME/.config/kilo/kilo.jsonc" || fail "schema-only config did not receive the managed source"

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
# managed denials follow local rules, and existing entries and
# $schema URLs containing // survive.
run_success_case no-anchor.jsonc
require_literal "$HOME/.config/kilo/kilo.jsonc" '"curl *": "allow"'
require_literal "$HOME/.config/kilo/kilo.jsonc" '"systemctl status *": "deny"'
# shellcheck disable=SC2016
require_literal "$HOME/.config/kilo/kilo.jsonc" '"$schema": "https://app.kilo.ai/config.json"'

for fixture in incompatible-instructions.jsonc managed-allow.jsonc duplicate-managed.jsonc missing-bash.jsonc ambiguous-bash.jsonc two-anchors.jsonc scalar-read.jsonc later-permission-wildcard.jsonc unicode-duplicate.jsonc; do
  run_conflict_case "$fixture"
done

# Invalid UTF-8 must reject before any live file mutation; generate bytes only
# inside disposable HOME, never modify tracked source fixtures.
printf '{"permission":{"bash":{"*":"allow"}},"note":"\377"}\n' > "$HOME/.config/kilo/kilo.jsonc"
encoding_before="$(sha256sum "$HOME/.config/kilo/kilo.jsonc")"
if "$MIGRATOR" "$CONFIG" "$HOME/.config/kilo/kilo.jsonc" > "$tmp/encoding.out" 2>&1; then
  fail 'invalid UTF-8 accepted'
fi
[[ "$(sha256sum "$HOME/.config/kilo/kilo.jsonc")" == "$encoding_before" ]] || fail 'invalid UTF-8 config mutated'

# Structural preflight must neither initialize a client nor prepare a missing
# parent/config. Preflight shares the normal migrator's admission checks.
export KILO_TEST_NO_CLIENT=1 KILO_TEST_CLIENT_MARKER="$tmp/preflight-client-called"
"$MIGRATOR" --preflight "$CONFIG" "$tmp/absent/kilo.jsonc" >/dev/null
[[ ! -e "$tmp/absent" ]] || fail 'preflight created a parent directory'
cp "$FIXTURES/later-overlapping-allows.jsonc" "$HOME/.config/kilo/kilo.jsonc"
preflight_before="$(sha256sum "$HOME/.config/kilo/kilo.jsonc")"
"$MIGRATOR" --preflight "$CONFIG" "$HOME/.config/kilo/kilo.jsonc" >/dev/null
[[ "$(sha256sum "$HOME/.config/kilo/kilo.jsonc")" == "$preflight_before" ]] || fail 'preflight wrote config'
[[ ! -e "$KILO_TEST_CLIENT_MARKER" ]] || fail 'preflight invoked a client'
unset KILO_TEST_NO_CLIENT KILO_TEST_CLIENT_MARKER

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
if grep -Eq 'ghp_[0-9]{36}' "$tmp/rollback.out"; then
  fail 'stub diagnostic sensitive content was emitted or retained'
fi

# Failed first installation must restore absence, not retain a rejected config.
rm -f "$HOME/.config/kilo/kilo.jsonc"
if KILO_TEST_FAIL=1 "$MIGRATOR" "$CONFIG" "$HOME/.config/kilo/kilo.jsonc" >"$tmp/absence-rollback.out" 2>&1; then
  fail 'failed first installation unexpectedly succeeded'
fi
[[ ! -e "$HOME/.config/kilo/kilo.jsonc" ]] || fail 'failed first installation retained config'
if compgen -G "$HOME/.config/kilo/.kilo-migration.*" >/dev/null; then
  fail 'failed first installation retained staging'
fi
require_literal "$tmp/absence-rollback.out" 'Restored original kilo.jsonc absence'
if grep -Eq 'ghp_[0-9]{36}' "$tmp/absence-rollback.out"; then
  fail 'first-install stub sensitive diagnostic was emitted or retained'
fi
cp "$FIXTURES/no-instructions.jsonc" "$HOME/.config/kilo/kilo.jsonc"
chmod 0640 "$HOME/.config/kilo/kilo.jsonc"

# Successful replacement also preserves the destination mode.
"$MIGRATOR" "$CONFIG" "$HOME/.config/kilo/kilo.jsonc" >/dev/null
[[ "$(stat -c %a "$HOME/.config/kilo/kilo.jsonc")" == 640 ]] || fail "migration did not preserve mode"

# The following assertions intentionally match literal Markdown/code text.
# Nested prefix-named Python tests need a separate worktree-relative pattern.
# This source assertion is not qualification of the client's matcher or tools.
require_literal "$STEP_DIR/_config/kilo/agents/test-engineer.md" '"*/test_*.py": allow'
# Compare the bounded permission declarations and their serialization order.
# This deliberately handles only these checked-in blocks, not arbitrary YAML,
# glob evaluation, effective inherited policy, or actual client enforcement.
python3 - "$STEP_DIR" <<'PY'
import sys
from pathlib import Path

step = Path(sys.argv[1])
common = [
    'bash: deny', 'task: deny', 'agent_manager: deny', 'goal: deny',
    'lsp: deny', 'skill: deny', 'webfetch: allow', 'websearch: allow',
    'external_directory: ask',
]
expected = {
    'architect': common + [
        'edit:', '  "*": deny', '  ".kilo/plans/*.md": allow',
        '  "plans/*.md": allow', '  ".plans/*.md": allow',
        'question: allow', 'open_plan: allow',
    ],
    'code-reviewer': ['edit: deny'] + common + ['question: allow'],
    'mapper': common + [
        'question: allow', 'edit:', '  "*": deny',
        '  "docs/*.md": allow', '  "*/docs/*.md": allow',
    ],
}
for name, rules in expected.items():
    text = (step / f'_config/kilo/agents/{name}.md').read_text()
    sections = text.split('---', 2)
    assert len(sections) == 3 and not sections[0].strip(), f'{name}: frontmatter missing'
    frontmatter = sections[1]
    assert 'permission_mode:' not in frontmatter, f'{name}: unsupported mode'
    assert frontmatter.count('\npermission:\n') == 1, f'{name}: permission block missing/duplicated'
    block = frontmatter.split('\npermission:\n', 1)[1]
    actual = []
    for line in block.splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        assert line.startswith('  '), f'{name}: unexpected block shape'
        actual.append(line[2:])
    assert actual == rules, f'{name}: permission scope/order changed'
    # No broad read/search override: inherited sensitive-path policy is retained.
    assert not any(line.lstrip().startswith(('read:', 'grep:', 'glob:')) for line in actual)
    assert 'prompt-level' in sections[2], f'{name}: scope distinction missing'
    assert 'operator decision' in sections[2], f'{name}: unresolved boundary not surfaced'
runner = (step / 'run.sh').read_text()
assert 'kilo capabilities' not in runner, 'private capability command returned'
assert 'strict-custom-roles-v1' not in runner, 'private protocol returned'
repo = step.parents[2]
for relative in ('README.md', 'docs/codemap.md'):
    text = (repo / relative).read_text()
    for obsolete in ('permission_mode: strict', 'strict-custom-roles-v1', 'Rule.ceiling'):
        assert obsolete not in text, f'{relative}: obsolete private-client requirement returned'
    for limitation in ('prompt-level', 'identified official', 'OS sandbox'):
        assert limitation in text, f'{relative}: evidence/scope distinction missing'
PY
# shellcheck disable=SC2016
require_literal "$MAINTAINER" 'current non-root identity'
# shellcheck disable=SC2016
require_literal "$MAINTAINER" 'Approval never authorizes you to execute `sudo`'
require_literal "$MAINTAINER" 'Give the user exact manual commands'
# shellcheck disable=SC2016
require_literal "$RUNNER" 'python3 "$STEP_DIR/context-files.py" config'
# The retired profile-temp policy must not return on fresh installs or reruns.
[[ ! -e "$STEP_DIR/_config/kilo/rules/workspace-temp.md" ]] || fail "profile-temp rule is still shipped"
# shellcheck disable=SC2016
require_literal "$RUNNER" 'python3 "$STEP_DIR/context-files.py" retire'
# shellcheck disable=SC2016
require_literal "$STEP_DIR/context-files.py" 'tmpfiles/kilo-agent-tmp.conf'
if grep -Eq 'AGENT_TMP|\.tmpdir|systemctl --user enable --now systemd-tmpfiles-clean.timer' "$RUNNER"; then
  fail "runner still provisions profile scratch or its cleanup timer"
fi
# shellcheck disable=SC2016
require_literal "$RUNNER" '"$STEP_DIR/migrate-kilo-jsonc.sh" "$cfg_src" "$cfg_dst"'
require_literal "$REPO_ROOT/AGENTS.md" 'Chat LLM sessions must never execute privilege escalation'
require_literal "$REPO_ROOT/README.md" 'Chat LLM sessions never execute privilege escalation'

echo 'PASS: canonical denial strings and isolated migration file invariants (not effective enforcement)'
