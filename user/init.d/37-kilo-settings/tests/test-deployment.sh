#!/usr/bin/env bash
set -euo pipefail

# LOCAL REGRESSION: exercises copies of the user runner and reverse wrapper in
# disposable non-root state, with stubbed nvm/client and no installation/network.
# This is not live deployment or official-client permission qualification.
# Usage from any CWD: bash /path/to/37-kilo-settings/tests/test-deployment.sh
[[ $EUID -ne 0 ]] || { echo 'Run as a non-root user.' >&2; exit 1; }
STEP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$STEP/../../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/kilo-deployment.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
test_python="$(command -v python3)"
work="$scratch/repo"
mkdir -p "$work/user/init.d/lib" "$work/init.d/lib" "$scratch/home/.nvm" "$scratch/bin"
cp "$REPO/user/init.sh" "$work/user/init.sh"
cp "$REPO/user/sync-kilo-context.sh" "$work/user/sync-kilo-context.sh"
cp "$REPO/user/init.d/lib/common.sh" "$work/user/init.d/lib/common.sh"
cp "$REPO/init.d/lib/conf.sh" "$work/init.d/lib/conf.sh"
cp "$REPO/example.bootstrap.conf.yml" "$work/example.bootstrap.conf.yml"
cp -R "$STEP" "$work/user/init.d/37-kilo-settings"
cat > "$work/bootstrap.conf.yml" <<'CONF'
capabilities:
  dev: false
