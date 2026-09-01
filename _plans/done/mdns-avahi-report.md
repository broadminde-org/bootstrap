# mDNS (Avahi) Configuration Issues

Host: `ll-protectli1` — Debian 13 (trixie)
Interface: `enp1s0`

## `/etc/avahi/avahi-daemon.conf`

### Issue 1: Wrong interface allow list

```
allow-interfaces=eth0,eth1,eno1
```

The actual interface is `enp1s0`. None of the listed interfaces exist on this host, so avahi binds only to loopback. mDNS resolution (`avahi-resolve --name ll-protectli1.local`) times out — the service is unreachable on the LAN.

**Fix:** change to the actual interface name, or remove the line entirely to allow all interfaces:

```
allow-interfaces=enp1s0
```

### Issue 2: IPv6 disabled

```
use-ipv6=no
```

IPv6 is explicitly turned off. Avahi does not publish AAAA records or listen on IPv6. Combined with issue 1, the host is invisible over both IPv4 and IPv6 mDNS.

**Fix:**

```
use-ipv6=yes
```

## Bootstrap considerations

- `allow-interfaces` should either be omitted (all interfaces) or populated dynamically from the actual interface name at bootstrap time (e.g., read from `ip link show`).
- Set `use-ipv6=yes` unconditionally for dual-stack hosts.
- After fixing the config, restart: `systemctl restart avahi-daemon`
- Verify with: `avahi-resolve --name <hostname>.local` from another machine on the same LAN.
