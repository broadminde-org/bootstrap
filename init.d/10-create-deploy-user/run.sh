#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 10-create-deploy-user — Create the non-root deploy user.
#
# The fresh cloud VPS only has `root`. Every later step assumes a
# non-root account with `sudo` membership, so this step must run first:
# as root on the fresh host, `./init.sh 10`, then log in as the deploy
# user and run the rest via `sudo ./init.sh` (see README quick start).
#
# Parameters (first source wins):
#   1. environment variables  BOOTSTRAP_USER / BOOTSTRAP_PASSWORD /
#      BOOTSTRAP_SSH_PUBKEY
#   2. the repo-root .env     (gitignored; read via lib/common.sh's
#      env_file_value — parsed, never sourced, so a malicious .env
#      cannot execute shell)
#   3. interactive prompts    — the deliberate exception to the
#      non-interactive rule, for first-run credential entry. Prompts
#      only fire on a TTY; otherwise the step fails loudly with
#      instructions.
#
# A deploy user needs at least one working login path before
# 51-ssh-hardening will disable root login: a password OR an enrolled
# SSH public key (BOOTSTRAP_SSH_PUBKEY, installed append-if-absent
# into ~/.ssh/authorized_keys, 0700/0600, correct ownership).
#
# Idempotent: an existing non-system user is left in place; sudo group
# membership is enforced; the password is (re)applied when provided.
#
# Auto-skip: when a real non-root user invoked sudo and no different
# BOOTSTRAP_USER was requested, that account already IS the deploy
# user (bootstrap on an existing machine) — creation is skipped.
#
# Run as root (./init.sh 10-create-deploy-user).

ENV_FILE="$EE_ROOT/.env"

BOOTSTRAP_USER="${BOOTSTRAP_USER:-$(env_file_value BOOTSTRAP_USER || true)}"
BOOTSTRAP_PASSWORD="${BOOTSTRAP_PASSWORD:-$(env_file_value BOOTSTRAP_PASSWORD || true)}"
BOOTSTRAP_SSH_PUBKEY="${BOOTSTRAP_SSH_PUBKEY:-$(env_file_value BOOTSTRAP_SSH_PUBKEY || true)}"

# Skip creation only when a real non-root human invoked sudo and no
# different deploy user was requested — that account IS the deploy user.
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" && "${SUDO_USER}" != "${BOOTSTRAP_USER}" ]]; then
  echo "==> Running via sudo from '${SUDO_USER}' — that account is the deploy user; skipping creation."
  exit 0
fi

if [[ -z "${BOOTSTRAP_USER:-}" && -t 0 ]]; then
  read -r -p "Username for the deploy account (leave blank to skip): " BOOTSTRAP_USER
fi

if [[ -z "${BOOTSTRAP_USER:-}" ]]; then
  echo "==> No deploy username provided — skipping deploy-user creation."
  echo "    Set BOOTSTRAP_USER in $ENV_FILE (or the environment) to create one."
  exit 0
fi

# Validate strictly BEFORE the name touches useradd/chpasswd — a newline
# in the name would let chpasswd set a second account's password.
if [[ ! "$BOOTSTRAP_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  echo "ERROR: invalid BOOTSTRAP_USER '${BOOTSTRAP_USER}'." >&2
  echo "       Must match ^[a-z_][a-z0-9_-]{0,31}\$ (POSIX account name)." >&2
  exit 1
fi

# `root` passes the regex above — refuse it explicitly.
if [[ "$BOOTSTRAP_USER" == "root" ]]; then
  echo "ERROR: refusing to use 'root' as the deploy user." >&2
  exit 1
fi

if [[ -z "${BOOTSTRAP_PASSWORD:-}" && -z "${BOOTSTRAP_SSH_PUBKEY:-}" && -t 0 ]]; then
  read -r -s -p "Password for ${BOOTSTRAP_USER} (leave blank for key-only): " BOOTSTRAP_PASSWORD
  echo
fi

if [[ -z "${BOOTSTRAP_PASSWORD:-}" && -z "${BOOTSTRAP_SSH_PUBKEY:-}" ]]; then
  echo "ERROR: provide BOOTSTRAP_PASSWORD or BOOTSTRAP_SSH_PUBKEY (env or .env)." >&2
  echo "       The deploy user needs at least one working login path before" >&2
  echo "       51-ssh-hardening disables root login." >&2
  exit 1
fi

if id "$BOOTSTRAP_USER" >/dev/null 2>&1; then
  uid="$(id -u "$BOOTSTRAP_USER")"
  # A pre-existing UID < 1000 account is a system account (bootstrap
  # creates deploy users with useradd, which allocates >= 1000) —
  # adopting one would hand system resources to the deploy user.
  if (( uid < 1000 )); then
    echo "ERROR: '${BOOTSTRAP_USER}' already exists with UID ${uid} (< 1000)." >&2
    echo "       That is a system account — refusing to adopt it as the" >&2
    echo "       deploy user. Choose a different BOOTSTRAP_USER." >&2
    exit 1
  fi
  echo "==> User '${BOOTSTRAP_USER}' already exists -- ensuring sudo group membership"
  usermod -aG sudo "$BOOTSTRAP_USER"
else
  echo "==> Creating user '${BOOTSTRAP_USER}'"
  useradd -m -s /bin/bash -G sudo "$BOOTSTRAP_USER"
fi

if [[ -n "${BOOTSTRAP_PASSWORD:-}" ]]; then
  printf '%s:%s\n' "$BOOTSTRAP_USER" "$BOOTSTRAP_PASSWORD" | chpasswd
  unset BOOTSTRAP_PASSWORD
  echo "==> Password (re)applied for ${BOOTSTRAP_USER}"
fi

# Enroll the SSH public key (idempotent: append-if-absent).
if [[ -n "${BOOTSTRAP_SSH_PUBKEY:-}" ]]; then
  DEPLOY_HOME="$(getent passwd "$BOOTSTRAP_USER" | cut -d: -f6)"
  SSH_DIR="$DEPLOY_HOME/.ssh"
  AUTH_KEYS="$SSH_DIR/authorized_keys"
  install -m 0700 -o "$BOOTSTRAP_USER" -g "$(id -gn "$BOOTSTRAP_USER")" -d "$SSH_DIR"
  if [[ ! -f "$AUTH_KEYS" ]]; then
    install -m 0600 -o "$BOOTSTRAP_USER" -g "$(id -gn "$BOOTSTRAP_USER")" /dev/null "$AUTH_KEYS"
  fi
  if grep -qxF "$BOOTSTRAP_SSH_PUBKEY" "$AUTH_KEYS"; then
    echo "==> SSH public key already enrolled for ${BOOTSTRAP_USER}"
  else
    printf '%s\n' "$BOOTSTRAP_SSH_PUBKEY" >> "$AUTH_KEYS"
    echo "==> Enrolled SSH public key for ${BOOTSTRAP_USER} (${AUTH_KEYS})"
  fi
fi

echo "==> Done."
echo "    User : ${BOOTSTRAP_USER}"
echo "    Group: sudo"
echo "    Next : log in as ${BOOTSTRAP_USER}, then run the remaining root-tier"
echo "           steps WITH sudo (sudo ./init.sh) followed by the user tier"
echo "           (cd user && ./init.sh)."
