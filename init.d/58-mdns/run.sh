#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 58-mdns — Enable mDNS hostname resolution via Avahi.
#
# Three independent fixes so the host can be reached by hostname from
# other LAN hosts:
#
#   1. Adds mdns4_minimal [NOTFOUND=return] to the hosts line in
#      /etc/nsswitch.conf so .local names resolve via Avahi mDNS.
#      Fully idempotent — sed replaces only when the old pattern matches.
#
#   2. Ensures /etc/hosts maps 127.0.1.1 to the FQDN (hostname + domain
#      suffix, obtained from DHCP/DNS search domain), with the short
#      hostname as an alias. This is the standard Debian convention.
#
#   3. Writes /etc/avahi/avahi-daemon.conf with detected physical
#      interfaces in allow-interfaces and use-ipv6=yes, then restarts
#      avahi-daemon. Idempotent — skips write when config matches.
#
# Run as root (sudo ./init.sh 58-mdns).

NSSWITCH_CONF=/etc/nsswitch.conf
HOSTS_FILE=/etc/hosts
AVAHi_CONF=/etc/avahi/avahi-daemon.conf

echo "=== 58-mdns: adding mDNS to nsswitch hosts line ==="

# ---------------------------------------------------------------------------
# Step 1: Patch /etc/nsswitch.conf — add mdns4_minimal.
# sed -i replaces only when the default pattern matches — idempotent.
# ---------------------------------------------------------------------------

if grep -q 'mdns' "$NSSWITCH_CONF" 2>/dev/null; then
  echo "nsswitch.conf already contains mDNS — skipping."
else
  sed -i 's/^hosts:\s*files\s*dns$/hosts:          files mdns4_minimal [NOTFOUND=return] dns/' "$NSSWITCH_CONF"
  if grep -q 'mdns' "$NSSWITCH_CONF"; then
    echo "nsswitch.conf updated: hosts line now includes mdns4_minimal."
  else
    echo "WARNING: nsswitch.conf hosts line not in expected 'files dns' format." >&2
    echo "Add mdns4_minimal [NOTFOUND=return] manually if needed." >&2
  fi
fi

# ---------------------------------------------------------------------------
# Step 2: Detect domain suffix from DHCP/DNS and ensure FQDN at 127.0.1.1.
# ---------------------------------------------------------------------------

echo ""
echo "=== 58-mdns: detecting domain suffix for /etc/hosts FQDN ==="

HOSTNAME="$(hostname -s)"

DOMAIN="$(grep '^domain ' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | head -1)"

if [[ -n "$DOMAIN" ]]; then
  FQDN="${HOSTNAME}.${DOMAIN}"
  DESIRED_LINE="127.0.1.1\t${FQDN} ${HOSTNAME}"
  echo "Detected domain: ${DOMAIN} → FQDN: ${FQDN}"
else
  DESIRED_LINE="127.0.1.1\t${HOSTNAME}"
  echo "No domain detected — using short hostname only."
fi

CURRENT_LINE="$(grep '^127\.0\.1\.1[[:space:]]' "$HOSTS_FILE" 2>/dev/null || true)"

if [[ -z "$CURRENT_LINE" ]]; then
  printf '%b\n' "$DESIRED_LINE" >> "$HOSTS_FILE"
  echo "Added 127.0.1.1 entry: ${DESIRED_LINE}"
elif echo "$CURRENT_LINE" | grep -qF "${FQDN:-${HOSTNAME}}"; then
  echo "/etc/hosts 127.0.1.1 entry is already correct — skipping."
else
  sed -i '/^127\.0\.1\.1[[:space:]]/d' "$HOSTS_FILE"
  printf '%b\n' "$DESIRED_LINE" >> "$HOSTS_FILE"
  echo "Updated 127.0.1.1 entry: ${DESIRED_LINE}"
fi

# ---------------------------------------------------------------------------
# Step 3: Generate avahi-daemon.conf from template using envsubst.
# ---------------------------------------------------------------------------

echo ""
echo "=== 58-mdns: configuring avahi-daemon ==="

STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${STEP_DIR}/avahi-daemon.conf.template"

detect_physical_interfaces() {
  ip -br link show 2>/dev/null \
    | awk '$1 != "lo" {print $1}' \
    | grep -v '^docker\|^br-\|^veth\|^virbr\|^lxc\|^cali\|^flannel\|^cni\|^tunl\|^kube\|^wg\|^tailscale'
}

INTERFACES="$(detect_physical_interfaces | paste -sd ',' -)"
ALLOW_INTERFACES="${INTERFACES:+allow-interfaces=${INTERFACES}}"
echo "Physical interfaces: ${INTERFACES:-none detected}"

NEW_CONF="$(ALLOW_INTERFACES="$ALLOW_INTERFACES" envsubst < "$TEMPLATE")"

install -m 0755 -d /etc/avahi

if [[ -f "$AVAHi_CONF" ]] && [[ "$(cat "$AVAHi_CONF")" == "$NEW_CONF" ]]; then
  echo "avahi-daemon.conf already up to date — skipping."
else
  printf '%s\n' "$NEW_CONF" > "$AVAHi_CONF"
  echo "Wrote avahi-daemon.conf"
fi

systemctl enable --now avahi-daemon 2>/dev/null || true
systemctl restart avahi-daemon
echo "avahi-daemon restarted"

echo ""
echo "58-mdns complete."
