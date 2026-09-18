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
#   3. Writes /etc/avahi/avahi-daemon.conf with detected private interfaces
#      in allow-interfaces and use-ipv6=yes, then restarts avahi-daemon.
#      Interfaces carrying only public addresses are excluded so mDNS is
#      never published on a public uplink. Idempotent — skips write when
#      config matches.
#
# Run as root (sudo ./init.sh 58-mdns).

NSSWITCH_CONF=/etc/nsswitch.conf
HOSTS_FILE=/etc/hosts
AVAHI_CONF=/etc/avahi/avahi-daemon.conf

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

DOMAIN="$(grep '^domain ' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | head -1 || true)"
if [[ -z "$DOMAIN" ]]; then
  DOMAIN="$(grep '^search ' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | head -1 || true)"
fi

# The domain comes from DHCP — untrusted input. Sanitize before it goes
# anywhere near /etc/hosts.
if [[ -n "$DOMAIN" && ! "$DOMAIN" =~ ^[a-z0-9.-]+$ ]]; then
  echo "WARNING: DHCP-derived domain '${DOMAIN}' contains unexpected" >&2
  echo "         characters — ignoring it." >&2
  DOMAIN=""
fi

if [[ -n "$DOMAIN" ]]; then
  FQDN="${HOSTNAME}.${DOMAIN}"
  DESIRED_LINE="127.0.1.1	${FQDN} ${HOSTNAME}"
  echo "Detected domain: ${DOMAIN} → FQDN: ${FQDN}"
else
  DESIRED_LINE="127.0.1.1	${HOSTNAME}"
  echo "No domain detected — using short hostname only."
fi

CURRENT_LINE="$(grep '^127\.0\.1\.1[[:space:]]' "$HOSTS_FILE" 2>/dev/null || true)"

if [[ -z "$CURRENT_LINE" ]]; then
  cp -a "$HOSTS_FILE" "${HOSTS_FILE}.bootstrap.bak"
  printf '%s\n' "$DESIRED_LINE" >> "$HOSTS_FILE"
  echo "Added 127.0.1.1 entry: ${DESIRED_LINE} (backup: ${HOSTS_FILE}.bootstrap.bak)"
elif echo "$CURRENT_LINE" | grep -qF "${FQDN:-${HOSTNAME}}"; then
  echo "/etc/hosts 127.0.1.1 entry is already correct — skipping."
else
  cp -a "$HOSTS_FILE" "${HOSTS_FILE}.bootstrap.bak"
  sed -i '/^127\.0\.1\.1[[:space:]]/d' "$HOSTS_FILE"
  printf '%s\n' "$DESIRED_LINE" >> "$HOSTS_FILE"
  echo "Updated 127.0.1.1 entry: ${DESIRED_LINE} (backup: ${HOSTS_FILE}.bootstrap.bak)"
fi

# ---------------------------------------------------------------------------
# Step 3: Generate avahi-daemon.conf from template using envsubst.
# ---------------------------------------------------------------------------

echo ""
echo "=== 58-mdns: configuring avahi-daemon ==="

STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${STEP_DIR}/avahi-daemon.conf.template"

detect_private_interfaces() {
  {
    # RFC1918 and carrier-grade NAT space indicate LAN/mesh-facing interfaces.
    ip -o -4 addr show scope global 2>/dev/null \
      | awk '$4 ~ /^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.)/ {print $2}'

    # Unique-local IPv6 (fc00::/7) also indicates non-public scope. Ignore
    # link-local addresses — every interface has one.
    ip -o -6 addr show scope global 2>/dev/null \
      | awk 'tolower($4) ~ /^(fc|fd)/ {print $2}'
  } \
    | grep -v '^docker\|^br-\|^veth\|^virbr\|^lxc\|^cali\|^flannel\|^cni\|^tunl\|^kube\|^wg\|^tailscale' \
    | sort -u
}

INTERFACES="$(detect_private_interfaces | paste -sd ',' -)"
if [[ -n "$INTERFACES" ]]; then
  ALLOW_INTERFACES="allow-interfaces=${INTERFACES}"
  echo "Private interfaces: ${INTERFACES}"
else
  # No RFC1918/ULA interface found (plain public VPS): restricting to
  # loopback keeps the guarantee that mDNS is never published on a
  # public uplink — an empty ALLOW_INTERFACES would render NO
  # restriction and advertise on every interface.
  ALLOW_INTERFACES="allow-interfaces=lo"
  echo "No private interfaces detected — restricting mDNS to loopback (lo)."
fi

NEW_CONF="$(ALLOW_INTERFACES="$ALLOW_INTERFACES" envsubst < "$TEMPLATE")"

install -m 0755 -d /etc/avahi

avahi_changed=0
if [[ -f "$AVAHI_CONF" ]] && [[ "$(cat "$AVAHI_CONF")" == "$NEW_CONF" ]]; then
  echo "avahi-daemon.conf already up to date — skipping."
else
  printf '%s\n' "$NEW_CONF" > "$AVAHI_CONF"
  avahi_changed=1
  echo "Wrote avahi-daemon.conf"
fi

systemctl enable --now avahi-daemon 2>/dev/null || true
if (( avahi_changed )); then
  systemctl restart avahi-daemon
  echo "avahi-daemon restarted"
else
  echo "config unchanged — skipping avahi-daemon restart"
fi

echo ""
echo "58-mdns complete."
