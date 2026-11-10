# Central Caddy IPv6 ingress failure

Observed on 2026-10-22 around 23:55 UTC for `https://dash.birb.gsit.ca/`.
This is a bootstrap/host-edge issue, not a NetBird dashboard route issue.

## Evidence

- DNS A: `178.128.225.92`; AAAA: `2604:a880:cad:d0:0:1:91f2:1` (assigned to host `eth0`).
- `curl -4 https://dash.birb.gsit.ca/` returned HTTP 200 with a valid certificate;
  `curl -6` failed to connect to the published AAAA address on port 443 with
  `Connection refused`. A direct local Caddy request also returned HTTP 200.
- Central Caddy and both NetBird Compose services were running. The Caddy
  container health check was healthy, but it checks the internal Admin API,
  not public IPv6 reachability.
- `ss -ltn6 '( sport = :443 or sport = :80 )'` showed no IPv6 listener.
  `docker inspect caddy` showed the effective published ports only on
  `0.0.0.0`, even though `HostConfig.PortBindings` and the resolved
  `~/infra/caddy/compose.yaml` include `[::]:80` and `[::]:443`.
- `docker network inspect edge` reported `EnableIPv6=false` and only the pinned
  IPv4 subnet `172.24.0.0/16` with gateway `172.24.0.1`. `/etc/docker/daemon.json`
  sets `"ipv6": true`, `"ip6tables": true`, and `"userland-proxy": false`.

## Bootstrap fix to investigate

`user/init.d/60-caddy/run.sh` step 4 creates `edge` using only
`docker network create edge --subnet 172.24.0.0/16 --gateway 172.24.0.1`.
The existing-network branch checks only for existence. The Compose template
at `user/init.d/60-caddy/stack/compose.yaml` already requests IPv4 and IPv6
publishes, so editing `Caddyfile.tmpl` is not the fix. Determine and implement
the Docker-supported IPv6 setup for the shared `edge` network with a suitable
non-overlapping IPv6 subnet and gateway. Confirm that Docker actually creates
IPv6 host listeners/forwarding with userland proxy disabled; do not assume
that declaring `[::]` ports is sufficient.

Preserve the pinned IPv4 subnet/gateway: route snippets can depend on
`172.24.0.1`. For an existing IPv4-only `edge`, fail with an explicit migration
instruction rather than silently accepting it or deleting/recreating a network
with attached application containers. Network migration affects central Caddy
and every service attached to `edge`; schedule downtime and inventory attached
containers first. Avoid changing the host daemon or firewall blindly; verify
IPv6 forwarding and host/provider firewall policy as part of rollout.

## Acceptance checks

1. On a disposable host, provision central Caddy and confirm
   `docker network inspect edge` reports IPv6 enabled while retaining
   `172.24.0.0/16` and `172.24.0.1`.
2. Confirm an IPv6 listener/working published port on 80 and 443, then run
   `curl -6 -v https://dash.birb.gsit.ca/` from an independent IPv6-capable
   client; expect valid TLS and HTTP 200. A same-host probe alone does not
   prove external firewall or provider reachability.
3. Confirm IPv4 still returns 200, Caddy routes remain registered, and the
   dashboard and NetBird server remain reachable through their intended names.
4. Test the existing IPv4-only network upgrade path without removing attached
   containers automatically. Keep the AAAA record only when external IPv6
   verification succeeds.

Separate observation: Caddy repeatedly timed out connecting to CrowdSec LAPI
at `172.17.0.1:8080`; its bouncer is fail-open. Investigate independently from
the IPv6 ingress fix.
