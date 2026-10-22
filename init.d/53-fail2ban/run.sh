#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 53-fail2ban — Install fail2ban, configure jails, enable the service.
#
# Sets up three jails:
#
#   sshd            — monitors the systemd journal for brute-force SSH
#                     login attempts. Bans via ufw. Active from first run.
#
#   caddy-auth      — monitors Caddy's JSON access log for repeated
#                     401/403 responses against /api/* paths (NetBird API
#                     auth failures). Active only after Phase 2 (Caddy
#                     JSON logging) and a caddy container restart.
#
#   netbird-installer — monitors Caddy's JSON access log for repeated
#                     requests to /install/* paths (installer rate-abuse
#                     detection). Active only after Phase 2.
#
# Dependencies:
#   Phase 1  — ufw must be active (banaction = ufw).
#   Phase 2  — Caddy JSON log must exist for the caddy-auth and
#              netbird-installer jails. Path resolution (shared with
#              54-crowdsec via lib/caddy-log.sh): $CADDY_LOG_PATH env
#              override, then whichever of the central (~/infra/caddy) or
#              legacy (netbird-docker) log is the live one — when both
#              exist, the fresher mtime wins — then the central path as
#              the default for new hosts. Log-dependent jails remain
#              disabled until a readable log exists.
#
# Run as root (sudo ./init.sh 53-fail2ban).

JAIL_LOCAL=/etc/fail2ban/jail.local
FILTER_DIR=/etc/fail2ban/filter.d

# Caddy JSON log path — resolved by the shared lib/caddy-log.sh (same
# resolution as 54-crowdsec): CADDY_LOG_PATH env override, then whichever of
# the central (~/infra/caddy) or legacy (netbird-docker) log is the live one
# (mtime when both exist — the live edge is the file being written), then
# the central path as the default for new hosts.
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/caddy-log.sh"
resolve_caddy_log CADDY_LOG

if ! command -v ufw >/dev/null 2>&1 || ! ufw status | grep -q 'Status: active'; then
  echo 'ERROR: fail2ban requires active UFW; run 52-ufw first.' >&2
  exit 1
fi

caddy_jails_enabled=false
if [[ -f "$CADDY_LOG" && -r "$CADDY_LOG" ]]; then
  caddy_jails_enabled=true
fi

echo "=== 53-fail2ban: installing fail2ban ==="

# ---------------------------------------------------------------------------
# Step 1: Install fail2ban.
# ---------------------------------------------------------------------------

apt-get install -y fail2ban python3-systemd

# ---------------------------------------------------------------------------
# Step 2: Write jail.local.
# ---------------------------------------------------------------------------

echo ""
echo "=== 53-fail2ban: writing ${JAIL_LOCAL} ==="

# Capture pre-write state so a changed jail.local triggers a reload of an
# already-running fail2ban (enable --now alone is a no-op on a running
# daemon — without a reload the jails keep tailing the old logpath).
f2b_was_active=0
systemctl is-active --quiet fail2ban && f2b_was_active=1
# jail.local does not exist on fresh hosts — a failing sha256sum here would
# abort the step (set -e + pipefail), so guard on the file's presence.
pre_jail_hash=""
[[ -f "$JAIL_LOCAL" ]] && pre_jail_hash="$(sha256sum "$JAIL_LOCAL" | cut -d' ' -f1)"
pre_filter_hash=""
for filter in caddy-auth netbird-installer; do
  if [[ -f "$FILTER_DIR/$filter.conf" ]]; then
    pre_filter_hash+="$(sha256sum "$FILTER_DIR/$filter.conf")"
  fi
done

cat > "$JAIL_LOCAL" <<JAIL_EOF
# Managed by bootstrap/init.d/53-fail2ban. Do not edit by hand.
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
banaction = ufw

[sshd]
enabled  = true
port     = 22
backend  = systemd
maxretry = 5

[caddy-auth]
enabled  = $caddy_jails_enabled
port     = 443
filter   = caddy-auth
logpath  = $CADDY_LOG
maxretry = 10
findtime = 5m

[netbird-installer]
enabled  = $caddy_jails_enabled
port     = 443
filter   = netbird-installer
logpath  = $CADDY_LOG
maxretry = 20
findtime = 1m
JAIL_EOF

echo "Written ${JAIL_LOCAL}"

# ---------------------------------------------------------------------------
# Step 3: Write the caddy-auth filter.
# ---------------------------------------------------------------------------

echo ""
echo "=== 53-fail2ban: writing ${FILTER_DIR}/caddy-auth.conf ==="

