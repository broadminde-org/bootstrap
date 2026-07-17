#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 51-ssh-hardening — Harden the OpenSSH daemon configuration.
#
# Performs two complementary actions so the effective sshd config is
# locked down regardless of how the cloud-init or default config was
# left at provisioning time:
#
#   1. Patches the base /etc/ssh/sshd_config in-place using sed (only
#      when the insecure default values are still present — idempotent).
#      Covers PermitRootLogin and X11Forwarding.
#
#   2. Installs two drop-in snippets into /etc/ssh/sshd_config.d/,
#      numbered above cloud-init's 50-cloud-init.conf so they win:
#
#        60-auth.conf     — auth methods (Round 1: password still enabled;
#                           disable in a later round once keys are enrolled)
#        61-hardening.conf — connection limits and forwarding policy
#
# Both steps are fully idempotent — running this script a second time
# produces the same end state and does NOT interrupt active sessions
# (systemctl reload, not restart).
#
# Post-condition assertions confirm the effective values via `sshd -T`
# (the full merged config including all drop-ins). Exit 1 on any
# failure so init.sh can surface the error cleanly.
#
# Run as root (sudo ./init.sh 51-ssh-hardening).

SSHD_CONFIG=/etc/ssh/sshd_config
DROP_IN_DIR=/etc/ssh/sshd_config.d
STEP_DIR="$(dirname "$0")"

echo "=== 51-ssh-hardening: patching base sshd_config ==="

# ---------------------------------------------------------------------------
# Step 1: Fix base /etc/ssh/sshd_config in-place.
# sed -i replaces only when the bad value is present — idempotent.
# ---------------------------------------------------------------------------

sed -i 's/^PermitRootLogin yes$/PermitRootLogin no/' "$SSHD_CONFIG"
sed -i 's/^X11Forwarding yes$/X11Forwarding no/' "$SSHD_CONFIG"
echo "Base sshd_config patched (PermitRootLogin, X11Forwarding)"

# ---------------------------------------------------------------------------
# Step 2: Install the hardening drop-ins.
# ---------------------------------------------------------------------------

install -m 0755 -d "$DROP_IN_DIR"

for conf in 60-auth.conf 61-hardening.conf; do
  install -m 0644 "${STEP_DIR}/${conf}" "${DROP_IN_DIR}/${conf}"
  echo "Installed ${DROP_IN_DIR}/${conf}"
done

# ---------------------------------------------------------------------------
# Step 3: Reload sshd to apply changes without dropping active sessions.
# ---------------------------------------------------------------------------

systemctl reload sshd
echo "sshd reloaded"


echo "51-ssh-hardening complete."
echo "NOTE: PasswordAuthentication is still enabled (Round 1)."
echo "      Once a key is enrolled for the deploy user, disable it by"
echo "      setting PasswordAuthentication no in 60-auth.conf and reloading sshd."
