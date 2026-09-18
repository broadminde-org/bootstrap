#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 54-crowdsec — Install CrowdSec LAPI and the firewall bouncer on the host.
#
# CrowdSec is a collaborative intrusion-prevention system. The LAPI
# (Local API) collects signals from parsers and scenarios, shares threat
# intel via the CrowdSec Central API, and drives the firewall bouncer.
# The crowdsec-firewall-bouncer-iptables translates ban decisions into
# iptables DROP rules directly — complementing (not replacing) ufw.
#
# What this script does:
#
#   1. Registers the CrowdSec packagecloud apt repo via their bootstrap
#      script. See supply-chain note below.
#
#   2. Installs crowdsec and crowdsec-firewall-bouncer-iptables.
#
#   2b. Binds the LAPI to 0.0.0.0:8080 so docker containers (central
#      caddy) can reach it via host.docker.internal — the Debian default
#      127.0.0.1:8080 refuses non-loopback connections. Exposure is scoped
#      by the ufw rule in Step 2c.
#
#   2c. Allows 172.16.0.0/12 → 8080/tcp in ufw so container→host LAPI
#      packets traverse the INPUT chain (ufw default-deny applies).
#
#   3. Installs the crowdsecurity/sshd and crowdsecurity/caddy
#      collections (parsers + scenarios for those services).
#
#   4. Manages the Caddy JSON log source as a drop-in at
#      /etc/crowdsec/acquis.d/caddy-central.yaml so CrowdSec tails the
#      access log once Phase 2 is applied. The path resolves via the
#      shared lib/caddy-log.sh (same as 53-fail2ban): $CADDY_LOG_PATH
#      env override, then whichever of the central (~/infra/caddy) or
#      legacy (netbird-docker) log is live — fresher mtime when both
#      exist — then central as the new-host default. The drop-in is
#      rewritten (never appended) when the resolution changes, blocks
#      previously appended to acquis.yaml are stripped, and the daemon
#      is restarted when the config changed on a running daemon.
#      CrowdSec tolerates a missing log file — it emits a warning but
#      does NOT hard-fail — so this step is safe to run before Phase 2.
#
#   4b. Adds the deploy user to the crowdsec group and makes the
#      config/credential files group-readable (diagnostics). cscli
#      MANAGEMENT commands still require root on root-owned installs —
#      user-tier 60-caddy uses passwordless sudo for bouncer key
#      generation (30-passwordless-sudo grants /usr/bin/cscli).
#
#   5. Enables and starts both services.
#
# Supply-chain note:
#   The apt repository is registered by THIS step directly (keyring +
#   sources.list, the same pattern as 59-gh-cli) — vendored from the
#   Debian branch of the official https://install.crowdsec.net script.
#   No remote script is piped to a root shell: apt verifies every
#   package against the packagecloud GPG key installed here. The "any/
#   any" suite avoids the Debian trixie 404 the legacy packagecloud
#   bootstrap produced. A deb-src entry is deliberately omitted (binary
#   installs only; fewer indexes to fetch).
#
# Run as root (sudo ./init.sh 54-crowdsec).

ACQUIS_YAML=/etc/crowdsec/acquis.yaml
ACQUIS_D=/etc/crowdsec/acquis.d
CADDY_ACQUIS_DROPIN=caddy-central.yaml

# Caddy JSON log path — resolved by the shared lib/caddy-log.sh (same
# resolution as 53-fail2ban so both IPS layers always tail the same file):
# CADDY_LOG_PATH env override, then whichever of the central (~/infra/caddy)
# or legacy (netbird-docker) log is the live one (mtime when both exist),
# then the central path as the default for new hosts. Resolved into a
# step-local variable — the operator's CADDY_LOG_PATH is never clobbered.
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/caddy-log.sh"
resolve_caddy_log RESOLVED_CADDY_LOG

echo "=== 54-crowdsec: adding CrowdSec apt repository ==="

# ---------------------------------------------------------------------------
# Step 1: Register the CrowdSec apt repo — vendored from the Debian
# branch of the official install script (keyring + signed-by sources
# entry). Idempotent via compare-before-write. No `curl | bash`.
# ---------------------------------------------------------------------------

DISTRO="$({ . /etc/os-release; printf '%s' "${ID:-}"; })"
case "$DISTRO" in
  debian|ubuntu) ;;
  *)
    echo "ERROR: 54-crowdsec supports Debian and Ubuntu only (detected: ${DISTRO:-unknown})." >&2
    exit 1
    ;;
esac

