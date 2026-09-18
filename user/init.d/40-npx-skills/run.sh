#!/usr/bin/env bash
# Install agent skills via npx skills CLI.
#
# User tier: runs as the deploy user (non-root).
# Depends on node/npx from 35-node.
#
# Idempotent: npx skills handles its own dedup; repeated runs are safe.
# Keep the target list explicit. Omitting --agent makes the CLI auto-detect
# installed agents and can populate every detected agent's skills directory.

set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

# Non-interactive invocations (ssh, cron) do not source ~/.bashrc, where
# nvm is normally wired up — load it explicitly, same as 98-npm-shared.
if ! command -v npx >/dev/null 2>&1 && [[ -s "$HOME/.nvm/nvm.sh" ]]; then
  # shellcheck disable=SC1091
  . "$HOME/.nvm/nvm.sh" --no-use
  nvm use default >/dev/null
fi

if ! command -v npx >/dev/null 2>&1; then
  echo "ERROR: npx not found — 35-node must run before 40-npx-skills." >&2
  exit 1
fi

export DISABLE_TELEMETRY=1

# The skills CLI shells out to `git clone`. The user's global git config may
# rewrite https://github.com/ URLs to ssh (url.<base>.insteadOf); when ssh to
# github.com hangs (egress firewall, missing key), every clone stalls until
# the CLI's 300s timeout. All repos below are public, so bypass the global
# git config entirely and clone over plain https.
export GIT_CONFIG_GLOBAL=/dev/null

# Kilo Code / Kilo CLI use the `kilo` target. Add another supported agent to
# skills.agents in bootstrap.conf.yml only when this host intentionally
# provisions that agent as well (for example: "kilo opencode").
read -r -a SKILLS_AGENTS <<< "$(get_skills_conf agents kilo)"
if (( ${#SKILLS_AGENTS[@]} == 0 )); then
  echo "ERROR: skills.agents must contain at least one npx skills agent target." >&2
  exit 1
fi

# General

npx --yes skills add https://github.com/mattpocock/skills \
  --skill \
    handoff \
    codebase-design \
    improve-codebase-architecture \
    grill-with-docs \
    domain-modeling \
    research \
  -g -a "${SKILLS_AGENTS[@]}" -y

npx --yes skills add https://github.com/anthropics/skills \
  --skill \
    frontend-design \
  -g -a "${SKILLS_AGENTS[@]}" -y

npx --yes skills add https://github.com/addyosmani/agent-skills \
  --skill \
    frontend-ui-engineering \
  -g -a "${SKILLS_AGENTS[@]}" -y

# Python
# npx --yes skills add https://github.com/github/awesome-copilot --skill python-mcp-server-generator -g -y
# npx --yes skills add https://github.com/wshobson/agents --skill async-python-patterns -g -y

# Svelte
