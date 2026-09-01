#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 60-caddy — Provision the host's central Caddy reverse proxy.
#
# Installs to ~/infra/caddy (everything deploy-user owned — this step runs
# AS the deploy user), syncs the stack files, renders the Caddyfile
# template, and builds the custom Docker image. It NEVER starts a stopped
# container — bringing up the host's edge is an explicit operator action
# (`cd ~/infra/caddy && docker compose up -d`). When the container is
# already running, an update is applied in place (recreate on change) and
# routes.d replayed. Idempotent: safe to re-run.
#
# Also deploys the central-caddy agent skill (kilo/skills/ →
# ~/.kilo/skills/). The skill lives with this step — not in
# 37-kilo-settings — because it documents THIS host's central stack, so it
# is gated by the same .requires (docker + caddy) as the stack itself.
#
# Privileges needed: docker group membership (root tier, 50-docker) for
# docker/compose, and — only when the `public` capability is on — crowdsec
# group membership (root tier, 54-crowdsec) for `cscli bouncers add`.
#
# Run as the deploy user (./user/init.sh 60-caddy).

STACK_DIR="$HOME/infra/caddy"
EDGE_DIR="$HOME/infra/edge"
SRC_DIR="$(dirname "$0")/stack"

echo "=== 60-caddy: provisioning central Caddy ==="

# ---------------------------------------------------------------------------
# Step 0: Deploy the central-caddy agent skill (~/.kilo/skills/).
#
# Deliberately BEFORE the docker preflight: the skill is plain files with
# no dependency on the daemon, so a host with docker temporarily down still
# gets the context. sync_dir_preserve never deletes — user-installed skills
# survive re-runs.
# ---------------------------------------------------------------------------

sync_dir_preserve "$(dirname "$0")/kilo/skills" "$HOME/.kilo/skills"

# ---------------------------------------------------------------------------
# Preflight — docker daemon access, compose, jq, curl, envsubst.
# ---------------------------------------------------------------------------

for cmd in docker jq curl envsubst; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd not found" >&2; exit 1; }
done

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: cannot reach the docker daemon — is $USER in the docker group?" >&2
  echo "       (root tier 50-docker adds it; log out and back in to pick it up)" >&2
  exit 1
fi

docker compose version >/dev/null 2>&1 || { echo "ERROR: docker compose plugin not available" >&2; exit 1; }

# Compose runs from the live dir so default file discovery picks up
# compose.yaml + the operator's compose.override.yaml (§6.3) and .env.
# (Explicit `-f` would suppress override discovery.)
compose() {
  (cd "$STACK_DIR" && docker compose "$@")
}

# ---------------------------------------------------------------------------
# Step 1: Seed .env if absent.
# ---------------------------------------------------------------------------

if [[ ! -f "$STACK_DIR/.env" ]]; then
  echo "Seeding $STACK_DIR/.env from .env.example …"
  mkdir -p "$STACK_DIR"
  install -m 0600 "$SRC_DIR/.env.example" "$STACK_DIR/.env"
  echo "ACTION REQUIRED: edit $STACK_DIR/.env and fill ACME_EMAIL"
  echo ""
fi

# ---------------------------------------------------------------------------
# Step 2: CrowdSec bouncer key generation (when public cap is on and key is
# empty). cscli runs through passwordless sudo (root-tier 30-passwordless-sudo
# grants /usr/bin/cscli): on root-owned installs the cscli SQLite DB at
# /var/lib/crowdsec/data/ is root-owned and cscli chmods it on startup, which
# only root may do — crowdsec group membership is not sufficient.
# ---------------------------------------------------------------------------

