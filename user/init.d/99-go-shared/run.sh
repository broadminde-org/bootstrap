#!/usr/bin/env bash
set -euo pipefail

# 99-go-shared - read-only access to broadminde-org/go-shared.
#
# This step runs as the deploy user. The private key is generated locally and
# must be registered manually as a read-only deploy key on go-shared.
#
# Also deploys the go-shared-access agent skill (kilo/skills/ →
# ~/.kilo/skills/). The skill lives with this step — not in 37-kilo-settings —
# because it documents go-shared module access, which this step provisions.

# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

readonly SSH_DIR="$HOME/.ssh"
readonly KEY_PATH="$SSH_DIR/go-shared-read"
readonly HOSTS_DIR="$SSH_DIR/hosts.d"
readonly HOST_CONFIG="$HOSTS_DIR/github-go-shared.conf"
readonly KNOWN_HOSTS="$SSH_DIR/known_hosts-go-shared"
readonly REPO="broadminde-org/go-shared"
readonly ALIAS="github-go-shared"

# Deploy the go-shared-access agent skill (~/.kilo/skills/). Plain files with
# no dependency on the deploy key, so a host whose key is not yet registered
# still gets the context. sync_dir_preserve never deletes.
sync_dir_preserve "$(dirname "$0")/kilo/skills" "$HOME/.kilo/skills"

mkdir -p "$SSH_DIR" "$HOSTS_DIR"
chmod 700 "$SSH_DIR" "$HOSTS_DIR"

if [[ ! -f "$KEY_PATH" ]]; then
  command -v ssh-keygen >/dev/null 2>&1 || {
    echo "ERROR: ssh-keygen is required to create $KEY_PATH" >&2
    exit 1
  }
  echo "Generating read-only go-shared deploy key at $KEY_PATH"
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "go-shared-read@$(hostname)"
fi
chmod 600 "$KEY_PATH"
[[ -f "${KEY_PATH}.pub" ]] || ssh-keygen -y -f "$KEY_PATH" > "${KEY_PATH}.pub"
chmod 644 "${KEY_PATH}.pub"

# GitHub publishes the host keys through its authenticated HTTPS API. Use that
# source rather than accepting an arbitrary first SSH connection.
command -v curl >/dev/null 2>&1 || {
  echo "ERROR: curl is required to provision GitHub known_hosts" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "ERROR: jq is required to provision GitHub known_hosts" >&2
  exit 1
}

tmp_known_hosts="$(mktemp)"
trap 'rm -f "$tmp_known_hosts"' EXIT
curl --fail --silent --show-error --proto '=https' --tlsv1.2 \
  https://api.github.com/meta \
  | jq -r '.ssh_keys[] | "github.com " + .' > "$tmp_known_hosts"

if [[ ! -s "$tmp_known_hosts" ]]; then
  echo "ERROR: GitHub API returned no SSH host keys" >&2
  exit 1
fi
install -m 600 "$tmp_known_hosts" "$KNOWN_HOSTS"

cat > "$HOST_CONFIG" <<EOF
# Managed by bootstrap/user/init.d/99-go-shared/run.sh — do not edit by hand.
Host $ALIAS
    HostName github.com
    User git
    IdentityFile $KEY_PATH
    IdentitiesOnly yes
    UserKnownHostsFile $KNOWN_HOSTS
    StrictHostKeyChecking yes
    # Distinct ControlPath: sharing cm-%r@%h:%p with plain github.com would let
    # a personal-key master get reused by this alias, silently authenticating
    # with the wrong identity and masking a missing deploy-key registration.
    ControlPath ~/.ssh/cm-go-shared-%r@%h:%p
EOF
chmod 644 "$HOST_CONFIG"

# The drop-in only takes effect if ~/.ssh/config loads ~/.ssh/hosts.d/*.
# Verify the alias resolves rather than let ssh fall back to a personal key,
# which would mask a missing deploy key and bypass the dedicated key entirely.
if ! ssh -G "$ALIAS" 2>/dev/null | grep -qx 'hostname github.com'; then
  echo "ERROR: the $ALIAS SSH alias is not active." >&2
  echo "Ensure ~/.ssh/config contains 'Include ~/.ssh/hosts.d/*'" >&2
  echo "(re-run the root-tier 56-ssh-client step to add it)." >&2
  exit 1
fi

# Route go-shared through the dedicated deploy-key alias. This rewrite is more
# specific than any org-wide rewrite, so it wins for this repo regardless of
# what other url.*.insteadOf entries exist. This step manages go-shared only —
# no other broadminde-org repo is configured here.
git config --global url."git@$ALIAS:$REPO".insteadOf \
  "https://github.com/$REPO"

# Keep the private-module scope explicit for non-interactive Go commands.
git config --global --get \
  "url.git@$ALIAS:$REPO.insteadof" | grep -qxF "https://github.com/$REPO" || {
  echo "ERROR: failed to install the go-shared Git URL rewrite" >&2
  exit 1
}

if command -v go >/dev/null 2>&1; then
  go env -w GOPRIVATE='github.com/broadminde-org/*'
fi

echo "Verifying read-only access to $REPO"
if ! timeout 15 git ls-remote "git@$ALIAS:$REPO.git" HEAD >/dev/null 2>&1; then
  echo "" >&2
  echo "ACTION REQUIRED: cannot read $REPO with the dedicated deploy key." >&2
  echo "" >&2
  echo "Register this public key as a read-only deploy key at:" >&2
  echo "  https://github.com/broadminde-org/go-shared/settings/keys" >&2
  echo "" >&2
  echo "Public key (${KEY_PATH}.pub):" >&2
  cat "${KEY_PATH}.pub" >&2
  echo "" >&2
  echo "Then re-run this step to complete verification." >&2
  exit 1
fi

echo "go-shared access configured and verified."
