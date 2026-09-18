#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 52-ufw — Install ufw, disable LLMNR, and stage + enable firewall rules.
#
# What this script does:
#
#   1. Disables LLMNR (UDP 5355) via a systemd-resolved drop-in so the
#      resolver stops advertising on the local network — even before ufw
#      blocks port 5355 at the kernel level.
#
#   2. Installs ufw from apt.
#
#   3. Stages firewall rules:
#        - default deny incoming / default allow outgoing
#        - SSH allowed from the management network only (MGMT_SSH_CIDR,
#          from the environment or repo-root .env — required)
#        - Port 5355 TCP/UDP blocked (belt-and-suspenders LLMNR block)
#
#   4. Enables ufw non-interactively — but ONLY after verifying the SSH
#      allow rule is actually staged (a misconfigured MGMT_SSH_CIDR must
#      never lock the operator out silently; when the rule is missing the
#      step fails loudly and leaves ufw disabled).
#
# IMPORTANT: Do NOT add rules for ports 80, 443, or 3478/udp here.
# Docker CE (with "iptables": true in daemon.json) inserts DNAT rules into
# the kernel's nat PREROUTING chain, which fires BEFORE ufw's INPUT chain.
# Any ufw rules for Docker-published ports are silently bypassed and create
# false confidence. Access control for those ports must be enforced at the
# application layer (Caddy for 80/443, NetBird for 3478).
#
# Run as root (sudo ./init.sh 52-ufw).

MGMT_SSH_CIDR="${MGMT_SSH_CIDR:-$(env_file_value MGMT_SSH_CIDR || true)}"
if [[ -z "$MGMT_SSH_CIDR" ]]; then
  echo "ERROR: MGMT_SSH_CIDR is not set." >&2
  echo "       Set it in the environment or in $EE_ROOT/.env — the management" >&2
  echo "       network allowed to reach SSH (e.g. MGMT_SSH_CIDR=203.0.113.0/24)." >&2
  exit 1
fi

RESOLVED_DROP_IN_DIR=/etc/systemd/resolved.conf.d
RESOLVED_DROP_IN="${RESOLVED_DROP_IN_DIR}/no-llmnr.conf"

echo "=== 52-ufw: disabling LLMNR via systemd-resolved drop-in ==="

# ---------------------------------------------------------------------------
# Step 1: Disable LLMNR via systemd-resolved drop-in (idempotent write).
# ---------------------------------------------------------------------------

mkdir -p "$RESOLVED_DROP_IN_DIR"

RESOLVED_NEW='# Managed by bootstrap/init.d/52-ufw. Do not edit by hand.
[Resolve]
LLMNR=no
MulticastDNS=no'

if [[ -f "$RESOLVED_DROP_IN" ]] && [[ "$(cat "$RESOLVED_DROP_IN")" == "$RESOLVED_NEW" ]]; then
  echo "ok: ${RESOLVED_DROP_IN} (unchanged)"
else
  printf '%s\n' "$RESOLVED_NEW" > "$RESOLVED_DROP_IN"
  echo "Written ${RESOLVED_DROP_IN}"
fi
if systemctl cat systemd-resolved &>/dev/null; then
  systemctl reload systemd-resolved
  echo "systemd-resolved reloaded"
else
  echo "systemd-resolved not present — drop-in written for future use, skipping reload"
fi

# ---------------------------------------------------------------------------
# Step 2: Install ufw.
# ---------------------------------------------------------------------------

echo ""
echo "=== 52-ufw: installing ufw ==="
apt-get install -y ufw

# ---------------------------------------------------------------------------
# Step 3: Stage ufw rules.
# ufw rule commands are idempotent — adding an already-present rule
# prints "Skipping adding existing rule" and exits 0.
# ---------------------------------------------------------------------------

echo ""
echo "=== 52-ufw: staging firewall rules ==="

ufw default deny incoming
ufw default allow outgoing
ufw allow from "$MGMT_SSH_CIDR" to any port 22 proto tcp comment 'SSH from management network'
ufw deny 5355/tcp comment 'Block LLMNR (systemd-resolved, host-only)'
ufw deny 5355/udp comment 'Block LLMNR (systemd-resolved, host-only)'

# IMPORTANT: Do NOT add rules for ports 80, 443, or 3478/udp here.
# Docker CE (with "iptables": true in daemon.json) inserts DNAT rules into
# the kernel's nat PREROUTING chain, which fires BEFORE ufw's INPUT chain.
# Any ufw rules for Docker-published ports are silently bypassed and create
# false confidence. Access control for those ports must be enforced at the
# application layer (Caddy for 80/443, NetBird for 3478).

# ---------------------------------------------------------------------------
# Step 4: Show staged rules.
# ---------------------------------------------------------------------------

echo ""
echo "=== Staged rules (NOT yet active) ==="
ufw show added

# ---------------------------------------------------------------------------
# Step 5: Enable ufw — gated on the SSH rule being verifiably staged.
#
# Historically this step printed manual-enable instructions (the old
# "Phase 1c") and hosts routinely never got their firewall turned on.
# Now that the SSH rule is staged first and MGMT_SSH_CIDR is explicit,
# enabling here is safe: if the rule is somehow absent the step fails
# loudly and leaves ufw DISABLED rather than risking a lockout.
# ---------------------------------------------------------------------------

echo ""
if ufw status 2>/dev/null | grep -q 'Status: active'; then
  echo "ufw is already active."
elif ufw show added | grep -qF "from $MGMT_SSH_CIDR to any port 22"; then
  echo "=== 52-ufw: SSH rule verified staged — enabling ufw ==="
  ufw --force enable
  ufw status verbose
else
  echo "ERROR: SSH allow rule for $MGMT_SSH_CIDR not found in 'ufw show added'." >&2
  echo "       Refusing to enable ufw — doing so would lock out SSH." >&2
  echo "       Staged rules were:" >&2
  ufw show added >&2
  exit 1
fi
