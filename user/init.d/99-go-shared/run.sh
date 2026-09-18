#!/usr/bin/env bash
set -euo pipefail

# 99-go-shared - read-only access to Broadminde private shared repositories.
#
# This step runs as the deploy user. Each repository gets its own private key.
# When gh is authenticated with permission to administer the repositories, the
# step registers the public keys as read-only deploy keys through the GitHub
# API. Otherwise it falls back to printing the manual registration instructions.
#
# Also deploys the go-shared-access agent skill (kilo/skills/ →
# ~/.kilo/skills/). The frontend-shared skill is owned by 98-npm-shared;
# this step still provisions its SSH source-repository access.

# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

readonly SSH_DIR="$HOME/.ssh"
readonly HOSTS_DIR="$SSH_DIR/hosts.d"

# Deploy the go-shared-access agent skill (~/.kilo/skills/). Plain files with
# no dependency on the deploy key, so a host whose key is not yet registered
# still gets the context. sync_dir_preserve never deletes.
sync_dir_preserve "$(dirname "$0")/kilo/skills" "$HOME/.kilo/skills"

mkdir -p "$SSH_DIR" "$HOSTS_DIR"
chmod 700 "$SSH_DIR" "$HOSTS_DIR"

command -v ssh-keygen >/dev/null 2>&1 || {
  echo "ERROR: ssh-keygen is required to create shared-repository deploy keys" >&2
  exit 1
}

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

register_deploy_key_with_gh() {
  local repo="$1"
  local key_name="$2"
  local key_path="$3"
  local public_key title keys_json existing_title existing_read_only

  command -v gh >/dev/null 2>&1 || return 1
  gh auth status --hostname github.com >/dev/null 2>&1 || return 1

  public_key="$(<"${key_path}.pub")"
  title="$key_name@$(hostname)"

  if ! keys_json="$(gh api "repos/$repo/keys" --paginate)"; then
    echo "gh could not list deploy keys for $repo; manual registration may be required." >&2
    return 1
  fi

  existing_title="$(jq -rs --arg key "$public_key" \
    'flatten | map(select(.key == $key)) | .[0].title // empty' <<<"$keys_json")"
  existing_read_only="$(jq -rs --arg key "$public_key" \
    'flatten | map(select(.key == $key)) | .[0].read_only // empty' <<<"$keys_json")"

  if [[ -n "$existing_title" ]]; then
    if [[ "$existing_read_only" == "true" ]]; then
      echo "Deploy key for $repo is already registered read-only (title: $existing_title)."
    else
      echo "ERROR: deploy key for $repo is already registered but is not read-only (title: $existing_title)." >&2
      echo "Change it to read-only at https://github.com/$repo/settings/keys." >&2
      return 1
    fi
    return 0
  fi

  echo "Registering read-only deploy key for $repo through gh ($title)"
  if ! gh api "repos/$repo/keys" --method POST \
    -f title="$title" \
    -f key="$public_key" \
    -F read_only=true >/dev/null; then
    echo "gh could not create the deploy key for $repo." >&2
    echo "The authenticated GitHub account needs permission to administer repository deploy keys." >&2
    return 1
  fi
}

configure_repo_access() {
  local repo="$1"
  local alias="$2"
  local key_name="$3"
  local key_path="$SSH_DIR/$key_name"
  local host_config="$HOSTS_DIR/$alias.conf"
  local known_hosts="$SSH_DIR/known_hosts-$key_name"

  if [[ ! -f "$key_path" ]]; then
    echo "Generating read-only deploy key for $repo at $key_path"
    ssh-keygen -t ed25519 -f "$key_path" -N "" -C "$key_name@$(hostname)"
  fi
  chmod 600 "$key_path"
  [[ -f "${key_path}.pub" ]] || ssh-keygen -y -f "$key_path" > "${key_path}.pub"
  chmod 644 "${key_path}.pub"

  install -m 600 "$tmp_known_hosts" "$known_hosts"

  cat > "$host_config" <<EOF
# Managed by bootstrap/user/init.d/99-go-shared/run.sh — do not edit by hand.
Host $alias
    HostName github.com
    User git
    IdentityFile $key_path
    IdentitiesOnly yes
    UserKnownHostsFile $known_hosts
    StrictHostKeyChecking yes
    # Never share a ControlPath with plain github.com: doing so can reuse a
    # personal-key master and mask a missing deploy-key registration.
    ControlPath ~/.ssh/cm-$key_name-%r@%h:%p
EOF
  chmod 644 "$host_config"

  # The drop-in only takes effect if ~/.ssh/config loads ~/.ssh/hosts.d/*.
  if ! ssh -G "$alias" 2>/dev/null | grep -qx 'hostname github.com'; then
    echo "ERROR: the $alias SSH alias is not active." >&2
    echo "Ensure ~/.ssh/config contains 'Include ~/.ssh/hosts.d/*'" >&2
    echo "(re-run the root-tier 56-ssh-client step to add it)." >&2
    exit 1
  fi

  # Keep this rewrite exact to one repository. It wins over any broader
  # organization rewrite by longest-match precedence.
  git config --global url."git@$alias:$repo".insteadOf "https://github.com/$repo"
  git config --global --get "url.git@$alias:$repo.insteadof" \
    | grep -qxF "https://github.com/$repo" || {
    echo "ERROR: failed to install the Git URL rewrite for $repo" >&2
    exit 1
  }

  if command -v gh >/dev/null 2>&1 && gh auth status --hostname github.com >/dev/null 2>&1; then
    register_deploy_key_with_gh "$repo" "$key_name" "$key_path" || true
  fi

  echo "Verifying read-only access to $repo"
  local verified=1
  local attempt
  for attempt in 1 2 3; do
    if timeout 15 git ls-remote "git@$alias:$repo.git" HEAD >/dev/null 2>&1; then
      verified=0
      break
    fi
    [[ "$attempt" -lt 3 ]] && sleep 2
  done

  if [[ "$verified" -ne 0 ]]; then
    echo "" >&2
    echo "ACTION REQUIRED: cannot read $repo with the dedicated deploy key." >&2
    echo "" >&2
    echo "If gh could not register the key automatically, add it as a read-only" >&2
    echo "deploy key at:" >&2
    echo "  https://github.com/$repo/settings/keys" >&2
    echo "" >&2
    echo "Public key (${key_path}.pub):" >&2
    cat "${key_path}.pub" >&2
    echo "" >&2
    echo "Then re-run this step or run: ~/scripts/github-access deploy-keys" >&2
    exit 1
  fi
}

configure_repo_access \
  "broadminde-org/go-shared" \
  "github-go-shared" \
  "go-shared-read"

configure_repo_access \
  "broadminde-org/frontend-shared" \
  "github-frontend-shared" \
  "frontend-shared-read"

# Keep the private-module scope explicit for non-interactive Go commands.
# Merge into any existing GOPRIVATE — never wholesale-overwrite entries
# the user added for other private hosts.

if command -v go >/dev/null 2>&1; then
  current_goprivate="$(go env GOPRIVATE)"
  case ",$current_goprivate," in
    *,github.com/broadminde-org/\*,*) ;;
    *) go env -w GOPRIVATE="${current_goprivate:+$current_goprivate,}github.com/broadminde-org/*" ;;
  esac
fi

echo "Broadminde shared-repository access configured and verified."
