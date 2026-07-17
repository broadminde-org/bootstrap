#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 50-docker — Install Docker CE (engine + CLI + Compose plugin) and
# configure the daemon for dual-stack (IPv4 + IPv6) operation.
#
# Cleans up any containerd/run/docker.io remnants, adds Docker's
# upstream apt repo for the current distro (Debian or Ubuntu),
# writes /etc/docker/daemon.json with iptables/ip6tables enabled,
# userland-proxy disabled, and IPv6 enabled with a fixed-cidr-v6
# for container addressing. Writes /etc/sysctl.d/99-docker-ipv6.conf
# with the kernel settings Docker needs for IPv6 forwarding and
# dual-stack `[::]` listeners, and applies them via `sysctl --system`.
# Starts the daemon.
#
# Optionally honours DOCKER_REGISTRY (read from the bootstrap repo's
# own .env if present). HTTP registries are added to
# insecure-registries; HTTPS registries are TLS-verified and not added
# (otherwise Docker would silently disable verification).
#
# Customisation:
#   DOCKER_IPV6_FIXED_CIDR — IPv6 subnet for Docker's default
#     bridge. Must be a /64 or smaller. Default fd00:db8::/64
#     (RFC 4193 ULA, never globally-routable). Set in the bootstrap
#     repo's .env if your network requires a different UL prefix.
#
# Restart requirement:
#   Changes to daemon.json require `systemctl restart docker` to
#   take effect on a running daemon. This script intentionally does
#   NOT restart Docker — re-running it on a host with live
#   containers would tear them down. Restart manually after the
#   first apply, or call this step before any compose stack starts.
#
# Run as root (sudo ./init.sh 50-docker).

# Optional per-step .env override. If the operator wants DOCKER_REGISTRY
# or DOCKER_IPV6_FIXED_CIDR read from a file rather than an env var,
# drop a `.env` next to this run.sh (init.d/50-docker/.env):
#   DOCKER_REGISTRY=http://registry.local:5000
_STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$_STEP_DIR/.env" ]]; then
  set -a; source "$_STEP_DIR/.env"; set +a
fi
unset _STEP_DIR

REGISTRY="${DOCKER_REGISTRY:-}"

