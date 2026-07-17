# Hostname mDNS Fix — ll-protectli1

## Problem

`ll-protectli1` is unreachable by hostname from other hosts on the LAN.

## Host Configuration

| Item | Value |
|------|-------|
| Hostname | `ll-protectli1` |
| LAN IP | `10.2.2.104/24` |
| LAN Domain | `home.lan` |
| DNS Server | `10.2.2.1` |
| Interface | `enp1s0` (MAC `64:62:66:2f:3a:2a`) |

## Root Cause

**`/etc/nsswitch.conf` is missing mDNS from the hosts resolution chain.**

Current line:
```
hosts:          files dns
```

Avahi-daemon is running and publishing `ll-protectli1.local`, but without `mdns4_minimal` or `mdns4` in the nsswitch hosts line, neither local nor remote clients use mDNS to resolve the hostname.

Additionally, `/etc/hosts` only maps the hostname to `127.0.1.1` (loopback), not to the LAN IP:
```
127.0.1.1	ll-protectli1
```

## Fix

### 1. Enable mDNS name resolution (nsswitch)

Install the mDNS NSS plugin package if not present:
```bash
apt install libnss-mdns
```

Then update `/etc/nsswitch.conf`:
```
hosts:          files mdns4_minimal [NOTFOUND=return] dns
```

`mdns4_minimal [NOTFOUND=return]` resolves only `.local` names via mDNS and falls through to DNS for everything else. This is the standard Debian/Ubuntu pattern.

### 2. (Recommended) Add LAN IP to /etc/hosts

For hosts that don't run mDNS, add a static mapping:
```
10.2.2.104	ll-protectli1 ll-protectli1.home.lan
```

Full resulting `/etc/hosts`:
```
127.0.0.1	localhost
127.0.1.1	ll-protectli1
10.2.2.104	ll-protectli1 ll-protectli1.home.lan

::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
```

## Bootstrap Integration

This fix should be applied in the bootstrap repo's `init.d` so all new hosts get:

1. `libnss-mdns` package installed
2. `/etc/nsswitch.conf` hosts line updated with `mdns4_minimal [NOTFOUND=return]`
3. LAN IP hostname mapping in `/etc/hosts` (when IP is known from DHCP/static config)
