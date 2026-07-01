#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 50-docker — Install Docker CE (engine + CLI + Compose plugin) and
# configure the daemon.
#
# Cleans up any containerd/run/docker.io remnants, adds Docker's
# upstream apt repo for the current distro (Debian or Ubuntu),
# writes /etc/docker/daemon.json with iptables/ip6tables enabled and
# userland-proxy disabled, and starts the daemon.
#
# Optionally honours DOCKER_REGISTRY (read from the bootstrap repo's
# own .env if present). HTTP registries are added to
# insecure-registries; HTTPS registries are TLS-verified and not added
# (otherwise Docker would silently disable verification).
#
# Run as root (sudo ./init.sh 50-docker).

# EE_ROOT is exported by lib/env.sh (via common.sh) and points to the
# bootstrap repo. If the operator wants DOCKER_REGISTRY read from a
# .env instead of an env var, drop a `.env` next to init.sh:
#   DOCKER_REGISTRY=http://registry.local:5000

if [[ -f "$EE_ROOT/.env" ]]; then
  set -a; source "$EE_ROOT/.env"; set +a
fi

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

# Write daemon.json — preserves iptables, ip6tables, userland-proxy and
# adds insecure-registries ONLY when REGISTRY is HTTP. The list is
# built with jq from the bash array to avoid hand-rolled JSON escaping
# bugs.
if (( ${#INSECURE_REGISTRIES[@]} > 0 )); then
  INSECURE_JSON=$(printf '%s\n' "${INSECURE_REGISTRIES[@]}" | jq -R . | jq -s .)
else
  INSECURE_JSON="[]"
fi

cat > /etc/docker/daemon.json <<DAEMON_EOF
{
  "iptables": true,
  "ip6tables": true,
  "userland-proxy": false,
  "insecure-registries": ${INSECURE_JSON}
}
DAEMON_EOF

systemctl enable --now docker
echo "Docker configured and started"