# Only mark a registry as insecure when its scheme is plain HTTP. An
# HTTPS registry must NOT appear under "insecure-registries" — doing
# so would silently disable TLS verification, defeating the security
# guarantee.
INSECURE_REGISTRIES=()
if [[ -n "$REGISTRY" && "${REGISTRY}" == http://* ]]; then
  INSECURE_REGISTRIES+=("${REGISTRY}")
fi

if [[ -n "$REGISTRY" ]]; then
  echo "Configuring Docker with registry: ${REGISTRY}"
  if (( ${#INSECURE_REGISTRIES[@]} > 0 )); then
    echo "  (HTTP — will be marked insecure)"
  else
    echo "  (HTTPS — TLS-verified)"
  fi
else
  echo "Configuring Docker (no private registry — DOCKER_REGISTRY unset)"
fi

# ---------------------------------------------------------------------------
# DOCKER_IPV6_FIXED_CIDR — IPv6 subnet Docker's default bridge uses to
# assign v6 addresses to containers. Does NOT affect which IPv6
# addresses the host publishes on — those come from the host's own
# interfaces. Must be a valid IPv6 CIDR with prefix length 0..128.
# Soft regex check only; Docker itself rejects malformed CIDRs on
# daemon startup (visible in `journalctl -u docker`).
# ---------------------------------------------------------------------------

DOCKER_IPV6_FIXED_CIDR="${DOCKER_IPV6_FIXED_CIDR:-fd00:db8::/64}"
if [[ ! "$DOCKER_IPV6_FIXED_CIDR" =~ ^[0-9a-fA-F:]+/([0-9]|[1-9][0-9]|1[0-1][0-9]|12[0-8])$ ]]; then
  echo "ERROR: DOCKER_IPV6_FIXED_CIDR='$DOCKER_IPV6_FIXED_CIDR' is not a valid IPv6 CIDR (prefix must be 0..128)" >&2
  exit 1
fi
echo "Docker IPv6 subnet: ${DOCKER_IPV6_FIXED_CIDR} (override via DOCKER_IPV6_FIXED_CIDR)"

# Clean up any docker remnants / podman from older installs.
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do apt-get remove -y "$pkg"; done

# Configure Docker apt repository.
DISTRO=$(. /etc/os-release && echo "${ID}")
case "$DISTRO" in
  ubuntu|debian) ;;
  *) DISTRO="ubuntu" ;;
esac
CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME}")

rm -f /etc/apt/sources.list.d/docker.list
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/${DISTRO}/gpg" -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
printf 'Types: deb\nURIs: https://download.docker.com/linux/%s\nSuites: %s\nComponents: stable\nSigned-By: /etc/apt/keyrings/docker.asc\n' \
  "$DISTRO" "$CODENAME" > /etc/apt/sources.list.d/docker.sources
apt-get update
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add the deploy user to the docker group so they can use Docker
# without sudo. The docker group is created by the docker-ce package
# above. We own group membership here rather than in 20-groups so that
# the docker group is only granted when Docker is actually installed.
if [[ -n "${SUDO_USER:-}" ]]; then
  usermod -aG docker "$SUDO_USER"
  echo "Added $SUDO_USER to docker group"
fi

# Write daemon.json — preserves iptables, ip6tables, userland-proxy and
# adds insecure-registries ONLY when REGISTRY is HTTP. The list is
# built with jq from the bash array to avoid hand-rolled JSON escaping
# bugs.
#
# Idempotent: builds the expected content in memory, compares against
# the on-disk file, and skips the write when they match. This avoids
# needlessly restarting Docker or tripping filesystem watches.
if (( ${#INSECURE_REGISTRIES[@]} > 0 )); then
  INSECURE_JSON=$(printf '%s\n' "${INSECURE_REGISTRIES[@]}" | jq -R . | jq -s .)
else
  INSECURE_JSON="[]"
fi

DAEMON_JSON="/etc/docker/daemon.json"
NEW_DAEMON_JSON=$(cat <<DAEMON_EOF
{
  "iptables": true,
  "ip6tables": true,
  "userland-proxy": false,
  "ipv6": true,
  "fixed-cidr-v6": "${DOCKER_IPV6_FIXED_CIDR}",
  "hosts": ["unix:///var/run/docker.sock"],
  "insecure-registries": ${INSECURE_JSON}
}
DAEMON_EOF
)

if [[ -f "$DAEMON_JSON" ]] && [[ "$(cat "$DAEMON_JSON")" == "$NEW_DAEMON_JSON" ]]; then
  echo "daemon.json already up to date — skipping."
else
  printf '%s\n' "$NEW_DAEMON_JSON" > "$DAEMON_JSON"
  echo "Wrote daemon.json"
fi

# ---------------------------------------------------------------------------
# Systemd override: remove -H fd:// from ExecStart.
#
# systemd's docker.service ships with `ExecStart=/usr/bin/dockerd -H fd://`
# for socket activation. When `hosts` is present in daemon.json, this
# fd:// flag conflicts — Docker refuses to start. The override replaces
# the ExecStart line with a bare `/usr/bin/dockerd` so Docker reads its
# hosts exclusively from daemon.json. This is a prerequisite for any
# app step that adds TCP listeners to the hosts list (e.g. isogen's
# docker TCP listener on :2375).
# ---------------------------------------------------------------------------
OVERRIDE_DIR="/etc/systemd/system/docker.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/override.conf"
if [[ -f "$OVERRIDE_FILE" ]] && grep -q 'ExecStart=/usr/bin/dockerd$' "$OVERRIDE_FILE" 2>/dev/null; then
  echo "systemd docker override already in place — skipping."
else
  mkdir -p "$OVERRIDE_DIR"
  cat > "$OVERRIDE_FILE" <<'DOCKER_OVERRIDE_EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd
DOCKER_OVERRIDE_EOF
  systemctl daemon-reload
  echo "Created systemd docker override (removed -H fd:// conflict)"
fi

# ---------------------------------------------------------------------------
# IPv6 sysctl: required for Docker IPv6 port publishing end-to-end.
#
# `daemon.json` `ipv6: true` is the application-level switch, but
# without these two kernel settings it is silently no-op:
#
#   net.ipv6.bindv6only = 0
#     Lets a process binding to `[::]:PORT` accept both stacks.
#     Some hardened kernels ship this as 1, which would block the
#     `[::]:80` / `[::]:443` Docker publishes.
#
#   net.ipv6.conf.all.forwarding = 1
#     Required so the Docker bridge can route IPv6 traffic between
#     container <-> host <-> WAN. Without it, v6-published ports
#     accept the SYN but the SYN-ACK cannot return.
#
# Both are written to a sysctl.d drop-in (survives reboots) and
# applied now via `sysctl --system`. Re-running this step is safe —
# `sysctl --system` is a no-op when runtime values already match.
# ---------------------------------------------------------------------------

SYSCtl_FILE=/etc/sysctl.d/99-docker-ipv6.conf
install -m 0755 -d /etc/sysctl.d

cat > "$SYSCtl_FILE" <<'SYSC_EOF'
# Managed by bootstrap/init.d/50-docker.
# Required for Docker IPv6 port publishing; do not edit by hand.
net.ipv6.bindv6only = 0
net.ipv6.conf.all.forwarding = 1
SYSC_EOF

if [[ -e /proc/sys/net/ipv6 ]]; then
  sysctl --system >/dev/null
  echo "Applied IPv6 sysctls: bindv6only=$(sysctl -n net.ipv6.bindv6only), all.forwarding=$(sysctl -n net.ipv6.conf.all.forwarding)"
else
  echo "WARNING: /proc/sys/net/ipv6 not present — kernel has no IPv6 support; IPv6 publishes will not work." >&2
fi

systemctl enable --now docker
echo "Docker configured and started"

# ---------------------------------------------------------------------------
# Post-condition: verify daemon.json parses and contains the expected
# IPv6 fields. jq exits non-zero on malformed JSON — surface that
# loudly so a broken config does not silently disable v6 publishes.
# ---------------------------------------------------------------------------

if ! jq -e '.ipv6 == true and (.["fixed-cidr-v6"] | type == "string")' /etc/docker/daemon.json >/dev/null; then
  echo "ERROR: /etc/docker/daemon.json missing ipv6/fixed-cidr-v6 after write" >&2
  exit 1
fi
