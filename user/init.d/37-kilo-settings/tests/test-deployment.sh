#!/usr/bin/env bash
set -euo pipefail

# RUNTIME QUALIFICATION: separately authorize before running. This exercises the
# production user runner and reverse wrapper in disposable non-root state. The
# fake validator tests file migration only, never effective permission behavior.
# Usage from any CWD: bash /path/to/37-kilo-settings/tests/test-deployment.sh
[[ $EUID -ne 0 ]] || { echo 'Run as a non-root user.' >&2; exit 1; }
STEP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$STEP/../../.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
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
if [[ "${1:-}" == capabilities && "${2:-}" == strict-custom-roles-v1 ]]; then
  [[ -z "${KILO_TEST_PROBE_MARKER:-}" ]] || printf '%s\n' PROBE_CALLED > "$KILO_TEST_PROBE_MARKER"
  case "${KILO_TEST_CAPABILITY:-supported}" in
    unsupported) exit 2 ;;
    wrong) printf '%s\n' 'kilo-capability:unrelated'; exit 0 ;;
    exact_fail) printf '%s\n' 'kilo-capability:strict-custom-roles-v1'; exit 2 ;;
    extra) printf '%s\n' 'kilo-capability:strict-custom-roles-v1' 'unexpected extra'; exit 0 ;;
    sensitive_ok|sensitive_fail) printf 'ghp_%036d\n' 0; printf 'ghp_%036d\n' 0 >&2; [[ "$KILO_TEST_CAPABILITY" == sensitive_ok ]] && exit 0; exit 2 ;;
    exact_stderr_fail) printf '%s\n' 'kilo-capability:strict-custom-roles-v1'; printf 'ghp_%036d\n' 0 >&2; exit 2 ;;
  esac
  printf '%s\n' 'kilo-capability:strict-custom-roles-v1'
  exit 0
fi
[[ "${1:-}" == config && "${2:-}" == check ]] || exit 2
[[ -z "${KILO_TEST_CONFIG_MARKER:-}" ]] || : > "$KILO_TEST_CONFIG_MARKER"
[[ "${KILO_TEST_FAIL:-0}" != 1 ]]
KILO
chmod 0755 "$scratch/bin/kilo" "$work/user/init.sh" "$work/user/sync-kilo-context.sh"
export HOME="$scratch/home" NVM_DIR="$scratch/home/.nvm" PATH="$scratch/bin:$PATH"
unset BOOTSTRAP_CONFIG_FILE KILO_OPTIONAL_SKILLS KILO_TEST_FAIL KILO_TEST_CAPABILITY KILO_TEST_CONFIG_MARKER KILO_TEST_PROBE_MARKER
managed="$work/user/init.d/37-kilo-settings"
live="$HOME/.config/kilo"
state="$HOME/.local/state/bootstrap/kilo-context"
mkdir -p "$live/rules" "$HOME/.kilo/skills/user-extra/nested"
printf '%s\n' 'old legacy content' > "$live/rules/workspace-temp.md"
printf '%s\n' 'keep' > "$HOME/.kilo/skills/user-extra/nested/extra.md"
printf '%s\n' 'keep local rule' > "$live/rules/user-extra.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
deploy() {
  # Deliberately retain the caller's unrelated CWD; runner resolves its own tree.
  "$work/user/init.sh" 37-kilo-settings > "$scratch/deploy.out" 2>&1
}

# UNRUN: admission must also precede directory/create-once writes on a fresh home.
expected='ERROR: corrected strict-custom-roles-v1 client required; no context deployed. Installation and qualification require separate approval.'
status=0
HOME="$scratch/fresh-home" KILO_TEST_CAPABILITY=unsupported KILO_TEST_PROBE_MARKER="$scratch/fresh-probe" KILO_TEST_CONFIG_MARKER="$scratch/fresh-config" deploy || status=$?
[[ "$status" == 1 ]] || fail 'fresh capability rejection status not exact runner failure'
[[ -f "$scratch/fresh-probe" && "$(< "$scratch/fresh-probe")" == PROBE_CALLED ]] || fail 'fresh capability probe not reached'
grep -Fxq "$expected" "$scratch/deploy.out" || fail 'fresh capability diagnostic missing'
[[ ! -e "$scratch/fresh-home" && ! -e "$work/.kilocodeignore" && ! -e "$scratch/fresh-config" ]] || fail 'fresh rejection created deployment state or reached validation'

