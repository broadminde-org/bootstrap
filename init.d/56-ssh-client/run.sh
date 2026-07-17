#!/usr/bin/env bash
# 56-ssh-client — SSH client defaults + stale ControlMaster cleanup
#
# Root tier: runs as root to write into $SUDO_USER's home directory.
# Idempotent — re-running is a no-op when the marker is present.
# Skips rather than clobbers when a user-managed `Host *` block exists.

# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

TARGET_USER="${SUDO_USER:?must run under sudo (e.g., sudo ./init.sh)}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

# ---------------------------------------------------------------------------
# Stale ControlMaster cleanup (bashrc snippet)
# ---------------------------------------------------------------------------
# ControlMaster sockets in ~/.ssh/cm-* outlive the host they point to. After
# the destination reboots, the socket is dead but still on disk; the next SSH
# session hangs trying to attach to it before falling back to a fresh master.
# Probe each socket with `ssh -O check` (no network/auth) and delete dead ones.
# Runs in every interactive shell so sessions opened long after a reboot stay
# clean. The function unsets itself after running so it does not pollute the
# user's shell namespace.
BASHRC="$TARGET_HOME/.bashrc"
CLEANUP_MARKER="ee SSH stale control-master cleanup"
if [ -f "$BASHRC" ] && ! grep -qF "$CLEANUP_MARKER" "$BASHRC" 2>/dev/null; then
  cat >> "$BASHRC" <<'CLEANUP_EOF'

# --- ee SSH stale control-master cleanup ---
# Remove dead ControlMaster sockets from ~/.ssh/cm-* so the next SSH session
# opens a fresh master instead of attaching to a zombie left over from before
# the destination host rebooted. Probe-only (`-O check`) — does not open any
# network connection or require auth.
_ssh_clean_stale_masters() {
    local s
    for s in "$HOME"/.ssh/cm-*; do
        [ -S "$s" ] || continue
        ssh -o ControlPath="$s" -o BatchMode=yes -o ConnectTimeout=2 \
            -O check noreply.invalid >/dev/null 2>&1 || rm -f "$s"
    done
}
_ssh_clean_stale_masters
unset -f _ssh_clean_stale_masters
# --- End ee SSH stale control-master cleanup ---
CLEANUP_EOF
  echo "Added SSH stale control-master cleanup to $BASHRC"
fi

# ---------------------------------------------------------------------------
# SSH client defaults (~/.ssh/config)
# ---------------------------------------------------------------------------
# Inject a global `Host *` stanza that mitigates two classes of pain:
#
#   1. Stale TCP sessions through NAT/firewalls. ServerAliveInterval/CountMax
#      probe the connection every 30s and close it after 3 missed replies
#      (~90s), so a dead NAT mapping surfaces as a clean disconnect instead of
#      silently corrupting the next command.
#
#   2. First-byte latency for IDE-driven sessions. ControlMaster multiplexes
#      sessions to one host over a single authed socket; ControlPersist keeps
#      the master alive 10m after the last client exits so a freshly opened
#      window reattaches instantly.
#
# UpdateHostKeys auto-rotates host keys in known_hosts on remote-side change
# instead of failing the connection. AddKeysToAgent is intentionally `no` —
# the host relies on explicitly managed agent keys. HashKnownHosts prevents
# accidental leakage of the host inventory.
#
# Idempotent: re-running this block is a no-op when the marker is present.
# Skips rather than clobbers when a user-managed `Host *` block already exists,
# so a deliberate `ServerAliveInterval 0` for a specific host is preserved.

SSHCONFIG="$TARGET_HOME/.ssh/config"
SSHCONFIG_MARKER="ee SSH client defaults"

if [ ! -f "$SSHCONFIG" ]; then
  # Case 1: brand-new host. Create the directory + file with sane modes, drop
  # in the defaults + Include for split-config pattern.
  mkdir -p "$TARGET_HOME/.ssh"
  chmod 700 "$TARGET_HOME/.ssh"
  chown "$TARGET_USER:" "$TARGET_HOME/.ssh"
  cat > "$SSHCONFIG" <<'CLIENT_EOF'
Include ~/.ssh/hosts.d/*

# --- ee SSH client defaults ---
# Global mitigations for stale-socket / IDE-reconnect issues. Applied to every
# host unless overridden by a more specific Host block below.
#
# - ServerAliveInterval/CountMax: probe idle TCP sessions every 30s; close
#   after 3 missed (~90s) so NAT/firewall dead sockets are detected instead
#   of silently corrupting subsequent commands.
# - ControlMaster/Path/Persist: multiplex sessions to a host through one
#   TCP+auth socket; master lingers 10m after last client quits so a freshly
#   opened window reattaches instantly.
# - UpdateHostKeys: auto-rotate host keys in known_hosts on remote-side change
#   instead of failing the connection.
# - AddKeysToAgent no: rely on explicitly managed agent keys.
Host *
    ServerAliveInterval 30
    ServerAliveCountMax 3
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 10m
    UpdateHostKeys yes
    AddKeysToAgent no
    HashKnownHosts yes
# --- End ee SSH client defaults ---
CLIENT_EOF
  chmod 600 "$SSHCONFIG"
  chown "$TARGET_USER:" "$SSHCONFIG"
  echo "Created $SSHCONFIG with ee SSH client defaults"
elif grep -qF "$SSHCONFIG_MARKER" "$SSHCONFIG" 2>/dev/null; then
  # Case 2: already patched. No-op.
  :
elif grep -qE '^[[:space:]]*Host[[:space:]]+\*([[:space:]]|$)' "$SSHCONFIG" 2>/dev/null; then
  # Case 3: user-managed Host * block exists; do not clobber.
  echo "Existing Host * block found in $SSHCONFIG — skipping ee SSH client defaults (manage manually)."
else
  # Case 4: append the defaults block to an existing user config. Quoted heredoc
  # so %r/%h/%p tokens in ControlPath are written literally.
  cat >> "$SSHCONFIG" <<'CLIENT_EOF'

# --- ee SSH client defaults ---
# Global mitigations for stale-socket / IDE-reconnect issues. Applied to every
# host unless overridden by a more specific Host block below.
#
# - ServerAliveInterval/CountMax: probe idle TCP sessions every 30s; close
#   after 3 missed (~90s) so NAT/firewall dead sockets are detected instead
#   of silently corrupting subsequent commands.
# - ControlMaster/Path/Persist: multiplex sessions to a host through one
#   TCP+auth socket; master lingers 10m after last client quits so a freshly
#   opened window reattaches instantly.
# - UpdateHostKeys: auto-rotate host keys in known_hosts on remote-side change
#   instead of failing the connection.
# - AddKeysToAgent no: rely on explicitly managed agent keys.
Host *
    ServerAliveInterval 30
    ServerAliveCountMax 3
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 10m
    UpdateHostKeys yes
    AddKeysToAgent no
    HashKnownHosts yes
# --- End ee SSH client defaults ---
CLIENT_EOF
  echo "Appended ee SSH client defaults to $SSHCONFIG"
fi