KEYRING_DIR=/etc/apt/keyrings
KEYRING="$KEYRING_DIR/crowdsec_crowdsec-archive-keyring.gpg"
SOURCE_LIST=/etc/apt/sources.list.d/crowdsec_crowdsec.list
KEY_URL="https://packagecloud.io/crowdsec/crowdsec/gpgkey"

apt-get install -y ca-certificates curl gpg
install -d -m 0755 "$KEYRING_DIR" /etc/apt/sources.list.d

tmp_key="$(mktemp)"
trap 'rm -f "$tmp_key" "$tmp_key.raw"' EXIT
curl -fsSL --retry 3 --proto '=https' "$KEY_URL" -o "$tmp_key.raw"
gpg --batch --dearmor < "$tmp_key.raw" > "$tmp_key"

if [[ ! -f "$KEYRING" ]] || ! cmp -s "$tmp_key" "$KEYRING"; then
  install -m 0644 "$tmp_key" "$KEYRING"
  echo "Installed CrowdSec APT keyring."
else
  echo "CrowdSec APT keyring already current."
fi
rm -f "$tmp_key" "$tmp_key.raw"
trap - EXIT

source_line="deb [signed-by=$KEYRING] https://packagecloud.io/crowdsec/crowdsec/any/ any main"
if [[ ! -f "$SOURCE_LIST" ]] || [[ "$(cat "$SOURCE_LIST")" != "$source_line" ]]; then
  printf '%s\n' "$source_line" > "$SOURCE_LIST"
  chmod 0644 "$SOURCE_LIST"
  echo "Configured CrowdSec APT repository."
else
  echo "CrowdSec APT repository already configured."
fi

apt-get update

# ---------------------------------------------------------------------------
# Step 2: Install CrowdSec and the iptables firewall bouncer.
# ---------------------------------------------------------------------------

echo ""
echo "=== 54-crowdsec: installing packages ==="
apt-get install -y crowdsec crowdsec-firewall-bouncer-iptables

# ---------------------------------------------------------------------------
# Step 2b: Make the LAPI reachable from docker containers.
#
# The central Caddy container's bouncer streams decisions from the host LAPI
# at http://host.docker.internal:8080 (user/init.d/60-caddy). host-gateway
# resolves to a bridge gateway address (e.g. 172.x.0.1), NOT loopback — and
# the Debian default `listen_uri: 127.0.0.1:8080` refuses those connections.
# Bind 0.0.0.0 and let ufw (step 2c) scope exposure to the docker bridges.
# The host's firewall bouncer keeps using loopback — unaffected.
# ---------------------------------------------------------------------------

CONFIG_YAML=/etc/crowdsec/config.yaml
lapi_changed=0

if grep -qE '^[[:space:]]*listen_uri:[[:space:]]*0\.0\.0\.0:8080' "$CONFIG_YAML"; then
  echo "LAPI listen_uri already 0.0.0.0:8080 — skipping"
elif grep -qE '^[[:space:]]*listen_uri:[[:space:]]*127\.0\.0\.1:8080' "$CONFIG_YAML"; then
  sed -i.crowdsec-bak -E \
    's|^([[:space:]]*)listen_uri:[[:space:]]*127\.0\.0\.1:8080|\1listen_uri: 0.0.0.0:8080  # managed by bootstrap/init.d/54-crowdsec — docker-bridge reachable, exposure scoped by ufw|' \
    "$CONFIG_YAML"
  echo "listen_uri: 127.0.0.1:8080 → 0.0.0.0:8080 (backup: ${CONFIG_YAML}.crowdsec-bak)"
  lapi_changed=1
else
  echo "WARNING: listen_uri is neither 127.0.0.1:8080 nor 0.0.0.0:8080 — leaving untouched:" >&2
  grep -E '^[[:space:]]*listen_uri:' "$CONFIG_YAML" >&2
fi

# ---------------------------------------------------------------------------
# Step 2c: Allow docker bridge traffic to the LAPI (ufw).
#
# Container → host LAPI packets traverse the INPUT chain, where ufw's
# default-deny applies. Allow only the RFC1918 docker bridge range; external
# exposure stays denied by policy. `ufw allow` stages the rule whether or not
# ufw is active yet (52-ufw stages rules, then enables ufw once the SSH rule
# is verified), so ordering against ufw activation does not matter. IPv6: the
# `edge` network is v4-only today — add a matching fd00::/8 rule if that
# ever changes.
# ---------------------------------------------------------------------------