KILO_OPTIONAL_SKILLS=skill-creator deploy
[[ -f "$HOME/.kilo/skills/skill-creator/SKILL.md" ]] || fail 'selected optional absent'
[[ -f "$live/rules/workspace-temp.md" ]] || fail 'unknown retirement removed'
[[ -f "$HOME/.kilo/skills/user-extra/nested/extra.md" ]] || fail 'nested extra removed'
[[ "$(stat -c %a "$state")" == 700 ]] || fail 'state directory not private'
# UNRUN: authentic prior receipt through the production recorder, selected skill
# refresh and owned eligible retirement. Stub outcomes prove ordering, not policy.
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
snapshot() { tar --sort=name --format=ustar -cf - "$live" "$state" "$HOME/.kilo/skills" "$HOME/.config/user-tmpfiles.d" "$work/.kilocodeignore" 2>/dev/null | sha256sum; }
for trace in plain traced; do
  for capability in unsupported wrong exact_fail extra sensitive_ok sensitive_fail exact_stderr_fail; do
    before="$(snapshot)"
    rm -f "$scratch/probe-called" "$scratch/config-called"
    status=0
    if [[ "$trace" == traced ]]; then
      env "SHELLOPTS=$SHELLOPTS:xtrace" KILO_OPTIONAL_SKILLS=skill-creator KILO_TEST_CAPABILITY="$capability" KILO_TEST_PROBE_MARKER="$scratch/probe-called" KILO_TEST_CONFIG_MARKER="$scratch/config-called" "$work/user/init.sh" 37-kilo-settings > "$scratch/deploy.out" 2>&1 || status=$?
    else
      KILO_OPTIONAL_SKILLS=skill-creator KILO_TEST_CAPABILITY="$capability" KILO_TEST_PROBE_MARKER="$scratch/probe-called" KILO_TEST_CONFIG_MARKER="$scratch/config-called" deploy || status=$?
    fi
    [[ "$status" == 1 ]] || fail 'capability rejection status not exact runner failure'
    [[ -f "$scratch/probe-called" && "$(< "$scratch/probe-called")" == PROBE_CALLED ]] || fail 'capability probe not reached'
    grep -Fxq "$expected" "$scratch/deploy.out" || fail 'capability rejection diagnostic missing'
    [[ "$before" == "$(snapshot)" ]] || fail 'capability rejection changed prior files, receipts, skills or eligible retirement'
    [[ ! -e "$scratch/config-called" ]] || fail 'capability rejection reached final config validation'
    if grep -Eq 'ghp_[0-9]{36}' "$scratch/deploy.out"; then fail 'traced capability output leaked'; fi
  done
done
KILO_OPTIONAL_SKILLS=skill-creator deploy
[[ ! -e "$live/rules/workspace-temp.md" ]] || fail 'owned retirement fixture was not actually eligible'
[[ ! -e "$HOME/.config/user-tmpfiles.d/kilo-agent-tmp.conf" ]] || fail 'owned tmpfiles retirement fixture was not actually eligible'
printf '%s\n' 'old legacy content' > "$live/rules/workspace-temp.md"
optional_before="$(sha256sum "$HOME/.kilo/skills/skill-creator/SKILL.md")"
printf '%s\n' 'new canonical optional body' >> "$managed/_kilo/skills/skill-creator/SKILL.md"
deploy
[[ "$(sha256sum "$HOME/.kilo/skills/skill-creator/SKILL.md")" == "$optional_before" ]] || fail 'deselected optional refreshed'

key='config/rules/execution-focus.md'
source="$managed/_config/kilo/rules/execution-focus.md"
target="$live/rules/execution-focus.md"
printf '%s\n' 'Reviewed non-sensitive local sentence.' >> "$target"
source_before="$(sha256sum "$source")"
"$work/user/sync-kilo-context.sh" > "$scratch/preview.out"
[[ "$(sha256sum "$source")" == "$source_before" ]] || fail 'preview changed source'
receipt_id="$(printf '%s' "$key" | sha256sum)"
receipt_id="${receipt_id%% *}"
receipt_before="$(sha256sum "$state/$receipt_id.json")"
"$work/user/sync-kilo-context.sh" --apply "$key" > "$scratch/import.out"
cmp -s "$source" "$target" || fail 'selected import did not converge'
[[ "$(sha256sum "$state/$receipt_id.json")" == "$receipt_before" ]] || fail 'import advanced deployment identity'
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
json_before="$(sha256sum "$live/kilo.jsonc")"
if KILO_TEST_FAIL=1 deploy; then fail 'fake validation failure accepted'; fi
[[ "$(sha256sum "$live/kilo.jsonc")" == "$json_before" ]] || fail 'JSONC rollback bytes changed'
[[ "$(stat -c %a "$live/kilo.jsonc")" == 640 ]] || fail 'JSONC rollback mode changed'
cmp -s "$source" "$target" || fail 'earlier successful file write unexpectedly rolled back'
[[ "$(sha256sum "$state/$receipt_id.json")" != "$receipt_before" ]] || fail 'earlier successful receipt not advanced'
deploy
deploy
[[ -f "$live/rules/user-extra.md" ]] || fail 'user rule extra removed'
echo 'PASS: isolated deployment/import convergence and JSONC-only rollback (stub client, not enforcement)'
