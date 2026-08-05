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
# empty). cscli access comes from the crowdsec group (54-crowdsec).
# ---------------------------------------------------------------------------

if cap_enabled public; then
  if grep -q '^CROWDSEC_BOUNCER_KEY=$' "$STACK_DIR/.env" 2>/dev/null; then
    if command -v cscli >/dev/null 2>&1; then
      echo "Generating CrowdSec bouncer key for caddy-edge …"
      if ! bkey="$(cscli bouncers add caddy-edge -o raw 2>/dev/null)"; then
        # A stale caddy-edge bouncer (e.g. from a previous partial run)
        # blocks re-creation by name — remove it and regenerate so the
        # step is self-healing instead of permanently running unprotected.
        cscli bouncers delete caddy-edge >/dev/null 2>&1 || true
        bkey="$(cscli bouncers add caddy-edge -o raw 2>/dev/null)" || bkey=""
      fi
      if [[ -n "$bkey" ]]; then
        # `|` delimiter: cscli keys are base64 (charset A-Za-z0-9+/=) —
        # a `/`-delimited s/// would break on most keys.
        sed -i "s|^CROWDSEC_BOUNCER_KEY=.*|CROWDSEC_BOUNCER_KEY=$bkey|" "$STACK_DIR/.env"
        echo "Bouncer key written to $STACK_DIR/.env"
      else
        echo "WARNING: cscli failed — is $USER in the crowdsec group (54-crowdsec)? Running without CrowdSec" >&2
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
# ---------------------------------------------------------------------------

if ! docker network inspect edge >/dev/null 2>&1; then
  docker network create edge >/dev/null
  echo "Created docker network: edge"
fi

# ---------------------------------------------------------------------------
# Step 5: Sync stack files (compare-before-write).
# ---------------------------------------------------------------------------

changed=0

sync_file() {
  local src="$1" dst="$2" mode="${3:-0644}"
  if [[ ! -f "$dst" ]] || ! cmp -s "$src" "$dst"; then
    install -m "$mode" "$src" "$dst"
    changed=1
  fi
}

mkdir -p "$STACK_DIR/bin" "$STACK_DIR/routes.d" "$STACK_DIR/logs"

sync_file "$SRC_DIR/Dockerfile"           "$STACK_DIR/Dockerfile"
sync_file "$SRC_DIR/compose.yaml"         "$STACK_DIR/compose.yaml"
sync_file "$SRC_DIR/Caddyfile.tmpl"       "$STACK_DIR/Caddyfile.tmpl"
sync_file "$SRC_DIR/bin/caddy-route"      "$STACK_DIR/bin/caddy-route"      0755
sync_file "$SRC_DIR/bin/acmedns-register" "$STACK_DIR/bin/acmedns-register" 0755

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
  changed=1
  echo "Caddyfile rendered"
fi

# ---------------------------------------------------------------------------
# Step 8: Build + autosave hygiene (on change); apply only when already
# running. This step NEVER starts a stopped container — bringing up the
# host's edge is an explicit operator action (`docker compose up -d` in the
# live dir). When the container IS running, the operator already opted in:
# an update is applied in place (recreate on change) and routes.d replayed.
# ---------------------------------------------------------------------------

if [[ "$changed" -eq 1 ]]; then
  echo "Configuration changed — rebuilding …"

  compose build

  # Wipe autosave + push hash so the next start replays the global config
  # from --config (never a stale --resume) and reconcile pushes exactly once.
  # `compose run` here is a transient, port-less utility container, not the
  # service — the service itself is not started.
  compose run --rm --no-deps --entrypoint rm caddy -f /config/autosave.json 2>/dev/null || true
  rm -f "$STACK_DIR/.last-pushed.sha256"
else
  echo "No changes — caddy stack is up to date."
fi

# Sample running state only AFTER the build, which can take minutes: an
# operator may have stopped (or started) caddy mid-run, and this step must
# NEVER start a stopped container. was_running also gates the post-condition
# checks below.
was_running=0
docker ps -q --filter 'name=^caddy$' 2>/dev/null | grep -q . && was_running=1

if [[ "$was_running" -eq 1 ]]; then
  # Already running (operator opted in): apply in place. up -d recreates on
  # config change, no-op when already current.
  compose up -d

  # Wait healthy (returns immediately when already healthy).
  echo "Waiting for caddy to become healthy …"
  status=""
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

  # Replay routes.d. Unconditional: the hash-skip makes it a no-op when
  # converged, and running it every time heals divergence — e.g. a previous
  # run that wiped autosave but aborted before its reconcile.
  "$STACK_DIR/bin/caddy-route" reconcile
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
  if [[ "$changed" -eq 1 ]]; then
    echo "Config changed since it last ran — after starting, replay routes once:"
    echo "  caddy-route reconcile"
  fi
fi

# ---------------------------------------------------------------------------
# Step 9: Post-condition checks (only meaningful against a running container).
# ---------------------------------------------------------------------------

if [[ "$was_running" -eq 1 ]]; then
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

echo ""
echo "60-caddy complete."
