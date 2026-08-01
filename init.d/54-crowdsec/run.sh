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
#   4b. Adds the deploy user to the crowdsec group so `cscli` works
#      without sudo (user-tier 60-caddy generates its bouncer key this
#      way). local_api_credentials.yaml is root:crowdsec 0640.
#
#   5. Enables and starts both services.
#
# Supply-chain note:
#   The official CrowdSec install script (step 1) is piped directly to bash
#   as root. This is the same pattern used by 50-docker for the Docker
#   GPG key step. Review the script at
#   https://install.crowdsec.net
#   before running on a new host. The script configures the apt repo using
#   the correct "any/ any" suite (avoiding the Debian trixie 404 issue with
#   the legacy packagecloud bootstrap) and imports the GPG signing key —
#   no package binaries are fetched until step 2. It is idempotent: it
#   overwrites an existing sources.list entry if one is already present.
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
# Step 1: Register CrowdSec apt repo.
#
# Supply-chain note: this pipes the official CrowdSec install script directly
# to bash as root. The script writes the apt repo using the "any/ any" suite,
# which resolves the HTTP 404 that the legacy packagecloud bootstrap produced
# on Debian trixie. Review the script at https://install.crowdsec.net before
# running on a new host. The script is idempotent — it overwrites any existing
# sources.list entry — so re-running is safe even if a previous (broken) run
# already wrote /etc/apt/sources.list.d/crowdsec_crowdsec.list.
# Consistent with how 50-docker handles the Docker GPG key step.
# ---------------------------------------------------------------------------

curl -fsSL https://install.crowdsec.net | bash

# ---------------------------------------------------------------------------
# Step 2: Install CrowdSec and the iptables firewall bouncer.
# ---------------------------------------------------------------------------

echo ""
echo "=== 54-crowdsec: installing packages ==="
apt-get install -y crowdsec crowdsec-firewall-bouncer-iptables

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
# block had a fixed shape: `---` / `filenames:` / `  - <path>` / `labels:` /
# `  type: caddy`. Only exact-shape caddy docs are removed.
if grep -q 'type: caddy' "$ACQUIS_YAML" 2>/dev/null; then
  awk '
    /^---[[:space:]]*$/              { buf=$0; state=1; next }
    state==1 && /^filenames:[[:space:]]*$/ { buf=buf "\n" $0; state=2; next }
    state==2 && /^[[:space:]]+-[[:space:]]/ { buf=buf "\n" $0; state=3; next }
    state==3 && /^labels:[[:space:]]*$/    { buf=buf "\n" $0; state=4; next }
    state==4 && /^[[:space:]]+type:[[:space:]]+caddy[[:space:]]*$/ { state=0; buf=""; next }
    state>0 { printf "%s\n", buf; buf=""; state=0 }
    { print }
    END { if (buf != "") printf "%s\n", buf }
  ' "$ACQUIS_YAML" > "$ACQUIS_YAML.bootstrap-tmp"
  cat "$ACQUIS_YAML.bootstrap-tmp" > "$ACQUIS_YAML"
  rm -f "$ACQUIS_YAML.bootstrap-tmp"
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
# Step 4b: Add the deploy user to the crowdsec group.
#
# /etc/crowdsec/local_api_credentials.yaml is root:crowdsec 0640 on Debian —
# group membership lets the deploy user run `cscli` (e.g. `cscli bouncers
# add` from user/init.d/60-caddy) without sudo. usermod -aG is idempotent.
# ---------------------------------------------------------------------------

if [[ -n "${SUDO_USER:-}" ]]; then
  usermod -aG crowdsec "$SUDO_USER"
  echo "Added $SUDO_USER to the crowdsec group (cscli access without sudo)"
fi

# ---------------------------------------------------------------------------
# Step 5: Enable and start CrowdSec LAPI.
# ---------------------------------------------------------------------------

echo ""
echo "=== 54-crowdsec: enabling crowdsec ==="
systemctl enable --now crowdsec

# Restart when the Caddy acquisition config changed on an already-running
# daemon — CrowdSec does not watch acquis files, so a path change (e.g.
# legacy→central during the migration) is silently inert until a restart.
if [[ "$acquis_changed" -eq 1 && "$cs_was_active" -eq 1 ]]; then
  echo "Caddy acquisition config changed — restarting crowdsec"
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

systemctl is-active crowdsec || { echo "ERROR: crowdsec service not active" >&2; exit 1; }
echo "  PASS: crowdsec is active"

systemctl is-active crowdsec-firewall-bouncer || { echo "ERROR: crowdsec-firewall-bouncer not active" >&2; exit 1; }
echo "  PASS: crowdsec-firewall-bouncer is active"

echo ""
echo "54-crowdsec complete."