if cap_enabled public; then
  if grep -q '^CROWDSEC_BOUNCER_KEY=$' "$STACK_DIR/.env" 2>/dev/null; then
    if command -v cscli >/dev/null 2>&1; then
      echo "Generating CrowdSec bouncer key for caddy-edge …"
      if ! bkey="$(sudo cscli bouncers add caddy-edge -o raw 2>/dev/null)"; then
        # A stale caddy-edge bouncer (e.g. from a previous partial run)
        # blocks re-creation by name — remove it and regenerate so the
        # step is self-healing instead of permanently running unprotected.
        sudo cscli bouncers delete caddy-edge >/dev/null 2>&1 || true
        bkey="$(sudo cscli bouncers add caddy-edge -o raw 2>/dev/null)" || bkey=""
      fi
      if [[ -n "$bkey" ]]; then
        # `|` delimiter: cscli keys are base64 (charset A-Za-z0-9+/=) —
        # a `/`-delimited s/// would break on most keys.
        sed -i "s|^CROWDSEC_BOUNCER_KEY=.*|CROWDSEC_BOUNCER_KEY=$bkey|" "$STACK_DIR/.env"
        # The bouncer key reaches the container via environment (compose.yaml:23)
        # — a container-env change only applies on recreate, so mark the compose
        # layer changed even though no stack file moved (R3).
        compose_changed=1
        echo "Bouncer key written to $STACK_DIR/.env"
      else
        echo "WARNING: sudo cscli failed — is /usr/bin/cscli in the passwordless sudo list (30-passwordless-sudo)? Running without CrowdSec" >&2
      fi
    else
      echo "WARNING: public cap enabled but cscli not found (54-crowdsec not run?) — running without CrowdSec"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Step 3: Create ~/infra/edge (static roots for file_server snippets).
# Mounted into the container at /srv/edge by compose.
# ---------------------------------------------------------------------------

if [[ ! -d "$EDGE_DIR" ]]; then
  mkdir -p "$EDGE_DIR"
  echo "Created $EDGE_DIR"
fi

# ---------------------------------------------------------------------------
# Step 4: Create edge network if absent.
#
# Subnet + gateway are PINNED: routes.d snippets may reference the gateway
# IP — e.g. the ci-dashboard mesh gate allows 172.24.0.1/32 so requests
# originating on this host (which hairpin through docker-proxy and arrive
# with the gateway as source IP) pass the gate. An auto-assigned subnet
# would silently break such snippets if the network were ever recreated.
# ---------------------------------------------------------------------------

if ! docker network inspect edge >/dev/null 2>&1; then
  docker network create edge --subnet 172.24.0.0/16 --gateway 172.24.0.1 >/dev/null
  echo "Created docker network: edge (172.24.0.0/16, gateway 172.24.0.1 — pinned)"
fi

# ---------------------------------------------------------------------------
# Step 5: Sync stack files (compare-before-write).
# ---------------------------------------------------------------------------

image_changed=0
compose_changed=0
config_changed=0

# sync_file src dst [mode] [flag]
#   flag: name of the change-flag to set on write (image_changed/compose_changed/
#   config_changed). Empty flag means "sync only, do not mark changed" — used for
#   build-context-only files (.dockerignore) whose content never affects the
#   running service and must not trigger a rebuild.
sync_file() {
  local src="$1" dst="$2" mode="${3:-0644}" flag="${4:-}"
  if [[ ! -f "$dst" ]]; then
    install -m "$mode" "$src" "$dst"
    [[ -n "$flag" ]] && declare -g "$flag=1"
    echo "new:  ${dst#"$STACK_DIR"/}"
  elif ! cmp -s "$src" "$dst"; then
    install -m "$mode" "$src" "$dst"
    [[ -n "$flag" ]] && declare -g "$flag=1"
    echo "diff: ${dst#"$STACK_DIR"/}"
  else
    echo "ok:   ${dst#"$STACK_DIR"/}"
  fi
}

mkdir -p "$STACK_DIR/bin" "$STACK_DIR/routes.d" "$STACK_DIR/logs"

sync_file "$SRC_DIR/Dockerfile"           "$STACK_DIR/Dockerfile"            0644 image_changed
sync_file "$SRC_DIR/compose.yaml"         "$STACK_DIR/compose.yaml"          0644 compose_changed
sync_file "$SRC_DIR/Caddyfile.tmpl"       "$STACK_DIR/Caddyfile.tmpl"        0644 config_changed
sync_file "$SRC_DIR/bin/caddy-route"      "$STACK_DIR/bin/caddy-route"       0755 config_changed
sync_file "$SRC_DIR/bin/acmedns-register" "$STACK_DIR/bin/acmedns-register"  0755 config_changed
sync_file "$SRC_DIR/.dockerignore"        "$STACK_DIR/.dockerignore"

# acmedns.json: seed as empty object if absent (compose volume mount needs a file).
if [[ ! -f "$STACK_DIR/acmedns.json" ]]; then
  echo '{}' > "$STACK_DIR/acmedns.json"
  chmod 0644 "$STACK_DIR/acmedns.json"
