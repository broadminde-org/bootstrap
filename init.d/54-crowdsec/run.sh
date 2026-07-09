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
#   4. Appends the Caddy JSON log path to /etc/crowdsec/acquis.yaml so
#      CrowdSec tails the access log once Phase 2 is applied. The
#      append is idempotent (skipped if the path is already present).
#      CrowdSec tolerates a missing log file — it emits a warning but
#      does NOT hard-fail — so this step is safe to run before Phase 2.
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
CADDY_LOG_PATH=/home/stack/netbird-docker/logs/caddy/access.log

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
# Step 4: Append Caddy log source to acquis.yaml (idempotent).
#
# NOTE: This log path only exists after Phase 2 (Caddy logging) is complete and
# the caddy container has been restarted. If 54-crowdsec runs before Phase 2,
# CrowdSec will emit a warning on every reload but will NOT hard-fail — this is
# expected and harmless until Phase 2 is applied.
# ---------------------------------------------------------------------------

echo ""
echo "=== 54-crowdsec: appending Caddy log source to ${ACQUIS_YAML} ==="

if ! grep -qF "$CADDY_LOG_PATH" "$ACQUIS_YAML" 2>/dev/null; then
  cat >> "$ACQUIS_YAML" <<'ACQUIS_EOF'

---
filenames:
  - /home/stack/netbird-docker/logs/caddy/access.log
labels:
  type: caddy
ACQUIS_EOF
  echo "Appended Caddy log source to ${ACQUIS_YAML}"
else
  echo "Caddy log source already present in ${ACQUIS_YAML} — skipping append"
fi

# ---------------------------------------------------------------------------
# Step 5: Enable and start CrowdSec LAPI.
# ---------------------------------------------------------------------------

echo ""
echo "=== 54-crowdsec: enabling crowdsec ==="
systemctl enable --now crowdsec

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
