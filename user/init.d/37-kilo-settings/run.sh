#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 37-kilo-settings — Deploy the Kilo global context set from skeleton dirs.
#
# Deploys from two source directories that mirror the live layout:
#
#   Source                                   | Target
#   -----------------------------------------|-----------------------
#   init.d/37-kilo-settings/_config/kilo/    | ~/.config/kilo/
#   init.d/37-kilo-settings/_kilo/           | ~/.kilo/
#
# This matches Kilo's Marketplace installation conventions:
#
#   Type    | Global destination
#   --------|-------------------
#   Agent   | ~/.config/kilo/agents/<name>.md
#   Command | ~/.config/kilo/commands/<name>.md
#   Skill   | ~/.kilo/skills/<name>/
#
# _config/kilo/ deploys:
#   agents/    — agent definitions (marketplace agents)
#   commands/  — slash commands
#   kilo.json  — MCP servers. Mirrors what the Kilo Marketplace installs
#                for the Playwright MCP (@playwright/mcp via npx; node/npx
#                is provided by 35-node). Also carries the Svelte docs MCP
#                as a remote server (https://mcp.svelte.dev/mcp — hosted by
#                the Svelte team, always tracks current docs, no local deps,
#                degrades gracefully when offline). Kilo deep-merges this
#                with kilo.jsonc, so the two files stay separate concerns.
#   kilo.jsonc — instructions glob (rules/) plus permissions
#
# ~/.config/kilo/rules/ is loaded globally by the instructions glob in
# kilo.jsonc. Keep this set small: rules are present in every agent context.
# The privilege boundary for chat LLM sessions is enforced by the bash
# denials in kilo.jsonc and the migrator below, not by a rule file.
#
# _kilo/ deploys:
#   skills/    — skills (each skill is a subdirectory with SKILL.md)
#
# Skills that document a specific provisioned feature live with that
# feature's step instead of here, so they share the step's capability
# gating — e.g. the central-caddy skill deploys from 60-caddy/kilo/skills/
# (gated on docker + caddy), not from this skeleton.
#
# Idempotent: directories are synced without deletion — user-installed agents,
# commands, and skills survive re-runs. kilo.json is copied once and remains a
# manual merge. kilo.jsonc is copied on first install; existing files receive a
# narrow, validated migration of the managed instructions and privilege-denial
# settings. Unfamiliar or conflicting JSONC is rejected for manual review.
#
# Run as the deploy user (./user/init.sh 37-kilo-settings).

STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_CONFIG="$STEP_DIR/_config/kilo"
SRC_KILO="$STEP_DIR/_kilo"
SRC_KILOCODEIGNORE="$STEP_DIR/.kilocodeignore"
OPTIONAL_SKILLS_FILE="$STEP_DIR/optional-skills.txt"
DEFAULT_SKILLS_FILE="$STEP_DIR/default-skills.txt"
BOOTSTRAP_ROOT="$(cd "$STEP_DIR/../../.." && pwd)"

KILO_CONFIG="$HOME/.config/kilo"
KILO_HOME="$HOME/.kilo"
AGENT_TMP="$HOME/.tmpdir"

if [[ -L "$AGENT_TMP" ]]; then
  echo "ERROR: refusing symlink at $AGENT_TMP" >&2
  exit 1
fi
mkdir -p "$AGENT_TMP"
if [[ ! -O "$AGENT_TMP" ]]; then
  echo "ERROR: $AGENT_TMP must be owned by the current user." >&2
  exit 1
fi
chmod 700 "$AGENT_TMP"

# Prune agent scratch older than 14 days via the systemd user tmpfiles
# timer. Agent shell deletion is denied by policy, so this timer is the
# cleanup mechanism the workspace-temp rule refers to. Best-effort: the
# user manager must be running (linger is not enabled by default), so the
# timer fires during active deploy-user sessions.
TMPFILES_DIR="$HOME/.config/user-tmpfiles.d"
TMPFILES_CONF="$TMPFILES_DIR/kilo-agent-tmp.conf"
mkdir -p "$TMPFILES_DIR"
tmpfiles_content='d %h/.tmpdir 0700 - - 14d'
if [[ ! -f "$TMPFILES_CONF" ]] || ! printf '%s\n' "$tmpfiles_content" | cmp -s - "$TMPFILES_CONF"; then
  printf '%s\n' "$tmpfiles_content" > "$TMPFILES_CONF"
  echo "  deployed $(basename "$TMPFILES_CONF") (prune $AGENT_TMP older than 14d)"
