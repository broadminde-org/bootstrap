#!/usr/bin/env bash
set -euo pipefail

# One-time migration of the central edge bridge on hosts with the Caddy and
# NetBird Compose projects. Run as the deploy user, never through sudo.
if (( EUID == 0 )); then
  echo 'ERROR: run as the deploy user with Docker access, not root.' >&2
  exit 1
fi
for cmd in docker jq curl; do
  command -v "$cmd" >/dev/null || { echo "ERROR: missing $cmd" >&2; exit 1; }
done
docker info >/dev/null
docker compose version >/dev/null

caddy_dir="$HOME/infra/caddy"
netbird_dir="$HOME/netbird-docker"
for path in "$caddy_dir/compose.yaml" "$netbird_dir/docker-compose.yml"; do
  [[ -f "$path" ]] || { echo "ERROR: missing $path" >&2; exit 1; }
done
caddy() { docker compose --project-directory "$caddy_dir" "$@"; }
netbird() { docker compose --project-directory "$netbird_dir" -f "$netbird_dir/docker-compose.yml" "$@"; }
caddy config -q
netbird config -q

v6_subnet=fd42:1724:0:1::/64
v6_gateway=fd42:1724:0:1::1

if docker network inspect edge >/dev/null 2>&1; then
  if ! docker network inspect edge | jq -e '
    .[0].Driver == "bridge" and
    ([.[0].IPAM.Config[] | select(.Subnet == "172.24.0.0/16" and .Gateway == "172.24.0.1")] | length == 1)
  ' >/dev/null; then
    echo 'ERROR: edge is not the expected bridge with pinned IPv4 addressing.' >&2
    exit 1
  fi

  if docker network inspect edge | jq -e --arg subnet "$v6_subnet" --arg gateway "$v6_gateway" '
    .[0].EnableIPv6 == true and
    ([.[0].IPAM.Config[] | select(.Subnet == $subnet and .Gateway == $gateway)] | length == 1)
  ' >/dev/null; then
    echo 'edge is already dual-stack; ensuring Compose services are running.'
  elif docker network inspect edge | jq -e '.[0].EnableIPv6 == true' >/dev/null; then
    echo 'ERROR: edge already has IPv6, but not the bootstrap-pinned subnet/gateway.' >&2
    exit 1
  else

  mapfile -t attached < <(docker network inspect edge --format '{{range .Containers}}{{println .Name}}{{end}}')
  for name in "${attached[@]}"; do
    case "$name" in
      caddy|netbird-docker-dashboard-1|netbird-docker-netbird-server-1) ;;
      *) echo "ERROR: unexpected edge attachment $name; refusing migration." >&2; exit 1 ;;
    esac
  done
  # Refuse to remove a similarly named container owned by another project.
  for name in "${attached[@]}"; do
    case "$name" in
      caddy) project=caddy; service=caddy ;;
      netbird-docker-dashboard-1) project=netbird-docker; service=dashboard ;;
      netbird-docker-netbird-server-1) project=netbird-docker; service=netbird-server ;;
    esac
    if [[ "$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}:{{index .Config.Labels "com.docker.compose.service"}}' "$name")" != "$project:$service" ]]; then
      echo "ERROR: $name is not the expected Compose service." >&2
      exit 1
    fi
  done

  echo 'Stopping and removing only the Caddy, dashboard, and NetBird server containers.'
  caddy stop caddy
  netbird stop dashboard netbird-server
  caddy rm -f caddy
  netbird rm -f dashboard netbird-server
  docker network rm edge
  fi
fi

if ! docker network inspect edge >/dev/null 2>&1; then
  echo 'Creating the pinned dual-stack edge bridge.'
  docker network create --ipv6 \
    --subnet 172.24.0.0/16 --gateway 172.24.0.1 \
    --subnet "$v6_subnet" --gateway "$v6_gateway" edge >/dev/null
fi

echo 'Recreating NetBird services and central Caddy without deleting volumes.'
netbird up -d --no-deps --no-build dashboard netbird-server
caddy up -d --no-deps --no-build caddy

if ! docker inspect caddy | jq -e '
  .[0].NetworkSettings.Ports as $ports |
  all(["80/tcp", "443/tcp"][]; . as $port |
    any($ports[$port][]?; .HostIp == "::" and .HostPort == ($port | split("/")[0])))
' >/dev/null; then
  echo 'ERROR: Caddy has no effective IPv6 bindings for ports 80 and 443.' >&2
  exit 1
fi
curl -6 -sS --noproxy '*' --max-time 5 -o /dev/null 'http://[::1]/'
curl -6 -sS --noproxy '*' --max-time 5 --connect-only 'http://[::1]:443/'
echo 'Local IPv6 ports 80/443 reachable. Verify TLS and HTTP from an independent IPv6 client.'
