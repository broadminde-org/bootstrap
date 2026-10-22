#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 52-ufw — Install ufw, disable LLMNR, and stage + enable firewall rules.
#
# What this script does:
#
#   1. Installs ufw from apt.
#
#   2. Disables LLMNR (UDP 5355) via a systemd-resolved drop-in so the
#      resolver stops advertising on the local network — even before ufw
#      blocks port 5355 at the kernel level.
#
#   3. Stages firewall rules:
#        - default deny incoming / default allow outgoing
#        - SSH allowed on TCP 22 from any IPv4 and IPv6 source
#        - Port 5355 TCP/UDP blocked (belt-and-suspenders LLMNR block)
#
#   4. Enables ufw non-interactively after staging the SSH allow rule.
#
# IMPORTANT: Do NOT add rules for ports 80, 443, or 3478/udp here.
# Docker CE (with "iptables": true in daemon.json) inserts DNAT rules into
# the kernel's nat PREROUTING chain, which fires BEFORE ufw's INPUT chain.
# Any ufw rules for Docker-published ports are silently bypassed and create
# false confidence. Access control for those ports must be enforced at the
# application layer (Caddy for 80/443, NetBird for 3478).
#
# Run as root (sudo ./init.sh 52-ufw).

echo "=== 52-ufw: installing ufw ==="
apt-get install -y ufw

RESOLVED_DROP_IN_DIR=/etc/systemd/resolved.conf.d
RESOLVED_DROP_IN="${RESOLVED_DROP_IN_DIR}/no-llmnr.conf"

echo "=== 52-ufw: disabling LLMNR via systemd-resolved drop-in ==="

# ---------------------------------------------------------------------------
# Step 2: Disable LLMNR via systemd-resolved drop-in (idempotent write).
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
# Step 3: Stage ufw rules.
# ufw rule commands are idempotent — adding an already-present rule
# prints "Skipping adding existing rule" and exits 0.
# ---------------------------------------------------------------------------

echo ""
echo "=== 52-ufw: staging firewall rules ==="

# UFW only generates IPv6 rules when IPV6=yes; do this before staging SSH.
if ! grep -q '^IPV6=yes$' /etc/default/ufw; then
  sed -i -E 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
  grep -q '^IPV6=yes$' /etc/default/ufw || { echo 'ERROR: could not enable UFW IPv6 rules' >&2; exit 1; }
fi

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
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
# Step 5: Enable ufw. The SSH allow command above must succeed first.
# ---------------------------------------------------------------------------

echo ""
echo "=== 52-ufw: enabling ufw ==="
ufw --force enable
status="$(ufw status verbose)"
printf '%s\n' "$status"
if ! grep -q 'Status: active' <<< "$status" ||
   ! grep -Eq '^22/tcp[[:space:]]+ALLOW IN[[:space:]]+Anywhere' <<< "$status" ||
   ! grep -Eq '^22/tcp \(v6\)[[:space:]]+ALLOW IN[[:space:]]+Anywhere \(v6\)' <<< "$status"; then
  echo 'ERROR: UFW must be active with unrestricted IPv4 and IPv6 SSH rules' >&2
  exit 1
fi