if command -v ufw >/dev/null 2>&1; then
  if ! ufw show added 2>/dev/null | grep -q 'CrowdSec LAPI'; then
    ufw allow from 172.16.0.0/12 to any port 8080 proto tcp comment 'CrowdSec LAPI from docker bridges'
    echo "ufw: allowed 172.16.0.0/12 → 8080/tcp (docker bridges)"
  else
    echo "ufw: LAPI rule already present — skipping"
  fi
  if ! ufw status 2>/dev/null | grep -q 'Status: active'; then
    echo "WARNING: ufw is installed but NOT active — LAPI binds 0.0.0.0:8080 with no firewall filter (run 52-ufw to stage and enable ufw)" >&2
  fi
fi

# ---------------------------------------------------------------------------
# Step 3: Install sshd and caddy collections.
# cscli install is idempotent — already-installed collections are skipped.
# ---------------------------------------------------------------------------

echo ""
echo "=== 54-crowdsec: installing collections ==="
cscli collections install crowdsecurity/sshd
cscli collections install crowdsecurity/caddy

# ---------------------------------------------------------------------------
# Step 4: Manage the Caddy log source as an acquis.d drop-in.
#
# Earlier revisions appended a static block to acquis.yaml, which could never
# remove a stale path and never restarted the daemon. The drop-in is rewritten
# each run, so a changed resolution replaces the source; any block previously
# appended to acquis.yaml is stripped. crowdsec is restarted at the end of
# the step when this config changed on an already-running daemon (CrowdSec
# does not watch acquis files — a source change without a restart is inert).
#
# NOTE: This log path only exists after Phase 2 (Caddy logging) is complete
# and the caddy container has been restarted. If 54-crowdsec runs before
# Phase 2, CrowdSec will emit a warning on every reload but will NOT
# hard-fail — this is expected and harmless until Phase 2 is applied.
# ---------------------------------------------------------------------------

echo ""
echo "=== 54-crowdsec: managing Caddy log source (${ACQUIS_D}/${CADDY_ACQUIS_DROPIN}) ==="

acquis_changed=0
cs_was_active=0
systemctl is-active --quiet crowdsec && cs_was_active=1

# 4a. Strip any Caddy block previously appended to acquis.yaml. The appended
# block had a fixed shape: `---` / `filenames:` / one-or-more `  - <path>`
# lines / `labels:` / `  type: caddy`. Only exact-shape caddy docs are
# removed. The rewrite is atomic: filter to a temp file, then `install`
# over the original (preserving its mode) so a crash mid-write can never
# leave a truncated acquis.yaml.
if grep -q 'type: caddy' "$ACQUIS_YAML" 2>/dev/null; then
  tmp_acquis="$(mktemp "${ACQUIS_YAML}.bootstrap-tmp.XXXXXX")"
  awk '
    /^---[[:space:]]*$/              { buf=$0; state=1; next }
    state==1 && /^filenames:[[:space:]]*$/ { buf=buf "\n" $0; state=2; next }
    state==2 && /^[[:space:]]+-[[:space:]]/ { buf=buf "\n" $0; next }
    state==2 && /^labels:[[:space:]]*$/    { buf=buf "\n" $0; state=3; next }
    state==3 && /^[[:space:]]+type:[[:space:]]+caddy[[:space:]]*$/ { state=0; buf=""; next }
    state>0 { printf "%s\n", buf; buf=""; state=0 }
    { print }
    END { if (buf != "") printf "%s\n", buf }
  ' "$ACQUIS_YAML" > "$tmp_acquis"
  install -m "$(stat -c '%a' "$ACQUIS_YAML")" "$tmp_acquis" "$ACQUIS_YAML"
  rm -f "$tmp_acquis"
  echo "Removed previously appended Caddy source from ${ACQUIS_YAML} (now managed in acquis.d)"
  acquis_changed=1
fi

# 4b. Write/replace the managed drop-in when the resolved path differs.
mkdir -p "$ACQUIS_D"
if [[ ! -f "$ACQUIS_D/$CADDY_ACQUIS_DROPIN" ]] || ! grep -qF "  - $RESOLVED_CADDY_LOG" "$ACQUIS_D/$CADDY_ACQUIS_DROPIN" 2>/dev/null; then
  cat > "$ACQUIS_D/$CADDY_ACQUIS_DROPIN" <<ACQUIS_EOF
# Managed by bootstrap/init.d/54-crowdsec. Do not edit by hand — rewritten each run.
filenames:
  - $RESOLVED_CADDY_LOG
labels:
  type: caddy
ACQUIS_EOF
  echo "Wrote ${ACQUIS_D}/${CADDY_ACQUIS_DROPIN} (path: $RESOLVED_CADDY_LOG)"
  acquis_changed=1
else
  echo "Caddy log source already current — skipping"
fi

