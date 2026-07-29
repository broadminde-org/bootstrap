#!/usr/bin/env bash
# Install agent skills via npx skills CLI.
#
# User tier: runs as the deploy user (non-root).
# Depends on node/npx from 35-node.
#
# Idempotent: npx skills handles its own dedup; repeated runs are safe.

set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

if ! command -v npx >/dev/null 2>&1; then
  echo "ERROR: npx not found — 35-node must run before 40-npx-skills." >&2
  exit 1
fi

export DISABLE_TELEMETRY=1

npx --yes skills add cxuu/golang-skills -g -y --all
npx --yes skills add https://github.com/mattpocock/skills --skill handoff -g -y
npx --yes skills add https://github.com/mattpocock/skills --skill design-an-interface
npx --yes skills add https://github.com/github/awesome-copilot --skill python-mcp-server-generator
npx --yes skills add https://github.com/wshobson/agents --skill async-python-patterns