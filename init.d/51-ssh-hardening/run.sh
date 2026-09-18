#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/user.sh"

# 51-ssh-hardening — Harden the OpenSSH daemon configuration.
#
# sshd configuration is FIRST-MATCH-WINS per keyword, and Debian's stock
# /etc/ssh/sshd_config has `Include /etc/ssh/sshd_config.d/*.conf` at the
# top — so the lexicographically FIRST drop-in that sets a keyword wins.
# cloud-init writes 50-cloud-init.conf; this step's drop-ins are named
# 00-bootstrap-*.conf so they sort before it (and before any distro or
# package drop-in) and win:
#
#   00-bootstrap-auth.conf       — auth methods (Round 1: password still
#                                  enabled; disable in a later round once
#                                  keys are enrolled)
#   01-bootstrap-hardening.conf  — connection limits and forwarding policy
#
# Performs two complementary actions:
#
#   1. Patches the base /etc/ssh/sshd_config in-place using tolerant sed
#      patterns (commented, whitespace-, or `=`-separated forms are all
#      normalized). The base file is backed up to
#      /etc/ssh/sshd_config.bootstrap.bak before the first edit.
#
#   2. Installs the drop-ins into /etc/ssh/sshd_config.d/ using
#      compare-before-write; legacy 60-auth.conf / 61-hardening.conf
#      drop-ins from earlier revisions (which sorted AFTER cloud-init
#      and silently lost) are removed when they carry our marker.
#
# Safety model — a bad config can never reach the live daemon:
#
#   a. `sshd -t` validates the merged config before any reload.
#   b. Lockout gate: PermitRootLogin no is only activated when the
#      deploy user has a working non-root login path — an enrolled
#      authorized_keys entry, or a set password with effective
#      `passwordauthentication yes`.
#   c. Post-condition assertions: effective values are read back with
#      `sshd -T -C user=<deploy>` (full merged config, Match blocks
#      applied) BEFORE the reload, so a failed assertion aborts the
#      step while the running daemon is still untouched. Round 1
#      requires: permitrootlogin no, passwordauthentication yes.
#   d. After reload the daemon's active state is confirmed.
#
# sshd is reloaded (never restarted), so active sessions survive.
# The reload is skipped entirely when nothing changed.
#
# Run as root (sudo ./init.sh 51-ssh-hardening).

SSHD_CONFIG=/etc/ssh/sshd_config
DROP_IN_DIR=/etc/ssh/sshd_config.d
STEP_DIR="$(dirname "$0")"

require_deploy_user

changed=0

echo "=== 51-ssh-hardening: patching base sshd_config ==="

# ---------------------------------------------------------------------------
# Step 1: Fix base /etc/ssh/sshd_config in-place (backup first).
# ---------------------------------------------------------------------------

BACKUP="$SSHD_CONFIG.bootstrap.bak"
if [[ -f "$SSHD_CONFIG" && ! -f "$BACKUP" ]]; then
  cp -a "$SSHD_CONFIG" "$BACKUP"
  echo "Backed up $SSHD_CONFIG -> $BACKUP"
fi

before_sum="$(sha256sum "$SSHD_CONFIG" | awk '{print $1}')"

# Tolerant patterns: match commented-out, whitespace-padded, and
# `=`-separated forms (`PermitRootLogin yes`, `#PermitRootLogin yes`,
# `PermitRootLogin=yes`, ...) and normalize to the hardened value.
sed -i -E 's/^[#[:space:]]*PermitRootLogin[[:space:]=].*$/PermitRootLogin no/' "$SSHD_CONFIG"
sed -i -E 's/^[#[:space:]]*X11Forwarding[[:space:]=].*$/X11Forwarding no/' "$SSHD_CONFIG"

after_sum="$(sha256sum "$SSHD_CONFIG" | awk '{print $1}')"
if [[ "$before_sum" != "$after_sum" ]]; then
  changed=1
  echo "Base sshd_config patched (PermitRootLogin, X11Forwarding)"
else
  echo "ok: base sshd_config already hardened"
fi

# ---------------------------------------------------------------------------
# Step 2: Install the hardening drop-ins (compare-before-write).
# ---------------------------------------------------------------------------

install -m 0755 -d "$DROP_IN_DIR"

# Migration: remove the pre-rename drop-ins — they sorted after
# cloud-init's 50-cloud-init.conf and silently lost. Only remove when
# they carry our marker so a hand-edited file is never deleted.
for legacy in 60-auth.conf 61-hardening.conf; do
  if [[ -f "$DROP_IN_DIR/$legacy" ]] \
    && grep -qF 'Managed by bootstrap/init.d/51-ssh-hardening' "$DROP_IN_DIR/$legacy"; then
    rm -f "$DROP_IN_DIR/$legacy"
    changed=1
    echo "Removed legacy drop-in $legacy (superseded by 00-bootstrap-*.conf)"
  fi