fi
if systemctl --user enable --now systemd-tmpfiles-clean.timer >/dev/null 2>&1; then
  systemd-tmpfiles --user --create >/dev/null 2>&1 || true
else
  echo "  WARNING: systemd user manager unavailable; $AGENT_TMP will not be pruned automatically" >&2
fi

# Each step runs in a separate shell, so 36-kilo's nvm PATH does not carry
# over. Select the same Node version before validating the effective config.
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  echo "ERROR: nvm is not installed; run 35-node and 36-kilo first." >&2
  exit 1
fi
source "$NVM_DIR/nvm.sh" --no-use
nvm use --delete-prefix default >/dev/null
if ! command -v kilo >/dev/null 2>&1; then
  echo "ERROR: kilo CLI is not available; run 36-kilo first." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Ensure target dirs exist
# ---------------------------------------------------------------------------

mkdir -p "$KILO_CONFIG"
echo "Config dir: $KILO_CONFIG"

mkdir -p "$KILO_HOME"
echo "Kilo home dir: $KILO_HOME"

# ---------------------------------------------------------------------------
# 2. Deploy from _config/kilo/  -->  ~/.config/kilo/
# ---------------------------------------------------------------------------

echo "=== Deploying from _config/kilo/ to ~/.config/kilo/ ==="

for dir in agents commands rules; do
  if [[ -d "$SRC_CONFIG/$dir" ]]; then
    sync_dir_preserve "$SRC_CONFIG/$dir" "$KILO_CONFIG/$dir"
  else
    echo "  skipped $dir/ (not found in skeleton)"
  fi
done

# Retired context: the privilege-escalation rule file and the standards
# command (dead standards_search/standards_get MCP tools) were removed from
# the managed set. sync_dir_preserve never deletes, so remove stale copies
# on re-run to converge previously provisioned hosts.
rm -f "$KILO_CONFIG/rules/privilege-escalation.md"
rm -f "$KILO_CONFIG/commands/standards.md"

# ---------------------------------------------------------------------------
# 3. Deploy kilo.json / kilo.jsonc
# ---------------------------------------------------------------------------
# Kilo deep-merges kilo.json with kilo.jsonc. MCP server configuration lives in
# kilo.json; permissions such as permission.bash: allow live in kilo.jsonc.
#
# kilo.json is create-once because its MCP settings are locally customizable.
cfg_src="$SRC_CONFIG/kilo.json"
cfg_dst="$KILO_CONFIG/kilo.json"
if [[ ! -f "$cfg_src" ]]; then
  echo "  skipped kilo.json (not found in skeleton)"
elif [[ ! -f "$cfg_dst" ]]; then
  cp "$cfg_src" "$cfg_dst"
  echo "  deployed kilo.json (new)"
elif ! cmp -s "$cfg_src" "$cfg_dst"; then
    echo ""
    echo "  WARNING: skeleton kilo.json differs from $cfg_dst"
    echo "  Diff (skeleton -> live):"
    diff -u "$cfg_dst" "$cfg_src" || true
    echo ""
    echo "  Review the diff above and merge changes into $cfg_dst manually."
    echo "  This warning will appear on every re-run until the files match."
else
  echo "  kilo.json unchanged"
fi

# kilo.jsonc preserves local formatting and permissions while automatically
# migrating only the recognized policy subset. The helper validates the live
# effective config and rolls back atomically on failure.
cfg_src="$SRC_CONFIG/kilo.jsonc"
cfg_dst="$KILO_CONFIG/kilo.jsonc"
if [[ ! -f "$cfg_src" ]]; then
  echo "  skipped kilo.jsonc (not found in skeleton)"
elif ! "$STEP_DIR/migrate-kilo-jsonc.sh" "$cfg_src" "$cfg_dst"; then
  echo "  kilo.jsonc rejected; review the manual-merge guidance above." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 4. Deploy Bootstrap workspace indexing exclusions
# ---------------------------------------------------------------------------
# .kilocodeignore is workspace-scoped rather than global Kilo configuration.
# Preserve a locally customized file and show the diff for manual merging.
if [[ -f "$SRC_KILOCODEIGNORE" ]]; then
  dst="$BOOTSTRAP_ROOT/.kilocodeignore"
  if [[ ! -f "$dst" ]]; then
    cp "$SRC_KILOCODEIGNORE" "$dst"
    echo "  deployed .kilocodeignore (new)"
  elif ! cmp -s "$SRC_KILOCODEIGNORE" "$dst"; then
    echo ""
    echo "  WARNING: skeleton .kilocodeignore differs from $dst"
    echo "  Diff (live -> skeleton):"
    diff -u "$dst" "$SRC_KILOCODEIGNORE" || true
    echo ""
    echo "  Review the diff above and merge changes into $dst manually."
  else
    echo "  .kilocodeignore unchanged"
  fi
