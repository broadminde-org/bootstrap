#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 10-create-deploy-user — Create the non-root deploy user.
#
# The fresh cloud VPS only has `root`. Every later step assumes a
# non-root account with `sudo` membership, so this step must run
# before any step that hands off to a user (10-groups, 30-passwordless-
# sudo, 50-docker group add, 55-lazydocker install into $HOME, …).
#
# Behaviour mirrors the old bootstrap.sh:
#   - BOOTSTRAP_USER / BOOTSTRAP_PASSWORD env vars preferred.
#   - Falls back to interactive prompts (password via `read -s`).
#   - Idempotent: existing users are left alone; sudo group is
#     enforced; the password is always (re)applied.
#
# Run as root (sudo ./init.sh 10-create-deploy-user).
#
# Auto-skip when running via sudo: if the script has a SUDO_USER,
# the admin is already a real user and doesn't need a deploy account
# created for them.  This handles the case where someone is running
# bootstrap on an existing machine.

if [[ -n "${SUDO_USER:-}" ]]; then
  echo "==> Detected sudo (caller: ${SUDO_USER}) — skipping deploy-user creation."
  echo "    Subsequent steps will operate on SUDO_USER (${SUDO_USER})."
  exit 0
fi

# If invoked via sudo from a non-root account, a deploy user already
# exists — skip the creation step entirely.
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  echo "==> Running as sudo from '${SUDO_USER}' — deploy user already exists, skipping."
  exit 0
fi

set +e
if [[ -z "${BOOTSTRAP_USER:-}" ]]; then
  read -r -p "Username for the deploy account (leave blank to skip): " BOOTSTRAP_USER
fi
set -e

if [[ -z "${BOOTSTRAP_USER:-}" ]]; then
  echo "==> No deploy username provided — skipping deploy-user creation."
  echo "    Subsequent steps will operate on SUDO_USER (${SUDO_USER:-unset})."
  exit 0
fi

set +e
if [[ -z "${BOOTSTRAP_PASSWORD:-}" ]]; then
  read -s -p "Password for ${BOOTSTRAP_USER}: " BOOTSTRAP_PASSWORD
  echo
fi
set -e

if [[ -z "${BOOTSTRAP_PASSWORD:-}" ]]; then
  echo "ERROR: BOOTSTRAP_PASSWORD must be non-empty when BOOTSTRAP_USER is set" >&2
  exit 1
fi

if id "$BOOTSTRAP_USER" >/dev/null 2>&1; then
  echo "==> User '${BOOTSTRAP_USER}' already exists -- ensuring sudo group membership"
  usermod -aG sudo "$BOOTSTRAP_USER"
else
  echo "==> Creating user '${BOOTSTRAP_USER}'"
  useradd -m -s /bin/bash -G sudo "$BOOTSTRAP_USER"
fi

printf '%s:%s\n' "$BOOTSTRAP_USER" "$BOOTSTRAP_PASSWORD" | chpasswd
unset BOOTSTRAP_PASSWORD

echo "==> Done."
echo "    User : ${BOOTSTRAP_USER}"
echo "    Group: sudo"
echo "    Next : log out and back in as ${BOOTSTRAP_USER}, then re-run subsequent init steps without sudo."