done

for conf in 00-bootstrap-auth.conf 01-bootstrap-hardening.conf; do
  if [[ ! -f "$DROP_IN_DIR/$conf" ]] || ! cmp -s "${STEP_DIR}/${conf}" "$DROP_IN_DIR/$conf"; then
    install -m 0644 "${STEP_DIR}/${conf}" "$DROP_IN_DIR/$conf"
    changed=1
    echo "Installed ${DROP_IN_DIR}/${conf}"
  else
    echo "ok:   ${DROP_IN_DIR}/${conf} (unchanged)"
  fi
done

# ---------------------------------------------------------------------------
# Step 3: Validate the merged config BEFORE touching the running daemon.
# ---------------------------------------------------------------------------

if ! sshd -t; then
  echo "ERROR: sshd -t failed — the merged config is invalid." >&2
  echo "       Refusing to reload; the running daemon is untouched." >&2
  exit 1
fi
echo "sshd -t: merged config is valid"

# ---------------------------------------------------------------------------
# Step 4: Read back effective values for the deploy user's login class.
# `sshd -T -C` applies Match blocks the way a real connection would, so
# a competing drop-in overriding us is caught here — before activation.
# ---------------------------------------------------------------------------

EFFECTIVE="$(sshd -T -C "user=${DEPLOY_USER},host=localhost,addr=127.0.0.1")"

effective_value() {
  awk -v key="$1" '$1 == key { print $2; exit }' <<<"$EFFECTIVE"
}

assert_effective() {
  local key="$1" want="$2" got
  got="$(effective_value "$key")"
  if [[ "$got" != "$want" ]]; then
    echo "ERROR: post-condition failed — effective ${key} is '${got:-<unset>}'," >&2
    echo "       expected '${want}'. Another drop-in is overriding" >&2
    echo "       00-bootstrap-*.conf; inspect $DROP_IN_DIR and $SSHD_CONFIG." >&2
    exit 1
  fi
  echo "  PASS: ${key} ${got}"
}

assert_effective permitrootlogin no
assert_effective passwordauthentication yes   # Round 1 — see 00-bootstrap-auth.conf

# ---------------------------------------------------------------------------
# Step 5: Lockout gate — activate PermitRootLogin no only when the deploy
# user has a working non-root login path: an enrolled SSH key, or a set
# password + effective password auth (asserted yes above).
# ---------------------------------------------------------------------------

DEPLOY_HOME="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
key_enrolled=0
[[ -n "$DEPLOY_HOME" && -s "$DEPLOY_HOME/.ssh/authorized_keys" ]] && key_enrolled=1

pw_status="$(passwd -S "$DEPLOY_USER" 2>/dev/null | awk '{print $2}')"
password_set=0
[[ "$pw_status" == "P" ]] && password_set=1

if (( ! key_enrolled )) && (( ! password_set )); then
  echo "ERROR: refusing to activate 'PermitRootLogin no':" >&2
  echo "       deploy user '$DEPLOY_USER' has neither an enrolled SSH key" >&2
  echo "       ($DEPLOY_HOME/.ssh/authorized_keys) nor a usable password" >&2
  echo "       (passwd status: ${pw_status:-unknown}). Activating would lock" >&2
  echo "       every login path off this host. Enroll a key via" >&2
  echo "       BOOTSTRAP_SSH_PUBKEY in .env (step 10) or set a password first." >&2
  exit 1
fi
if (( key_enrolled )); then
  echo "  PASS: deploy user has an enrolled SSH key"
else
  echo "  PASS: deploy user has a usable password (password auth enabled)"
fi

# ---------------------------------------------------------------------------
# Step 6: Reload sshd to apply changes without dropping active sessions.
# The unit is sshd.service on Debian, ssh.service on Ubuntu — detect it.
# ---------------------------------------------------------------------------

if (( changed )); then
  if systemctl cat sshd.service >/dev/null 2>&1; then
    systemctl reload sshd
  else
    systemctl reload ssh
  fi
  echo "sshd reloaded"
else
  echo "No config changes — skipping sshd reload."
fi

# Confirm the daemon survived (reload of a bad binary state can kill it).
if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
  echo "  PASS: ssh daemon is active"
else
  echo "ERROR: ssh daemon is not active after reload." >&2
  exit 1
fi

echo "51-ssh-hardening complete."
echo "NOTE: PasswordAuthentication is still enabled (Round 1)."
echo "      Once a key is enrolled for the deploy user, disable it by"
echo "      setting PasswordAuthentication no in 00-bootstrap-auth.conf"
echo "      and re-running this step."
