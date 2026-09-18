#!/usr/bin/env bash
# Provision the unprivileged host account used by Woodpecker's local backend.

# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/conf.sh"

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
SSH_CONFIG_NEW='# Managed by bootstrap/init.d/45-woodpecker-local.
Host github-go-shared
    HostName github.com
    User git
    IdentitiesOnly yes
'
if [[ -f "$WOODPECKER_HOME/.ssh/config" ]] \
  && [[ "$(cat "$WOODPECKER_HOME/.ssh/config")" == "$SSH_CONFIG_NEW" ]]; then
  echo "ok: $WOODPECKER_HOME/.ssh/config (unchanged)"
else
  printf '%s' "$SSH_CONFIG_NEW" > "$WOODPECKER_HOME/.ssh/config"
  chown "$WOODPECKER_USER:$WOODPECKER_USER" "$WOODPECKER_HOME/.ssh/config"
  chmod 0600 "$WOODPECKER_HOME/.ssh/config"
  echo "Wrote $WOODPECKER_HOME/.ssh/config"
fi

# Seed GitHub's published host keys (https://api.github.com/meta,
# ssh_keys) instead of StrictHostKeyChecking accept-new — a CI account
# must never trust-on-first-use.
KNOWN_HOSTS_NEW='# Managed by bootstrap/init.d/45-woodpecker-local — GitHub published host keys.
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk='
if [[ -f "$WOODPECKER_HOME/.ssh/known_hosts" ]] \
  && [[ "$(cat "$WOODPECKER_HOME/.ssh/known_hosts")" == "$KNOWN_HOSTS_NEW" ]]; then
  echo "ok: $WOODPECKER_HOME/.ssh/known_hosts (unchanged)"
else
  printf '%s\n' "$KNOWN_HOSTS_NEW" > "$WOODPECKER_HOME/.ssh/known_hosts"
  chown "$WOODPECKER_USER:$WOODPECKER_USER" "$WOODPECKER_HOME/.ssh/known_hosts"
  chmod 0600 "$WOODPECKER_HOME/.ssh/known_hosts"
  echo "Wrote $WOODPECKER_HOME/.ssh/known_hosts (GitHub published host keys)"
fi

# Install the generic runner and toolchains through the same user-tier source
# used for the deploy user. Each step runs as woodpecker, never as root.
# BOOTSTRAP_CONFIG_FILE is inherited from the runner (hostname override
# included); fall back to resolving it here when the step runs standalone.
CHILD_CONF="${BOOTSTRAP_CONFIG_FILE:-$(resolve_conf_file || true)}"
for step in 20-python 25-go 35-node 30-scripts 38-woodpecker-cli; do
  runuser -u "$WOODPECKER_USER" -- env HOME="$WOODPECKER_HOME" \
    BOOTSTRAP_CONFIG_FILE="$CHILD_CONF" \
    bash -lc "cd '$BOOTSTRAP_ROOT/user' && ./init.sh '$step'"
done

# plugin-git is required by the local backend's default clone step.
# Verified against the upstream release checksums (SHA256 pinned per
# arch); an installed binary whose checksum differs is REINSTALLED —
# the version pin is real, not a one-shot gate.
case "$(uname -m)" in
  x86_64)  plugin_asset="linux-amd64_plugin-git"
           plugin_sha256="be3c3fa5363ddaff0dac88c2dc5b745ca785f21d5554f90b47d132d34baebcec" ;;
  aarch64) plugin_asset="linux-arm64_plugin-git"
           plugin_sha256="61c9f28d70b4eba433d3abcebfe00b177243fc39ed0da1cd4d7d308bb0588782" ;;
  *) echo "ERROR: unsupported architecture for plugin-git: $(uname -m)" >&2; exit 1 ;;
esac

plugin_bin=/usr/local/bin/plugin-git
if [[ -x "$plugin_bin" ]] \
  && [[ "$(sha256sum "$plugin_bin" | awk '{print $1}')" == "$plugin_sha256" ]]; then
  echo "plugin-git ${PLUGIN_GIT_VERSION} already installed (${plugin_bin})"
else
  plugin_url="https://github.com/woodpecker-ci/plugin-git/releases/download/${PLUGIN_GIT_VERSION}/${plugin_asset}"
  tmp_plugin="$(mktemp)"
  trap 'rm -f "$tmp_plugin"' EXIT
  curl -fsSL --retry 3 "$plugin_url" -o "$tmp_plugin"
  actual_sha="$(sha256sum "$tmp_plugin" | awk '{print $1}')"
  if [[ "$actual_sha" != "$plugin_sha256" ]]; then
    echo "ERROR: plugin-git checksum mismatch (got $actual_sha, want $plugin_sha256)" >&2
    exit 1
  fi
  install -m 0755 "$tmp_plugin" "$plugin_bin"
  rm -f "$tmp_plugin"
  trap - EXIT
  echo "Installed plugin-git ${PLUGIN_GIT_VERSION} (${plugin_asset})"
fi

echo "Woodpecker local-backend user provisioned: $WOODPECKER_USER"