# ---------------------------------------------------------------------------
# Step 4b: crowdsec group membership + readable config files.
#
# Group membership lets the deploy user READ crowdsec config and logs (useful
# for diagnostics). It does NOT make `cscli` management commands work on
# root-owned installs: cscli opens the SQLite DB at /var/lib/crowdsec/data/
# read-write and chmods it on startup, and chmod is owner-only — when the
# daemon runs as root (no crowdsec service user), the DB is root-owned and
# only root can manage bouncers/machines. user-tier 60-caddy therefore runs
# cscli through passwordless sudo (30-passwordless-sudo grants /usr/bin/cscli).
#
# The crowdsec group may not exist after package install (Debian packaging
# quirk) — create it idempotently before adding the user.
# ---------------------------------------------------------------------------

if ! getent group crowdsec >/dev/null 2>&1; then
  groupadd --system crowdsec
  echo "Created crowdsec system group"
fi

if [[ -n "${SUDO_USER:-}" ]]; then
  usermod -aG crowdsec "$SUDO_USER"
  echo "Added $SUDO_USER to the crowdsec group (config/log read access)"
fi

# Make config + credentials group-readable for diagnostics. chown/chmod are
# idempotent. This is deliberately NOT sufficient for cscli management
# commands on root-owned installs — see the header comment above.
#
# DELIBERATE CHOICE: 0640 root:crowdsec on local_api_credentials.yaml and
# online_api_credentials.yaml widens LAPI/CAPI credential reads to anyone in
# the crowdsec group (which the deploy user joins below). Accepted because
# these credentials only authenticate to the LOCAL LAPI and CrowdSec's CAPI
# enrollment — they do not grant host management. Do not extend this
# pattern to other files without the same analysis.
for f in /etc/crowdsec/config.yaml \
         /etc/crowdsec/local_api_credentials.yaml \
         /etc/crowdsec/online_api_credentials.yaml; do
  if [[ -f "$f" ]]; then
    chown root:crowdsec "$f"
    chmod 0640 "$f"
  fi
done
echo "Reconciled crowdsec config/credential files to root:crowdsec 0640"

# ---------------------------------------------------------------------------
# Step 5: Enable and start CrowdSec LAPI.
# ---------------------------------------------------------------------------

echo ""
echo "=== 54-crowdsec: enabling crowdsec ==="
systemctl enable --now crowdsec

# Restart when the Caddy acquisition config changed on an already-running
# daemon — CrowdSec does not watch acquis files, so a path change (e.g.
# legacy→central during the migration) is silently inert until a restart.
if [[ "$((acquis_changed + lapi_changed))" -gt 0 && "$cs_was_active" -eq 1 ]]; then
  echo "CrowdSec config changed — restarting crowdsec"
  systemctl restart crowdsec
fi

# ---------------------------------------------------------------------------
# Step 6: Enable and start the firewall bouncer.
# ---------------------------------------------------------------------------

echo ""
echo "=== 54-crowdsec: enabling crowdsec-firewall-bouncer ==="
systemctl enable --now crowdsec-firewall-bouncer

# ---------------------------------------------------------------------------
# Step 7: Post-condition assertions.
# ---------------------------------------------------------------------------

echo ""
echo "=== Post-condition assertions ==="

cscli version || { echo "ERROR: cscli not functional" >&2; exit 1; }
echo "  PASS: cscli is functional"

# cscli management commands require root on root-owned installs (see Step
# 4b header) — there is no effective-user cscli assertion here by design.
# The 60-caddy user step exercises `sudo cscli` end-to-end when it
# generates the bouncer key.

systemctl is-active crowdsec || { echo "ERROR: crowdsec service not active" >&2; exit 1; }
echo "  PASS: crowdsec is active"

systemctl is-active crowdsec-firewall-bouncer || { echo "ERROR: crowdsec-firewall-bouncer not active" >&2; exit 1; }
echo "  PASS: crowdsec-firewall-bouncer is active"

# LAPI listens on all interfaces (docker-bridge reachable).
# `ss` formats wildcard binds differently across versions: `0.0.0.0:8080`,
# `[::]:8080`, or `*:8080`. All three accept docker-bridge traffic.
if ss -tlnH 'sport = :8080' | grep -qE '(0\.0\.0\.0:8080|\[::\]:8080|\*:8080)'; then
  echo "  PASS: LAPI listening on wildcard :8080 (docker-bridge reachable)"
else
  echo "  FAIL: LAPI not listening on a wildcard :8080 — central caddy cannot reach it" >&2
  echo "  Current 8080 listeners:" >&2
  ss -tlnH 'sport = :8080' >&2
  exit 1
fi

echo ""
echo "54-crowdsec complete."
