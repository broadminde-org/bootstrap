#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 52-ufw — Install ufw, disable LLMNR, and stage firewall rules.
#
# Deliberately does NOT call `ufw enable`. Enabling the firewall is a
# separate manual step (Phase 1c) because activating ufw on a remote
# host without a confirmed SSH-allow rule will lock you out. The staged
# rules must be reviewed first (ufw show added) from a second SSH
# session.
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
#        - SSH allowed from the management network only (170.203.0.0/16)
#        - Port 5355 TCP/UDP blocked (belt-and-suspenders LLMNR block)
#
#   4. Shows staged rules and prints Phase 1c instructions.
#
# IMPORTANT: Do NOT add rules for ports 80, 443, or 3478/udp here.
# Docker CE (with "iptables": true in daemon.json) inserts DNAT rules into
# the kernel's nat PREROUTING chain, which fires BEFORE ufw's INPUT chain.
# Any ufw rules for Docker-published ports are silently bypassed and create
# false confidence. Access control for those ports must be enforced at the
# application layer (Caddy for 80/443, NetBird for 3478).
#
# Run as root (sudo ./init.sh 52-ufw).

RESOLVED_DROP_IN_DIR=/etc/systemd/resolved.conf.d
RESOLVED_DROP_IN="${RESOLVED_DROP_IN_DIR}/no-llmnr.conf"

echo "=== 52-ufw: disabling LLMNR via systemd-resolved drop-in ==="

# ---------------------------------------------------------------------------
# Step 1: Disable LLMNR via systemd-resolved drop-in (idempotent write).
# ---------------------------------------------------------------------------

mkdir -p "$RESOLVED_DROP_IN_DIR"

cat > "$RESOLVED_DROP_IN" <<'RESOLVED_EOF'
# Managed by bootstrap/init.d/52-ufw. Do not edit by hand.
[Resolve]
LLMNR=no
MulticastDNS=no
RESOLVED_EOF

echo "Written ${RESOLVED_DROP_IN}"
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
ufw allow from 170.203.0.0/16 to any port 22 proto tcp comment 'SSH from management network'
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
# Phase 1c reminder — printed last so it is not buried in apt output.
# ---------------------------------------------------------------------------

echo ""
echo "==================================================================="
echo "  PHASE 1b COMPLETE — ufw rules STAGED but NOT yet active."
echo "  To enable, follow Phase 1c procedure in the host-hardening plan:"
echo "    1. Confirm your IP is in 170.203.0.0/16: curl -s https://ifconfig.me"
echo "    2. Open a SECOND SSH session (keep it open throughout)"
echo "    3. Review staged rules: ufw show added"
echo "    4. Enable: ufw --force enable && ufw status verbose"
echo "  Recovery fallback: DigitalOcean droplet console -> ufw disable"
echo "==================================================================="
