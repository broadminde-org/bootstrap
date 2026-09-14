#!/usr/bin/env bash
# Provision the unprivileged host account used by Woodpecker's local backend.

set -euo pipefail

WOODPECKER_USER="woodpecker"
WOODPECKER_HOME="/var/lib/woodpecker"
BOOTSTRAP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WOODPECKER_CLI_VERSION="${WOODPECKER_CLI_VERSION:-v3.17.0}"
PLUGIN_GIT_VERSION="${PLUGIN_GIT_VERSION:-2.10.0}"

if ! id "$WOODPECKER_USER" >/dev/null 2>&1; then
  useradd --system --create-home --home-dir "$WOODPECKER_HOME" \
    --shell /usr/sbin/nologin "$WOODPECKER_USER"
fi

install -d -m 0750 -o "$WOODPECKER_USER" -g "$WOODPECKER_USER" \
  "$WOODPECKER_HOME" "$WOODPECKER_HOME/.ssh" "$WOODPECKER_HOME/.cache"
chmod 0700 "$WOODPECKER_HOME/.ssh"

# The deploy key is intentionally not copied or generated here. Operators add
# a new read-only key for the github-go-shared alias separately.
cat > "$WOODPECKER_HOME/.ssh/config" <<'EOF'
Host github-go-shared
    HostName github.com
    User git
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
EOF
chown "$WOODPECKER_USER:$WOODPECKER_USER" "$WOODPECKER_HOME/.ssh/config"
chmod 0600 "$WOODPECKER_HOME/.ssh/config"

# Install the generic runner and toolchains through the same user-tier source
# used for luke. Each step runs as woodpecker, never as root.
for step in 20-python 25-go 35-node 30-scripts 38-woodpecker-cli; do
  runuser -u "$WOODPECKER_USER" -- env HOME="$WOODPECKER_HOME" \
    BOOTSTRAP_CONFIG_FILE="$BOOTSTRAP_ROOT/bootstrap.conf.yml" \
    bash -lc "cd '$BOOTSTRAP_ROOT/user' && ./init.sh '$step'"
done

# plugin-git is required by the local backend's default clone step.
if ! command -v plugin-git >/dev/null 2>&1; then
  plugin_url="https://github.com/woodpecker-ci/plugin-git/releases/download/${PLUGIN_GIT_VERSION}/linux-amd64_plugin-git"
  curl -fsSL "$plugin_url" -o /usr/local/bin/plugin-git
  chmod 0755 /usr/local/bin/plugin-git
fi

echo "Woodpecker local-backend user provisioned: $WOODPECKER_USER"
