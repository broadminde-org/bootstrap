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
#   2. Installs a drop-in snippet at /etc/ssh/sshd_config.d/60-hardening.conf
#      that contains the full authoritative policy (PermitRootLogin no,
#      X11Forwarding no, AllowUsers stack, MaxAuthTries 3,
#      LoginGraceTime 20). Numbered 60 so it wins over cloud-init's
#      50-cloud-init.conf drop-in on future re-provisions.
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
DROP_IN_DST="${DROP_IN_DIR}/60-hardening.conf"
DROP_IN_SRC="$(dirname "$0")/60-hardening.conf"

echo "=== 51-ssh-hardening: patching base sshd_config ==="

# ---------------------------------------------------------------------------
# Step 1: Fix base /etc/ssh/sshd_config in-place.
# sed -i replaces only when the bad value is present — idempotent.
# ---------------------------------------------------------------------------

sed -i 's/^PermitRootLogin yes$/PermitRootLogin no/' "$SSHD_CONFIG"
sed -i 's/^X11Forwarding yes$/X11Forwarding no/' "$SSHD_CONFIG"
echo "Base sshd_config patched (PermitRootLogin, X11Forwarding)"

# ---------------------------------------------------------------------------
# Step 2: Install the hardening drop-in.
# The drop-in wins over cloud-init's 50-cloud-init.conf because sshd
# processes sshd_config.d/*.conf in lexicographic order and uses the
# FIRST occurrence of each directive.
# ---------------------------------------------------------------------------

install -m 0755 -d "$DROP_IN_DIR"
install -m 0644 "$DROP_IN_SRC" "$DROP_IN_DST"
echo "Installed ${DROP_IN_DST}"

# ---------------------------------------------------------------------------
# Step 3: Reload sshd to apply changes without dropping active sessions.
# ---------------------------------------------------------------------------

systemctl reload sshd
echo "sshd reloaded"

# ---------------------------------------------------------------------------
# Step 4: Post-condition assertions via sshd -T (effective merged config).
# ---------------------------------------------------------------------------

echo ""
echo "=== Post-condition assertions ==="

FAIL=0

check() {
  local label="$1"
  local pattern="$2"
  local value="$3"
  if sshd -T | grep -E "$pattern" | grep -q "$value"; then
    echo "  PASS: ${label}"
  else
    echo "  FAIL: ${label}" >&2
    FAIL=1
  fi
}

check "PermitRootLogin no"  "^permitrootlogin "  " no"
check "X11Forwarding no"    "^x11forwarding "    " no"
check "AllowUsers stack"    "^allowusers "       " stack"
check "MaxAuthTries 3"      "^maxauthtries "     " 3"

if (( FAIL != 0 )); then
  echo "" >&2
  echo "ERROR: one or more sshd post-condition assertions failed." >&2
  echo "Run 'sshd -T' to inspect the effective configuration." >&2
  exit 1
fi

echo ""
echo "51-ssh-hardening complete."
