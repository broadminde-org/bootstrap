#!/usr/bin/env bash
#
# bootstrap.sh -- initial provisioning for a fresh Digital Ocean VPS.
#
# Target OS  : Debian 13 (trixie).
# Privileges : MUST be run as root.
# Network    : apt repositories must be reachable; no other external
#              fetches are performed by this script.
#
# What it does (in order):
#   1. Runs `apt-get update` and `apt-get upgrade -y`.
#   2. Installs a small, defensible baseline of packages:
#        git, curl, wget, vim, htop, unzip, ca-certificates, sudo
#   3. Creates a non-root user account with a home directory and bash
#      shell, adds them to the `sudo` group, and sets the initial
#      password non-interactively via chpasswd.
#
# Invocation:
#   # Interactive (prompts for username + password):
#   sudo ./bootstrap.sh
#
#   # Non-interactive (preferred for automation):
#   sudo BOOTSTRAP_USER=luke BOOTSTRAP_PASSWORD='s3cret' ./bootstrap.sh
#
#   # Or, when already running as root on the fresh VPS:
#   BOOTSTRAP_USER=luke BOOTSTRAP_PASSWORD='s3cret' ./bootstrap.sh
#
# Idempotency:
#   Re-running is safe. If the target user already exists, the script
#   leaves them alone but still ensures `sudo` group membership and
#   still (re)applies the supplied password.
#
# Out of scope (intentionally NOT included -- add later as needed):
#   SSH key installation, firewall (ufw/iptables), hostname changes,
#   timezone configuration, fail2ban, Docker, dotfiles, backups.

set -euo pipefail

# --- Sanity checks -------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: this script must be run as root (try: sudo $0)" >&2
  exit 1
fi

# --- Resolve credentials -------------------------------------------------
# Prefer env vars (set by the caller / CI). Fall back to an interactive
# prompt. The password prompt uses `read -s` so it is never echoed.

if [[ -z "${BOOTSTRAP_USER:-}" ]]; then
  read -r -p "Username for the new account: " BOOTSTRAP_USER
fi

if [[ -z "${BOOTSTRAP_PASSWORD:-}" ]]; then
  read -s -p "Password for ${BOOTSTRAP_USER}: " BOOTSTRAP_PASSWORD
  echo
fi

if [[ -z "$BOOTSTRAP_USER" || -z "$BOOTSTRAP_PASSWORD" ]]; then
  echo "ERROR: username and password must both be non-empty" >&2
  exit 1
fi

# --- apt update + upgrade -----------------------------------------------

echo "==> apt-get update"
apt-get update

echo "==> apt-get upgrade -y"
apt-get upgrade -y

# --- Install baseline packages ------------------------------------------

echo "==> Installing baseline packages"
apt-get install -y \
  git \
  curl \
  wget \
  vim \
  htop \
  unzip \
  ca-certificates \
  sudo

# --- Create the user (idempotent) ---------------------------------------

if id "$BOOTSTRAP_USER" >/dev/null 2>&1; then
  echo "==> User '${BOOTSTRAP_USER}' already exists -- ensuring sudo group membership"
  usermod -aG sudo "$BOOTSTRAP_USER"
else
  echo "==> Creating user '${BOOTSTRAP_USER}'"
  useradd -m -s /bin/bash -G sudo "$BOOTSTRAP_USER"
fi

# --- Set the password non-interactively --------------------------------
# chpasswd reads `user:password` lines from stdin. Using `printf` (not
# `echo`) avoids any backslash interpretation in the password. The
# variable is still in this shell's memory, but dropping the reference
# below is the right hygiene.

printf '%s:%s\n' "$BOOTSTRAP_USER" "$BOOTSTRAP_PASSWORD" | chpasswd
unset BOOTSTRAP_PASSWORD

# --- Summary ------------------------------------------------------------

echo "==> Done."
echo "    User : ${BOOTSTRAP_USER}"
echo "    Group: sudo"
echo "    Next : ssh ${BOOTSTRAP_USER}@<host>"