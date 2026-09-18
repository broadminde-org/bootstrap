#!/usr/bin/env bash
# shellcheck shell=bash
# lib/user.sh — deploy-user resolution for root-tier steps.
#
# Every root-tier step that operates on "the deploy user" (group
# membership, sudoers, ~/.profile, ~/.ssh, per-user installs) resolves
# that user through here instead of reading SUDO_USER raw.
#
# Resolution order:
#   1. BOOTSTRAP_USER (explicit operator env var / repo-root .env)
#   2. SUDO_USER (set by sudo when a human runs `sudo ./init.sh`)
#
# Hard error when the result is empty, "root", or a nonexistent
# account: a root-tier step that cannot name a non-root deploy user
# would otherwise provision root's account or die later with a cryptic
# message. The only step exempt from this helper is
# 10-create-deploy-user itself, which CREATES the account.

require_deploy_user() {
  DEPLOY_USER="${BOOTSTRAP_USER:-${SUDO_USER:-}}"

  if [[ -z "$DEPLOY_USER" ]]; then
    echo "ERROR: cannot resolve the deploy user." >&2
    echo "       Set BOOTSTRAP_USER, or log in as the deploy user and run" >&2
    echo "       this step via sudo (sudo ./init.sh <step>)." >&2
    echo "       On a fresh host, run step 10 first:  ./init.sh 10" >&2
    exit 1
  fi

  if [[ "$DEPLOY_USER" == "root" ]]; then
    echo "ERROR: deploy user resolved to 'root' — refusing to provision" >&2
    echo "       root as its own deploy account. Log in as the deploy user" >&2
    echo "       and re-run via sudo, or set BOOTSTRAP_USER explicitly." >&2
    exit 1
  fi

  if [[ ! "$DEPLOY_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    echo "ERROR: deploy user '$DEPLOY_USER' is not a valid POSIX account name" >&2
    echo "       (^[a-z_][a-z0-9_-]{0,31}\$). Note: sudo silently skips" >&2
    echo "       /etc/sudoers.d/ files whose names contain a dot." >&2
    exit 1
  fi

  if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
    echo "ERROR: deploy user '$DEPLOY_USER' does not exist." >&2
    echo "       Run step 10-create-deploy-user first (./init.sh 10)." >&2
    exit 1
  fi

  export DEPLOY_USER
}