fi

# ---------------------------------------------------------------------------
# Step 6: ~/.local/bin/caddy-route symlink.
# ---------------------------------------------------------------------------

mkdir -p "$HOME/.local/bin"

if [[ ! -L "$HOME/.local/bin/caddy-route" ]]; then
  ln -sf "$STACK_DIR/bin/caddy-route" "$HOME/.local/bin/caddy-route"
  echo "Symlinked ~/.local/bin/caddy-route"
fi

# ---------------------------------------------------------------------------
# Step 7: Render Caddyfile.
# ---------------------------------------------------------------------------

read -r ACME_EMAIL < <(grep '^ACME_EMAIL=' "$STACK_DIR/.env" | cut -d= -f2-) || true
read -r CROWDSEC_BOUNCER_KEY < <(grep '^CROWDSEC_BOUNCER_KEY=' "$STACK_DIR/.env" | cut -d= -f2-) || true
read -r CROWDSEC_API_URL < <(grep '^CROWDSEC_API_URL=' "$STACK_DIR/.env" | cut -d= -f2-) || true

CROWDSEC_API_URL="${CROWDSEC_API_URL:-http://host.docker.internal:8080}"

if [[ -z "$ACME_EMAIL" ]]; then
  echo "NOTE: ACME_EMAIL is empty — cert issuance will fail."
  echo "      Edit $STACK_DIR/.env and re-run this step."
fi

template_text="$(cat "$SRC_DIR/Caddyfile.tmpl")"

# Caddy rejects a bare `email` line ("wrong argument count") — drop it when
# ACME_EMAIL is unset. Caddy runs fine without an ACME account email; the
# line returns on the next run once .env is filled.
if [[ -z "$ACME_EMAIL" ]]; then
  template_text="$(echo "$template_text" | grep -vF 'email ${ACME_EMAIL}')"
fi

if [[ -n "$CROWDSEC_BOUNCER_KEY" ]]; then
  crowdsec_block="	crowdsec {
		api_url ${CROWDSEC_API_URL}
		api_key {env.CROWDSEC_BOUNCER_KEY}
		ticker_interval 60s
	}
	order crowdsec first"
  template_text="${template_text/\$CROWDSEC_SECTION/$crowdsec_block}"
else
  # Drop the marker line entirely — a leftover blank line trips `caddy fmt`
  # warnings on every adapt.
  template_text="$(echo "$template_text" | grep -vF '$CROWDSEC_SECTION')"
fi

rendered="$(echo "$template_text" | ACME_EMAIL="$ACME_EMAIL" CROWDSEC_API_URL="$CROWDSEC_API_URL" envsubst '${ACME_EMAIL} ${CROWDSEC_API_URL}')"

if [[ ! -f "$STACK_DIR/Caddyfile" ]] || [[ "$(cat "$STACK_DIR/Caddyfile")" != "$rendered" ]]; then
  echo "$rendered" > "$STACK_DIR/Caddyfile"
  chmod 0644 "$STACK_DIR/Caddyfile"
  config_changed=1
  echo "Caddyfile rendered (new or changed)"
else
  echo "ok:   Caddyfile (render unchanged)"
fi

# ---------------------------------------------------------------------------
# Step 7.5: Render wildcard cert snippets from config.
# ---------------------------------------------------------------------------

wildcards="$(get_caddy_conf wildcards "")"

if [[ -z "$wildcards" ]]; then
  echo "NOTE: caddy.wildcards is empty or unset — no wildcard zones configured."
  echo "       Set wildcards labels in bootstrap.conf.yml to generate wildcard certs,"
  echo "       or set wildcards: \"\" to suppress this message."