else
  echo "  skipped .kilocodeignore (not found in skeleton)"
fi

# ---------------------------------------------------------------------------
# 5. Deploy from _kilo/  -->  ~/.kilo/
# ---------------------------------------------------------------------------

echo "=== Deploying from _kilo/ to ~/.kilo/ ==="

if [[ -d "$SRC_KILO/skills" ]]; then
  if [[ ! -f "$OPTIONAL_SKILLS_FILE" ]]; then
    echo "ERROR: optional skill manifest is missing: $OPTIONAL_SKILLS_FILE" >&2
    exit 1
  fi
  if [[ ! -f "$DEFAULT_SKILLS_FILE" ]]; then
    echo "ERROR: default skill manifest is missing: $DEFAULT_SKILLS_FILE" >&2
    exit 1
  fi

  declare -A optional_skills=()
  while IFS= read -r skill; do
    [[ -n "$skill" && "$skill" != \#* ]] || continue
    if [[ ! -f "$SRC_KILO/skills/$skill/SKILL.md" ]]; then
      echo "ERROR: optional skill '$skill' has no source directory." >&2
      exit 1
    fi
    optional_skills["$skill"]=1
  done < "$OPTIONAL_SKILLS_FILE"

  declare -A default_skills=()
  while IFS= read -r skill; do
    [[ -n "$skill" && "$skill" != \#* ]] || continue
    if [[ -n "${optional_skills[$skill]+x}" ]]; then
      echo "ERROR: skill '$skill' is listed in both default and optional manifests." >&2
      exit 1
    fi
    if [[ ! -f "$SRC_KILO/skills/$skill/SKILL.md" ]]; then
      echo "ERROR: default skill '$skill' has no source directory." >&2
      exit 1
    fi
    default_skills["$skill"]=1
  done < "$DEFAULT_SKILLS_FILE"

  declare -A selected_optional_skills=()
  if [[ -n "${KILO_OPTIONAL_SKILLS:-}" ]]; then
    if [[ "$KILO_OPTIONAL_SKILLS" == "all" ]]; then
      for skill in "${!optional_skills[@]}"; do
        selected_optional_skills["$skill"]=1
      done
    else
      IFS=',' read -r -a requested_skills <<< "$KILO_OPTIONAL_SKILLS"
      for skill in "${requested_skills[@]}"; do
        if [[ -z "${optional_skills[$skill]+x}" ]]; then
          echo "ERROR: '$skill' is not an optional Kilo skill." >&2
          exit 1
        fi
        selected_optional_skills["$skill"]=1
      done
    fi
  fi

  for skill_dir in "$SRC_KILO/skills"/*; do
    [[ -f "$skill_dir/SKILL.md" ]] || continue
    skill="${skill_dir##*/}"
    if [[ -z "${optional_skills[$skill]+x}" && -z "${default_skills[$skill]+x}" ]]; then
      echo "ERROR: skill '$skill' is in neither default-skills.txt nor optional-skills.txt." >&2
      exit 1
    fi
    if [[ -n "${optional_skills[$skill]+x}" && -z "${selected_optional_skills[$skill]+x}" ]]; then
      echo "  skipped optional skill: $skill"
      continue
    fi
    sync_dir_preserve "$skill_dir" "$KILO_HOME/skills/$skill"
  done
else
  echo "  skipped skills/ (not found in skeleton)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "37-kilo-settings: context set deployed."
echo "  Agent scratch:    $AGENT_TMP (private, user-owned, pruned >14d via user tmpfiles timer)"
echo "  ~/.config/kilo/:  agents/ commands/ rules/ kilo.json (MCP) kilo.jsonc"
echo "  ~/.kilo/:         skills/"
echo "  Optional skills:  KILO_OPTIONAL_SKILLS=all or a comma-separated skill list"
echo "  Bootstrap:        $BOOTSTRAP_ROOT/.kilocodeignore"
echo "  Playwright MCP seed: npx @playwright/mcp (check live kilo.json for existing configs)"
echo ""
echo "Restart kilo (or reload config) to pick up the new context."