CONF
cat > "$scratch/home/.nvm/nvm.sh" <<'NVM'
nvm() { return 0; }
NVM
cat > "$scratch/bin/kilo" <<'KILO'
#!/usr/bin/env bash
set -euo pipefail
# Only the existing JSONC validation path is accepted; any extra client command
# is recorded and rejected, so a prerequisite probe cannot silently return.
if [[ $# -ne 2 || "${1:-}" != config || "${2:-}" != check ]]; then
  : > "$KILO_TEST_UNEXPECTED_MARKER"
  exit 2
fi
[[ -z "${KILO_TEST_CONFIG_MARKER:-}" ]] || : > "$KILO_TEST_CONFIG_MARKER"
if [[ "${KILO_TEST_FAIL:-0}" == 1 ]]; then
  printf 'ghp_%036d\n' 0
  printf 'ghp_%036d\n' 0 >&2
  exit 1
fi
KILO
cat > "$scratch/managed-python" <<'MANAGED'
#!/bin/bash
set -euo pipefail
printf '%s\n' "${1:-}" >> "$KILO_TEST_MANAGED_LOG"
exec "$KILO_TEST_REAL_PYTHON" "$@"
MANAGED
cat > "$scratch/old-python3" <<'OLD'
#!/bin/bash
exit 1
OLD
cat > "$scratch/bin/uv" <<'UV'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$KILO_TEST_UV_LOG"
[[ "${KILO_TEST_NO_MANAGED:-0}" != 1 ]] || exit 1
[[ "$*" == 'python find --no-project --managed-python --no-python-downloads >=3.10' ]] || exit 2
printf '%s\n' "$KILO_TEST_MANAGED_PYTHON"
UV
chmod 0755 "$scratch/bin/kilo" "$scratch/bin/uv" "$scratch/managed-python" "$scratch/old-python3" "$work/user/init.sh" "$work/user/sync-kilo-context.sh"
export HOME="$scratch/home" NVM_DIR="$scratch/home/.nvm" PATH="$scratch/bin:$PATH"
unset BOOTSTRAP_CONFIG_FILE KILO_OPTIONAL_SKILLS KILO_TEST_FAIL KILO_TEST_NO_MANAGED
export KILO_TEST_CONFIG_MARKER="$scratch/config-called"
export KILO_TEST_UNEXPECTED_MARKER="$scratch/unexpected-client-command"
export KILO_TEST_REAL_PYTHON="$test_python" KILO_TEST_MANAGED_PYTHON="$scratch/managed-python"
export KILO_TEST_UV_LOG="$scratch/uv-calls" KILO_TEST_MANAGED_LOG="$scratch/managed-calls"
# Prevent Python module loading from writing bytecode into the source tree.
export PYTHONDONTWRITEBYTECODE=1
managed="$work/user/init.d/37-kilo-settings"
live="$HOME/.config/kilo"
state="$HOME/.local/state/bootstrap/kilo-context"
mkdir -p "$live/rules" "$HOME/.kilo/skills/user-extra/nested"
printf '%s\n' 'old legacy content' > "$live/rules/workspace-temp.md"
printf '%s\n' 'keep' > "$HOME/.kilo/skills/user-extra/nested/extra.md"
printf '%s\n' 'keep local rule' > "$live/rules/user-extra.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}
file_mode() {
  python3 -c 'import os, sys; print(f"{os.stat(sys.argv[1]).st_mode & 0o7777:o}")' "$1"
}
deploy() {
  # Deliberately retain the caller's unrelated CWD; runner resolves its own tree.
  "$work/user/init.sh" 37-kilo-settings > "$scratch/deploy.out" 2>&1
}

# A managed-only PATH has no system python3. Every external command needed by
# the runner is linked explicitly; uv and the managed interpreter are stubs
# around existing local binaries, so this test performs no install or download.
managed_path="$scratch/managed-path"
mkdir -p "$managed_path"
for tool in awk basename bash chmod cmp cp dirname env find hostname id mkdir mktemp mv perl rm rmdir sed sort xargs; do
  ln -s "$(command -v "$tool")" "$managed_path/$tool"
done
ln -s "$scratch/bin/kilo" "$managed_path/kilo"
ln -s "$scratch/bin/uv" "$managed_path/uv"

# Existing structural/selection preflight must still reject before writes or
# client validation. nvm is supplied through the isolated NVM_DIR.
if HOME="$scratch/fresh-home" KILO_OPTIONAL_SKILLS=unknown-skill deploy; then
  fail 'invalid selection passed preflight'
fi
[[ ! -e "$scratch/fresh-home" && ! -e "$work/.kilocodeignore" && ! -e "$KILO_TEST_CONFIG_MARKER" ]] || fail 'preflight rejection created state or reached validation'
[[ ! -e "$KILO_TEST_UNEXPECTED_MARKER" ]] || fail 'preflight invoked an unexpected client command'

# Fresh normal deployment needs only the validator stub, not a capability API.
KILO_OPTIONAL_SKILLS=skill-creator deploy
[[ -f "$KILO_TEST_CONFIG_MARKER" ]] || fail 'normal deployment did not validate JSONC'
[[ ! -e "$KILO_TEST_UNEXPECTED_MARKER" ]] || fail 'normal deployment invoked an unexpected client command'
for agent in architect code-reviewer mapper; do
  cmp -s "$managed/_config/kilo/agents/$agent.md" "$live/agents/$agent.md" || fail 'corrected agent not deployed'
done
[[ -f "$HOME/.kilo/skills/skill-creator/SKILL.md" ]] || fail 'selected optional absent'
[[ -f "$live/rules/workspace-temp.md" ]] || fail 'unknown retirement removed'
[[ -f "$HOME/.kilo/skills/user-extra/nested/extra.md" ]] || fail 'nested extra removed'
[[ "$(file_mode "$state")" == 700 ]] || fail 'state directory not private'
[[ ! -e "$KILO_TEST_UV_LOG" ]] || fail 'valid PATH python3 unexpectedly fell back to uv'

# Missing and old PATH python3 both use an existing managed interpreter. A
# second missing-python deployment exercises migrator mode preservation too.
for system_python in missing old; do
  managed_home="$scratch/managed-home-$system_python"
  rm -f "$KILO_TEST_CONFIG_MARKER"
  : > "$KILO_TEST_UV_LOG"
  : > "$KILO_TEST_MANAGED_LOG"
  if [[ "$system_python" == old ]]; then
    ln -s "$scratch/old-python3" "$managed_path/python3"
  fi
  HOME="$managed_home" PATH="$managed_path" deploy
  [[ -f "$KILO_TEST_CONFIG_MARKER" ]] || fail "$system_python python3 deployment did not reach validation"
  [[ -s "$KILO_TEST_MANAGED_LOG" ]] || fail "$system_python python3 did not use the managed interpreter"
  [[ -f "$managed_home/.config/kilo/rules/execution-focus.md" ]] || fail "$system_python python3 deployment did not converge"
  if [[ "$system_python" == missing ]]; then
    HOME="$managed_home" PATH="$managed_path" deploy
    HOME="$managed_home" PATH="$managed_path" "$work/user/sync-kilo-context.sh" --preview > "$scratch/managed-preview.out"
  fi
  if [[ "$system_python" == old ]]; then
    rm -f "$managed_path/python3"
  fi
done

# An old interpreter without a managed fallback is not sufficient. Resolution
# fails with the step-20 remediation before a fresh HOME or client state exists.
ln -s "$scratch/old-python3" "$managed_path/python3"
no_python_home="$scratch/no-python-home"
rm -f "$KILO_TEST_CONFIG_MARKER"
status=0
HOME="$no_python_home" PATH="$managed_path" KILO_TEST_NO_MANAGED=1 deploy || status=$?
[[ "$status" == 1 ]] || fail 'old python3 without a managed fallback unexpectedly succeeded'
[[ ! -e "$no_python_home" && ! -e "$KILO_TEST_CONFIG_MARKER" ]] || fail 'Python rejection created state or reached validation'
grep -Fq 'no existing Python 3.10+ found' "$scratch/deploy.out" || fail 'Python rejection lacks the version requirement'
grep -Fq 'run ./user/init.sh 20-python' "$scratch/deploy.out" || fail 'Python rejection lacks accurate remediation'
rm -f "$managed_path/python3"

# Fixture receipt through the production recorder, selected skill refresh and
# owned eligible retirement. These local receipts are not live-client evidence.
mkdir -p "$HOME/.config/user-tmpfiles.d"
printf '%s\n' 'old owned tmpfiles content' > "$HOME/.config/user-tmpfiles.d/kilo-agent-tmp.conf"
python3 - "$managed/context-files.py" "$state" "$live/rules/workspace-temp.md" "$HOME/.config/user-tmpfiles.d/kilo-agent-tmp.conf" <<'PY'
import importlib.util
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("receipt_fixture", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
content = Path(sys.argv[3]).read_bytes()
module.record(Path(sys.argv[2]), "config/rules/workspace-temp.md", content, content)
assert module.receipt(Path(sys.argv[2]), "config/rules/workspace-temp.md")["content"] == module.digest(content)
content = Path(sys.argv[4]).read_bytes()
module.record(Path(sys.argv[2]), "tmpfiles/kilo-agent-tmp.conf", content, content)
PY
printf '%s\n' 'Pending selected refresh.' >> "$managed/_kilo/skills/skill-creator/SKILL.md"
printf '%s\n' 'Pending config refresh.' >> "$managed/_config/kilo/rules/execution-focus.md"
KILO_OPTIONAL_SKILLS=skill-creator deploy
cmp -s "$managed/_kilo/skills/skill-creator/SKILL.md" "$HOME/.kilo/skills/skill-creator/SKILL.md" || fail 'selected optional not refreshed'
cmp -s "$managed/_config/kilo/rules/execution-focus.md" "$live/rules/execution-focus.md" || fail 'config not refreshed'
[[ ! -e "$live/rules/workspace-temp.md" ]] || fail 'owned retirement fixture was not actually eligible'
[[ ! -e "$HOME/.config/user-tmpfiles.d/kilo-agent-tmp.conf" ]] || fail 'owned tmpfiles retirement fixture was not actually eligible'
printf '%s\n' 'old legacy content' > "$live/rules/workspace-temp.md"
optional_before="$(sha256 "$HOME/.kilo/skills/skill-creator/SKILL.md")"
printf '%s\n' 'new canonical optional body' >> "$managed/_kilo/skills/skill-creator/SKILL.md"
deploy
[[ "$(sha256 "$HOME/.kilo/skills/skill-creator/SKILL.md")" == "$optional_before" ]] || fail 'deselected optional refreshed'

key='config/rules/execution-focus.md'
source="$managed/_config/kilo/rules/execution-focus.md"
target="$live/rules/execution-focus.md"
printf '%s\n' 'Reviewed non-sensitive local sentence.' >> "$target"
source_before="$(sha256 "$source")"
"$work/user/sync-kilo-context.sh" > "$scratch/preview.out"
[[ "$(sha256 "$source")" == "$source_before" ]] || fail 'preview changed source'
receipt_id="$(printf '%s' "$key" | sha256)"
receipt_id="${receipt_id%% *}"
receipt_before="$(sha256 "$state/$receipt_id.json")"
"$work/user/sync-kilo-context.sh" --apply "$key" > "$scratch/import.out"
cmp -s "$source" "$target" || fail 'selected import did not converge'
[[ "$(sha256 "$state/$receipt_id.json")" == "$receipt_before" ]] || fail 'import advanced deployment identity'
"$work/user/sync-kilo-context.sh" --apply "$key" > "$scratch/import-again.out"
printf '%s\n' 'Another local sentence.' >> "$target"
if "$work/user/sync-kilo-context.sh" --apply "$key" > "$scratch/stale.out" 2>&1; then
  fail 'stale baseline imported another change'
fi

# A client-validation failure after earlier file deployment must restore only
# JSONC while retaining the successfully deployed file and its receipt.
printf '%s\n' 'Next canonical baseline.' >> "$source"
cp "$managed/tests/fixtures/no-instructions.jsonc" "$live/kilo.jsonc"
chmod 0640 "$live/kilo.jsonc"
json_before="$(sha256 "$live/kilo.jsonc")"
for trace in plain traced; do
  rm -f "$KILO_TEST_CONFIG_MARKER"
  status=0
  if [[ "$trace" == traced ]]; then
    env "SHELLOPTS=$SHELLOPTS:xtrace" KILO_TEST_FAIL=1 "$work/user/init.sh" 37-kilo-settings > "$scratch/deploy.out" 2>&1 || status=$?
  else
    KILO_TEST_FAIL=1 deploy || status=$?
  fi
  [[ "$status" == 1 ]] || fail 'validation rejection status not exact runner failure'
  [[ -f "$KILO_TEST_CONFIG_MARKER" ]] || fail 'failure did not reach JSONC validation'
  [[ "$(sha256 "$live/kilo.jsonc")" == "$json_before" ]] || fail 'JSONC rollback bytes changed'
  [[ "$(file_mode "$live/kilo.jsonc")" == 640 ]] || fail 'JSONC rollback mode changed'
  if grep -Eq 'ghp_[0-9]{36}' "$scratch/deploy.out"; then fail 'validator diagnostic leaked'; fi
done
[[ "$(sha256 "$live/kilo.jsonc")" == "$json_before" ]] || fail 'JSONC rollback bytes changed'
[[ "$(file_mode "$live/kilo.jsonc")" == 640 ]] || fail 'JSONC rollback mode changed'
cmp -s "$source" "$target" || fail 'earlier successful file write unexpectedly rolled back'
[[ "$(sha256 "$state/$receipt_id.json")" != "$receipt_before" ]] || fail 'earlier successful receipt not advanced'
deploy
deploy
[[ -f "$live/rules/user-extra.md" ]] || fail 'user rule extra removed'
[[ ! -e "$KILO_TEST_UNEXPECTED_MARKER" ]] || fail 'deployment invoked an unexpected client command'
echo 'PASS: isolated deployment/import convergence and JSONC-only rollback (stub client, not enforcement)'