else
  base_domain="$(get_caddy_conf base_domain "")"

  if [[ -z "$base_domain" ]]; then
    echo "NOTE: caddy.base_domain is empty or unset — skipping wildcard zone rendering."
    echo "       Set base_domain in bootstrap.conf.yml to define the zone apex."
  elif [[ ! -f "$STACK_DIR/acmedns.json" ]] || ! jq -e '. | keys | length > 0' "$STACK_DIR/acmedns.json" >/dev/null 2>&1; then
    echo "NOTE: acmedns.json is missing or empty — skipping wildcard zone rendering."
    echo "       Run bin/acmedns-register to create a real acme-dns account, then re-run this step."
  else
    active_labels=()
    invalid_labels=0
    # read -ra (not `for x in $wildcards`): an unquoted expansion would
    # pathname-expand glob chars in the config value against the CWD.
    read -ra wildcard_labels <<< "$wildcards"
    for label in "${wildcard_labels[@]}"; do
      if [[ ! "$label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
        echo "WARNING: ignoring invalid wildcard label '$label' — must match ^[a-z0-9]([a-z0-9-]*[a-z0-9])?\$" >&2
        invalid_labels=1
        continue
      fi
      if [[ "$label" == "host" ]]; then
        zone_fqdn="$(hostname).$base_domain"
      else
        zone_fqdn="$label.$base_domain"
      fi
      active_labels+=("$label")
      dest="$STACK_DIR/routes.d/${label}-wildcard.caddy"
      rendered="$(ZONE_FQDN="$zone_fqdn" envsubst '$ZONE_FQDN' < "$SRC_DIR/wildcard.caddy.tmpl")"
      if [[ ! -f "$dest" ]] || [[ "$(cat "$dest")" != "$rendered" ]]; then
        echo "$rendered" > "$dest"
        chmod 0644 "$dest"
        echo "Rendered wildcard zone: *.$zone_fqdn"
        config_changed=1
      fi
    done

    # Stale cleanup only runs when every configured label validated — a
    # config with rejected labels is suspect, and deleting zones based on
    # it could turn a typo into an outage. Fail safe: touch nothing.
    if [[ "$invalid_labels" -eq 1 ]]; then
      echo "NOTE: skipping stale wildcard cleanup until the invalid labels above are fixed."
    else
      for dest in "$STACK_DIR/routes.d/"*-wildcard.caddy; do
        [[ -f "$dest" ]] || continue
        fname="${dest##*/}"
        label="${fname%-wildcard.caddy}"
        found=0
        for a in "${active_labels[@]}"; do
          [[ "$a" == "$label" ]] && { found=1; break; }
        done
        if [[ "$found" -eq 0 ]]; then
          rm "$dest"
          echo "Removed stale wildcard zone: $fname"
          config_changed=1
        fi
      done
    fi
  fi
fi

if [[ -z "$wildcards" ]]; then
  for dest in "$STACK_DIR/routes.d/"*-wildcard.caddy; do
    [[ -f "$dest" ]] || continue
    rm "$dest"
    echo "Removed stale wildcard zone: ${dest##*/}"
    config_changed=1
  done
fi

# ---------------------------------------------------------------------------
# Step 7.6: Write discovery file — a well-known, machine-readable JSON blob
# that any project agent can read to discover the central Caddy instance.
# Path: ~/infra/caddy/central.json  (well-known: alongside the caddy stack)
# ---------------------------------------------------------------------------

central_json() {
  local was_running_d="${1:-0}"

  local docker_hostname
  docker_hostname="$(hostname)"

  jq -n --arg hostname "$docker_hostname" \
    --arg cli "$HOME/.local/bin/caddy-route" \
    --arg routes_dir "$STACK_DIR/routes.d" \
    --arg edge_dir "$EDGE_DIR" \
    --arg docs "~/bootstrap/docs/central-caddy.md" \
    --argjson running "$was_running_d" \
    '{
      "version": 1,
      "hostname": $hostname,
      "available": true,
      "container": {
        "name": "caddy",
        "network": "edge",
        "admin_socket": "/run/caddy-admin.sock",
        "admin_method": "docker exec caddy curl --unix-socket /run/caddy-admin.sock"
      },
      "registration": {
        "cli": $cli,
        "commands": {
          "register": "caddy-route register <app> <file.caddy>",
          "deregister": "caddy-route deregister <app>",
          "list": "caddy-route list",
          "reconcile": "caddy-route reconcile"
        },
        "routes_dir": $routes_dir
      },
      "backend_reachability": {
        "preferred": "join edge docker network, use container names in snippets",
        "fallback": "publish on 0.0.0.0, target host.docker.internal:<port> in snippets"
      },
      "snippet_contract": {
        "allowed": "site blocks only (no global blocks), reverse_proxy, file_server, matchers, handle, tls, log",
        "forbidden": "global blocks ({ ... }), global options (email, admin, storage, crowdsec)",
        "backend_format": "container-name:port on edge network",
        "tls_default": "automatic HTTP/TLS-ALPN for public names",
        "tls_dns01": "tls { dns acmedns /etc/caddy/acmedns.json } for wildcards or non-public names"
      },
      "static_assets": {
        "host_path": $edge_dir,
        "container_mount": "/srv/edge",
        "usage": "root * /srv/edge/<path> in file_server snippets"
      },
      "documentation": {
        "path": $docs,
        "description": "Full operator guide with snippet examples, TLS modes, day-2 ops"
      },
      "status": {
        "running": $running,
        "lifecycle_note": "provisioning step never starts a stopped container — explicit docker compose up -d required"
      }
    }' > "$STACK_DIR/central.json"
}

# ---------------------------------------------------------------------------
# Step 8: Rebuild policy (on change); apply only when already running. This
# step NEVER starts a stopped container — bringing up the host's edge is an
# explicit operator action (`docker compose up -d` in the live dir). When the
# container IS running, the operator already opted in: an update is applied
# in place and routes.d replayed.
#
# Image changes rebuild; compose (service) changes recreate; config-only
# changes hot-reload through the admin API — never a build or recreate, so
# edge connections survive. See §8 rebuild policy.
# ---------------------------------------------------------------------------

wait_healthy() {
  # Wait healthy (returns immediately when already healthy).
  echo "Waiting for caddy to become healthy …"
  local status=""
  for _i in $(seq 1 60); do
    status="$(docker inspect -f '{{.State.Health.Status}}' caddy 2>/dev/null)" || status=""
    if [[ "$status" == "healthy" ]]; then
      break
    fi
    sleep 1
  done
  if [[ "$status" != "healthy" ]]; then
    echo "ERROR: caddy did not become healthy after 60s" >&2
    docker logs caddy --tail 30 >&2
    exit 1
  fi
  echo "Caddy is healthy"
}

if [[ "$image_changed" -eq 1 ]]; then
  echo "Dockerfile changed — rebuilding image …"
  compose build

  # Wipe autosave + push hash so the next start replays the global config
  # from --config (never a stale --resume) and reconcile pushes exactly once.
  # `compose run` here is a transient, port-less utility container, not the
  # service — the service itself is not started.
  compose run --rm --no-deps --entrypoint rm caddy -f /config/autosave.json 2>/dev/null || true
  rm -f "$STACK_DIR/.last-pushed.sha256"
fi

# Sample running state only AFTER any build, which can take minutes: an
# operator may have stopped (or started) caddy mid-run, and this step must
# NEVER start a stopped container. was_running also gates every apply path
# and the post-condition checks below.
was_running=0
docker ps -q --filter 'name=^caddy$' 2>/dev/null | grep -q . && was_running=1

if [[ "$was_running" -eq 1 ]]; then
  if [[ "$image_changed" -eq 1 || "$compose_changed" -eq 1 ]]; then
    # Image or service config changed: recreate the container in place. up -d
    # recreates on change, carries the new image/env, no-op otherwise.
    if [[ "$image_changed" -eq 1 ]]; then
      compose up -d
    else
      # Compose-only change: `pull_policy: build` otherwise forces a rebuild
      # on `up -d` when the service definition changed. We only want a
      # recreate here — the image itself is unchanged (R2/R7: no rebuild for
      # a config-only service tweak).
      compose up -d --no-build
    fi
    wait_healthy
  elif [[ "$config_changed" -eq 1 ]]; then
    # Config-only change: hot-reload through the admin API. No build, no
    # recreate, no health wait — existing connections stay alive. The
    # reconcile hash-skip makes a converged push a no-op.
    echo "Configuration changed — hot-reloading via admin API …"
  else
    echo "No changes — caddy stack is up to date."
  fi

  # Replay routes.d. Conditional on any change: the hash-skip makes it a no-op
  # when converged, and running it on real change heals divergence — e.g. a
  # previous run that wiped autosave but aborted before its reconcile.
  if [[ "$image_changed" -eq 1 || "$compose_changed" -eq 1 || "$config_changed" -eq 1 ]]; then
    "$STACK_DIR/bin/caddy-route" reconcile
  fi
else
  echo ""
  echo "Caddy is provisioned but NOT started — this step never starts it automatically."
  if port_conflicts="$(ss -tlnH '( sport = :80 or sport = :443 )' 2>/dev/null)" && [[ -n "$port_conflicts" ]]; then
    echo ""
    echo "WARNING: ports 80/443 are currently in use by another service:" >&2
    ss -tlnpH '( sport = :80 or sport = :443 )' >&2 2>/dev/null || echo "$port_conflicts" >&2
    echo "Resolve the conflict (or remap ports via $STACK_DIR/compose.override.yaml) before starting." >&2
  fi
  echo ""
  echo "To bring it up:"
  echo "  cd $STACK_DIR && docker compose up -d"
  if [[ "$image_changed" -eq 1 || "$compose_changed" -eq 1 || "$config_changed" -eq 1 ]]; then
    echo "Config changed since it last ran — after starting, replay routes once:"
    echo "  caddy-route reconcile"
  fi
fi

# ---------------------------------------------------------------------------
# Step 9: Post-condition checks (only meaningful against a running container
# that we just mutated — a no-change run does zero work and skips these).
# ---------------------------------------------------------------------------

if [[ "$was_running" -eq 1 && ( "$image_changed" -eq 1 || "$compose_changed" -eq 1 || "$config_changed" -eq 1 ) ]]; then
  echo ""
  echo "=== Post-condition assertions ==="

  # Validate rendered Caddyfile adapts.
  if docker exec caddy caddy adapt --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1; then
    echo "  PASS: Caddyfile adapts"
  else
    echo "  FAIL: Caddyfile does not adapt:"
    docker exec caddy caddy adapt --config /etc/caddy/Caddyfile --adapter caddyfile 2>&1 || true
    exit 1
  fi

  # CrowdSec bouncer link — when a key is configured, prove decisions
  # actually stream from the host LAPI into caddy. The bouncer plugin is
  # fail-open (enable_hard_fails off), so a broken link is SILENT: caddy
  # keeps serving with zero protection. This assertion is the only thing
  # that catches it. The stream bouncer connects on its own retry loop —
  # allow a few ticker intervals (ticker_interval 60s) before failing.
  if [[ -n "$CROWDSEC_BOUNCER_KEY" ]]; then
    cs_healthy=0
    for _i in $(seq 1 12); do
      if docker exec caddy caddy crowdsec health --address unix//run/caddy-admin.sock >/dev/null 2>&1; then
        cs_healthy=1
        break
      fi
      sleep 5
    done
    if [[ "$cs_healthy" -eq 1 ]]; then
      echo "  PASS: CrowdSec bouncer link healthy (decisions streaming from host LAPI)"
    else
      echo "  FAIL: 'caddy crowdsec health' did not pass within 60s" >&2
      echo "        The edge is running UNPROTECTED — the bouncer fails open." >&2
      echo "        Diagnose:" >&2
      echo "          docker exec caddy caddy crowdsec ping --address unix//run/caddy-admin.sock" >&2
      echo "          cscli bouncers list                 (is caddy-edge registered?)" >&2
      echo "          grep listen_uri /etc/crowdsec/config.yaml   (0.0.0.0:8080? — root-tier 54-crowdsec)" >&2
      echo "          ufw status | grep 8080            (docker bridges allowed? — 54-crowdsec)" >&2
      exit 1
    fi
  fi

  # Verify route listing works.
  if "$STACK_DIR/bin/caddy-route" list >/dev/null 2>&1; then
    echo "  PASS: caddy-route list works"
  else
    echo "  WARNING: caddy-route list failed"
  fi
fi

# ---------------------------------------------------------------------------
# Step 9.5: Write the discovery file exactly once, with the final running
# state. Skipped when nothing changed AND the recorded state already matches
# (avoids rewriting central.json every no-op run — R6).
# ---------------------------------------------------------------------------

if [[ "$image_changed" -eq 1 || "$compose_changed" -eq 1 || "$config_changed" -eq 1 ]] \
   || [[ ! -f "$STACK_DIR/central.json" ]] \
   || [[ "$(jq -r '.status.running' "$STACK_DIR/central.json" 2>/dev/null)" != "$was_running" ]]; then
  central_json "$was_running"
fi

echo ""
echo "60-caddy complete."