cat > "${FILTER_DIR}/caddy-auth.conf" <<'FILTER_EOF'
# Managed by bootstrap/init.d/53-fail2ban. Do not edit by hand.
# Matches Caddy JSON access log lines for 401/403 responses to /api/* paths.
#
# Log shape (one JSON object per line):
#   {"level":"warn","ts":...,"request":{"remote_ip":"...","client_ip":"<HOST>","uri":"/api/..."},"status":401}
#
# "client_ip" is used instead of "remote_ip" because sase.tlicho.ca is
# Cloudflare-fronted. Caddy resolves the real attacker IP via trusted_proxies
# into "client_ip"; "remote_ip" would be a CF edge node address.
#
# "uri" and "client_ip" are nested inside "request{}"; "status" is a sibling
# of "request" at the top level — so <HOST> must appear before "uri" in the
# line, and "status" is matched separately at the end.
#
# Verify against real log lines with:
#   fail2ban-regex /home/<deploy>/infra/caddy/logs/access.log /etc/fail2ban/filter.d/caddy-auth.conf
[Definition]
failregex = .*"client_ip":"<HOST>".*"uri":"/api/[^"]*".*"status":\s*(401|403)
FILTER_EOF

echo "Written ${FILTER_DIR}/caddy-auth.conf"

# ---------------------------------------------------------------------------
# Step 4: Write the netbird-installer filter.
# ---------------------------------------------------------------------------

echo ""
echo "=== 53-fail2ban: writing ${FILTER_DIR}/netbird-installer.conf ==="

cat > "${FILTER_DIR}/netbird-installer.conf" <<'FILTER_EOF'
# Managed by bootstrap/init.d/53-fail2ban. Do not edit by hand.
# Matches Caddy JSON access log lines for any /install/* request (rate abuse detection).
#
# Log shape (one JSON object per line):
#   {"level":"info","ts":...,"request":{"remote_ip":"...","client_ip":"<HOST>","uri":"/install/..."},"status":200}
#
# "client_ip" is used instead of "remote_ip" because sase.tlicho.ca is
# Cloudflare-fronted. Caddy resolves the real attacker IP via trusted_proxies
# into "client_ip"; banning "remote_ip" would ban a CF edge node address.
#
# "uri" and "client_ip" are nested inside "request{}" — both appear before
# "status" in the serialised line, so the pattern anchors on "client_ip" first.
#
# Verify against real log lines with:
#   fail2ban-regex /home/<deploy>/infra/caddy/logs/access.log /etc/fail2ban/filter.d/netbird-installer.conf
[Definition]
failregex = .*"client_ip":"<HOST>".*"uri":"/install/[^"]*"
FILTER_EOF

echo "Written ${FILTER_DIR}/netbird-installer.conf"

# ---------------------------------------------------------------------------
# Step 5: Enable and start fail2ban.
# ---------------------------------------------------------------------------

echo ""
echo "=== 53-fail2ban: enabling and starting service ==="
systemctl enable --now fail2ban

# Reload when jail.local changed on an already-running daemon (e.g. the
# Caddy log path flipped legacy→central during the migration) — otherwise
# the jails keep tailing the stale path silently until an unrelated restart.
post_filter_hash="$(sha256sum "$FILTER_DIR/caddy-auth.conf" "$FILTER_DIR/netbird-installer.conf")"
if [[ "$f2b_was_active" -eq 1 ]] \
  && { [[ "$(sha256sum "$JAIL_LOCAL" | cut -d' ' -f1)" != "$pre_jail_hash" ]] \
    || [[ "$post_filter_hash" != "$pre_filter_hash" ]]; }; then
  echo "fail2ban configuration changed — reloading fail2ban"
  fail2ban-client reload
fi

# ---------------------------------------------------------------------------
# Step 6: Post-condition assertions.
# ---------------------------------------------------------------------------

echo ""
echo "=== Post-condition assertions ==="

systemctl is-active fail2ban || { echo "ERROR: fail2ban not active" >&2; exit 1; }
echo "  PASS: fail2ban is active"

# systemd can report active before fail2ban has opened its control socket.
for ((attempt=0; attempt<10; attempt++)); do
  if fail2ban-client ping >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
fail2ban-client ping >/dev/null || { echo 'ERROR: fail2ban control socket not ready' >&2; exit 1; }

fail2ban-client status sshd >/dev/null || { echo 'ERROR: sshd jail not active' >&2; exit 1; }
if [[ "$caddy_jails_enabled" == true ]]; then
  fail2ban-client status caddy-auth >/dev/null
  fail2ban-client status netbird-installer >/dev/null
fi

# ---------------------------------------------------------------------------
# Step 7: Log-format dependency note.
# ---------------------------------------------------------------------------

echo ""
echo "NOTE: caddy-auth and netbird-installer filters assume Caddy JSON log format (Phase 2)."
echo "Verify filter regex against a real log line before trusting jail status:"
echo "  fail2ban-regex ${CADDY_LOG} ${FILTER_DIR}/caddy-auth.conf"

echo ""
echo "53-fail2ban complete."
