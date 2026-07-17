#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 58-mdns — Enable mDNS hostname resolution and LAN IP hostname mapping.
#
# Two independent fixes so the host can be reached by hostname from
# other LAN hosts:
#
#   1. Adds mdns4_minimal [NOTFOUND=return] to the hosts line in
#      /etc/nsswitch.conf so .local names resolve via Avahi mDNS.
#      Fully idempotent — sed replaces only when the old pattern matches.
#
#   2. Adds the host's primary LAN IP + hostname to /etc/hosts as a
#      static fallback for hosts that don't run mDNS themselves.
#      Marker-guarded so bootstrap re-runs only touch its own line.
#
# Run as root (sudo ./init.sh 58-mdns).

NSSWITCH_CONF=/etc/nsswitch.conf
HOSTS_FILE=/etc/hosts
HOSTS_MARKER="# bootstrap-58-mdns"

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
# Step 2: Add LAN IP hostname mapping to /etc/hosts.
# Marker-guarded so only bootstrap's own line is managed.
# ---------------------------------------------------------------------------

echo ""
echo "=== 58-mdns: detecting LAN IP for /etc/hosts ==="

HOSTNAME="$(hostname)"

LAN_INTERFACE="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
if [[ -z "$LAN_INTERFACE" ]]; then
  echo "WARNING: no default IPv4 route found — skipping /etc/hosts mapping." >&2
else
  LAN_IP="$(ip -4 addr show "$LAN_INTERFACE" 2>/dev/null | awk '/inet / {print $2; exit}' | cut -d/ -f1)"
  if [[ -z "$LAN_IP" ]]; then
    echo "WARNING: no IPv4 address on interface $LAN_INTERFACE — skipping /etc/hosts mapping." >&2
  elif [[ "$LAN_IP" = "127."* ]]; then
    echo "WARNING: loopback IP ($LAN_IP) on $LAN_INTERFACE — skipping /etc/hosts mapping." >&2
  else
    DOMAIN="$(hostname -d 2>/dev/null || true)"
    if [[ -n "$DOMAIN" && "$DOMAIN" != "(none)" ]]; then
      HOSTS_ENTRY="${LAN_IP}\t${HOSTNAME} ${HOSTNAME}.${DOMAIN}  ${HOSTS_MARKER}"
    else
      HOSTS_ENTRY="${LAN_IP}\t${HOSTNAME}  ${HOSTS_MARKER}"
    fi

    if grep -qF "${HOSTS_MARKER}" "$HOSTS_FILE" 2>/dev/null; then
      EXISTING="$(grep -F "${HOSTS_MARKER}" "$HOSTS_FILE")"
      if echo "$EXISTING" | grep -qF "${LAN_IP}"; then
        echo "/etc/hosts already has bootstrap-managed entry for ${LAN_IP} — skipping."
      else
        echo "/etc/hosts has a stale bootstrap entry (IP changed). Updating."
        sed -i "/${HOSTS_MARKER}/d" "$HOSTS_FILE"
        printf '%b\n' "$HOSTS_ENTRY" >> "$HOSTS_FILE"
        echo "Updated /etc/hosts: ${LAN_IP} → ${HOSTNAME}"
      fi
    else
      printf '%b\n' "$HOSTS_ENTRY" >> "$HOSTS_FILE"
      echo "Added to /etc/hosts: ${LAN_IP} → ${HOSTNAME}"
    fi
  fi
fi

echo ""
echo "58-mdns complete."
