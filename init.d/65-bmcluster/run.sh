#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"
# shellcheck source=init.d/lib/conf.sh
. "$(dirname "$0")/../lib/conf.sh"
# shellcheck source=init.d/lib/user.sh
. "$(dirname "$0")/../lib/user.sh"

# This step prepares a closed host only. Activation and admission are separate,
# operator-reviewed actions after two-host verification.
STEP_DIR="$(cd "$(dirname "$0")" && pwd)"
version="$(get_pinned_version bmcluster '')"
base="$(get_cluster_conf release_base_url)"
key="$(get_cluster_conf signing_key_file)"
iface="$(get_cluster_conf trusted_interface)"
ip="$(get_cluster_conf control_ip)"
port="$(get_cluster_conf control_port)"
discovery="$(get_cluster_conf discovery off)"

[[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'ERROR: versions.bmcluster must be an exact vX.Y.Z release tag' >&2; exit 1; }
[[ "$base" =~ ^https://[a-zA-Z0-9._~:/%-]+$ ]] || { echo 'ERROR: cluster.release_base_url must be an explicit HTTPS release directory' >&2; exit 1; }
[[ "$key" == /* && -f "$key" && ! -L "$key" && "$(stat -c %u "$key")" == 0 ]] || { echo 'ERROR: an out-of-band root-owned signing_key_file is required' >&2; exit 1; }
(( (8#$(stat -c %a "$key") & 8#022) == 0 )) || { echo 'ERROR: signing key must not be group/world writable' >&2; exit 1; }
dir="$(dirname "$key")"
while [[ "$dir" != / ]]; do
  if [[ -L "$dir" || "$(stat -c %u "$dir")" != 0 ]] || (( (8#$(stat -c %a "$dir") & 8#022) != 0 )); then
    echo 'ERROR: signing key directory must be root-owned and not writable by others' >&2; exit 1
  fi
  dir="$(dirname "$dir")"
done
openssl pkey -pubin -in "$key" -text_pub -noout 2>/dev/null | grep -q 'ED25519 Public-Key' || {
  echo 'ERROR: signing key must be an Ed25519 public PEM key' >&2; exit 1;
}
[[ "$iface" =~ ^[a-zA-Z0-9_.:-]+$ && "$iface" != lo ]] || { echo 'ERROR: trusted_interface must be an explicit non-loopback interface' >&2; exit 1; }
ip link show dev "$iface" >/dev/null || { echo 'ERROR: trusted interface is absent' >&2; exit 1; }
if [[ ! "$port" =~ ^[0-9]{1,5}$ ]] || (( 10#$port < 1024 || 10#$port > 65535 )); then
  echo 'ERROR: control_port must be 1024..65535 for the unprivileged service' >&2; exit 1
fi
[[ "$discovery" == off ]] || { echo 'ERROR: DNS-SD publication is not approved before two-host verification; set discovery: off' >&2; exit 1; }

# Binding a public IP is forbidden even when the unit is disabled. Confirm the
# private address belongs to the selected device (including its CIDR suffix).
if [[ ! "$ip" =~ ^(10\.[0-9.]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9.]+|192\.168\.[0-9.]+|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9.]+|[fF][cCdD][0-9a-fA-F:]+)$ ]] ||
   ! ip -o addr show dev "$iface" | awk -v want="$ip" '{split($4,a,"/"); if (a[1] == want) found=1} END {exit !found}'; then
  echo 'ERROR: control_ip must be a private address assigned to trusted_interface' >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64) arch=arm64 ;;
  *) echo 'ERROR: no pinned bmcluster release for this architecture' >&2; exit 1 ;;
esac
for cmd in curl openssl sha256sum ufw sshd systemctl; do
  command -v "$cmd" >/dev/null || { echo "ERROR: missing $cmd" >&2; exit 1; }
done
require_deploy_user
[[ "$DEPLOY_USER" != bmcluster ]] || { echo 'ERROR: the bmcluster service account cannot be its own operator' >&2; exit 1; }

require_bmcluster_units_inactive_disabled() {
  local unit active_state enabled_state
  for unit in bmcluster.service bmcluster.socket; do
    active_state="$(systemctl is-active "$unit" 2>/dev/null || true)"
    enabled_state="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    [[ "$active_state" == inactive || "$active_state" == failed ]] || {
      echo "ERROR: $unit is $active_state; stop it before provisioning" >&2; exit 1;
    }
    case "$enabled_state" in
      disabled|masked|masked-runtime|not-found) ;;
      *) echo "ERROR: $unit has activation state '$enabled_state'; disable it before provisioning" >&2; exit 1 ;;
    esac
  done
}
require_bmcluster_units_inactive_disabled
ufw status verbose | grep -q '^Status: active$' || {
  echo 'ERROR: UFW must be active before provisioning; run 52-ufw first' >&2; exit 1;
}

asset="bmcluster_${version}_linux_${arch}"
tmp="$(mktemp -d /root/.bmcluster-install.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
for name in "$asset" SHA256SUMS SHA256SUMS.sig; do
  case "$name" in
    "$asset") max_bytes=$((256 * 1024 * 1024)) ;;
    SHA256SUMS) max_bytes=$((1024 * 1024)) ;;
    SHA256SUMS.sig) max_bytes=1024 ;;
  esac
  curl --fail --silent --show-error --location --retry 3 --retry-max-time 300 \
    --connect-timeout 10 --max-time 300 --speed-limit 1024 --speed-time 30 \
    --max-filesize "$max_bytes" --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --output "$tmp/$name" "${base%/}/$name"
  bytes="$(stat -c %s "$tmp/$name")"
  (( bytes > 0 && bytes <= max_bytes )) || {
    echo "ERROR: downloaded $name exceeds its size limit or is empty" >&2; exit 1;
  }
done
# The signing key is a separately provisioned trust anchor. A downloaded
# checksum without its authenticated detached signature is not sufficient.
openssl pkeyutl -verify -pubin -inkey "$key" -rawin -in "$tmp/SHA256SUMS" -sigfile "$tmp/SHA256SUMS.sig" >/dev/null || {
  echo 'ERROR: release manifest signature verification failed' >&2; exit 1;
}
awk -v asset="$asset" '$2 == asset && NF == 2 && $1 ~ /^[0-9a-fA-F]+$/ && length($1) == 64 {print; n++} END {if (n != 1) exit 1}' \
  "$tmp/SHA256SUMS" > "$tmp/selected.sha256" || { echo 'ERROR: signed manifest has no unique checksum for this architecture' >&2; exit 1; }
( cd "$tmp" && sha256sum -c selected.sha256 ) || { echo 'ERROR: bmcluster checksum mismatch' >&2; exit 1; }
[[ -s "$tmp/$asset" ]] || { echo 'ERROR: release binary is empty' >&2; exit 1; }

# Do not adopt an existing, privileged account under this well-known name.
if id bmcluster >/dev/null 2>&1; then
  passwd_entry="$(getent passwd bmcluster)"
  IFS=: read -r _ _ uid gid _ home shell <<< "$passwd_entry"
  [[ "$uid" -ne 0 && "$home" == /var/lib/bmcluster && "$shell" == /usr/sbin/nologin &&
     "$(id -G bmcluster)" == "$gid" && "$(id -gn bmcluster)" == bmcluster ]] || {
    echo 'ERROR: existing bmcluster account has unexpected identity, shell or groups' >&2; exit 1;
  }
else
  useradd --system --user-group --home-dir /var/lib/bmcluster --no-create-home --shell /usr/sbin/nologin bmcluster
fi
usermod --lock bmcluster
[[ "$(passwd -S bmcluster | awk '{print $2}')" == L ]] || { echo 'ERROR: bmcluster password was not locked' >&2; exit 1; }
if ! getent group bmcluster-operators >/dev/null; then
  groupadd --system bmcluster-operators
fi
if ! id -nG "$DEPLOY_USER" | tr ' ' '\n' | grep -qx bmcluster-operators; then
  usermod -a -G bmcluster-operators "$DEPLOY_USER"
fi
for path in /var/lib/bmcluster /var/lib/bmcluster/state /etc/bmcluster /etc/bmcluster/daemon.env; do
  [[ ! -L "$path" ]] || { echo "ERROR: refusing symlink at $path" >&2; exit 1; }
done
install -d -o bmcluster -g bmcluster -m 0700 /var/lib/bmcluster
# Leave state absent: explicit `bmcluster init` or `join` creates it once.
# Pre-creating it here would make both commands refuse enrollment.
install -d -o root -g root -m 0700 /etc/bmcluster
install -o root -g root -m 0755 "$tmp/$asset" /usr/local/bin/bmcluster

listen_ip="$ip"
[[ "$ip" != *:* ]] || listen_ip="[$ip]"
env_content="CLUSTER_STATE_DIR=/var/lib/bmcluster/state
CLUSTER_CONTROL_INTERFACE=$iface
CLUSTER_CONTROL_LISTEN_ADDR=$listen_ip:$port
CLUSTER_OPERATOR_UID=$(id -u "$DEPLOY_USER")"
if [[ ! -f /etc/bmcluster/daemon.env ]] || [[ "$(</etc/bmcluster/daemon.env)" != "$env_content" ]]; then
  printf '%s\n' "$env_content" > /etc/bmcluster/daemon.env
fi
chown root:root /etc/bmcluster/daemon.env
chmod 0600 /etc/bmcluster/daemon.env
if [[ ! -f /etc/systemd/system/bmcluster.service ]] || ! cmp -s "$STEP_DIR/bmcluster.service" /etc/systemd/system/bmcluster.service; then
  install -o root -g root -m 0644 "$STEP_DIR/bmcluster.service" /etc/systemd/system/bmcluster.service
  systemctl daemon-reload
fi
if [[ ! -f /etc/systemd/system/bmcluster.socket ]] || ! cmp -s "$STEP_DIR/bmcluster.socket" /etc/systemd/system/bmcluster.socket; then
  install -o root -g root -m 0644 "$STEP_DIR/bmcluster.socket" /etc/systemd/system/bmcluster.socket
  systemctl daemon-reload
fi

# Install the managed Match block first, terminated by Match all. This keeps
# later global directives valid and prevents an earlier competing Match from
# weakening the bmcluster policy. Build and validate a complete candidate before
# atomically replacing sshd_config; retain rollback through a successful reload.
sshd_config=/etc/ssh/sshd_config
[[ -f "$sshd_config" && ! -L "$sshd_config" ]] || { echo 'ERROR: sshd_config must be a regular non-symlink file' >&2; exit 1; }
marker='# Managed by bootstrap/init.d/65-bmcluster'
sshd_block='# Managed by bootstrap/init.d/65-bmcluster
Match User bmcluster
    AuthenticationMethods publickey
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    PermitTTY no
    DisableForwarding yes
    X11Forwarding no
    PermitUserRC no
    ForceCommand /usr/bin/false
Match all'
# PermitUserEnvironment is global-only in OpenSSH. Keep its safe default in the
# effective-policy assertions below and reject hosts that enable it globally.
ssh_backup=''
ssh_candidate=''
ssh_transaction_active=0
ssh_reload_attempted=0
ssh_service=''
cleanup_install() {
  local rc=$?
  trap - EXIT
  if (( ssh_transaction_active )); then
    if [[ -n "$ssh_backup" && -f "$ssh_backup" ]]; then
      if mv -f "$ssh_backup" "$sshd_config"; then
        ssh_backup=''
      else
        echo "ERROR: failed to restore sshd_config; backup retained at $ssh_backup" >&2
        rc=1
      fi
    else
      echo 'ERROR: sshd_config rollback backup is missing' >&2
      rc=1
    fi
    if (( ssh_reload_attempted )) && [[ -n "$ssh_service" && -z "$ssh_backup" ]]; then
      if ! systemctl reload "$ssh_service"; then
        echo 'ERROR: sshd_config restored but rollback reload failed; console recovery required' >&2
        rc=1
      elif ! systemctl is-active --quiet "$ssh_service"; then
        echo 'ERROR: sshd_config restored but rollback daemon-health check failed; console recovery required' >&2
        rc=1
      fi
    fi
  fi
  [[ -z "$ssh_candidate" ]] || rm -f "$ssh_candidate"
  if (( ! ssh_transaction_active )) && [[ -n "$ssh_backup" ]]; then
    rm -f "$ssh_backup"
  fi
  rm -rf "$tmp"
  exit "$rc"
}
trap cleanup_install EXIT

verify_ssh() {
  local config="$1" context effective expected
  sshd -t -f "$config" || return 1
  for context in 'user=bmcluster,host=localhost,addr=127.0.0.1' "user=bmcluster,host=cluster-peer.invalid,addr=$ip"; do
    effective="$(sshd -T -f "$config" -C "$context")" || return 1
    for expected in 'authenticationmethods publickey' 'passwordauthentication no' 'kbdinteractiveauthentication no' 'permittty no' 'disableforwarding yes' 'x11forwarding no' 'permituserenvironment no' 'permituserrc no' 'forcecommand /usr/bin/false'; do
      grep -qFx "$expected" <<< "$effective" || { echo "ERROR: sshd did not enforce $expected for $context" >&2; return 1; }
    done
  done
}

ssh_candidate="$(mktemp /etc/ssh/.bmcluster-sshd-candidate.XXXXXX)"
awk -v block="$sshd_block" -v marker="$marker" '
  BEGIN { printf "%s\n", block }
  $0 == marker {
    if (found++) exit 1
    skipping=1
    next
  }
  skipping {
    if (skipping == 1) {
      if ($0 != "Match User bmcluster") exit 1
      skipping=2
      next
    }
    if ($0 == "Match all") skipping=0
    else if (tolower($0) ~ /^[[:space:]]*match[[:space:]]/) exit 1
    next
  }
  { print }
  END { if (skipping) exit 1 }
' "$sshd_config" > "$ssh_candidate"
chown --reference="$sshd_config" "$ssh_candidate"
chmod --reference="$sshd_config" "$ssh_candidate"
verify_ssh "$ssh_candidate"

ssh_backup="$(mktemp /etc/ssh/.bmcluster-sshd-backup.XXXXXX)"
cp -a --remove-destination "$sshd_config" "$ssh_backup"
ssh_transaction_active=1
if ! cmp -s "$ssh_candidate" "$sshd_config"; then
  mv -f "$ssh_candidate" "$sshd_config"
  ssh_candidate=''
fi
verify_ssh "$sshd_config"
if systemctl cat sshd.service >/dev/null 2>&1; then ssh_service=sshd; else ssh_service=ssh; fi
ssh_reload_attempted=1
systemctl reload "$ssh_service"
systemctl is-active --quiet "$ssh_service"
ssh_transaction_active=0
rm -f "$ssh_backup"
ssh_backup=''

# Reconcile only bootstrap-owned denies, then place the current narrow deny
# ahead of broader allows. UFW's numbered display is authoritative for order;
# `ufw show added` provides stable rule text for endpoint reconciliation.
managed_ufw_endpoints() {
  ufw show added | awk '
    $1 == "ufw" && $2 == "deny" && $3 == "in" && $4 == "on" &&
    $6 == "to" && $8 == "port" && $10 == "proto" && $11 == "tcp" &&
    / comment \047bmcluster inactive\047[[:space:]]*$/ { print $5 "\t" $7 "\t" $9 }
  ' | sort -u
}
mapfile -t stale_rules < <(managed_ufw_endpoints)
for rule in "${stale_rules[@]}"; do
  [[ -n "$rule" ]] || continue
  IFS=$'\t' read -r old_iface old_ip old_port <<< "$rule"
  # UFW hides identical rules in show added and deletes only one match at a time.
  while managed_ufw_endpoints | grep -qFx "$rule"; do
    before_ufw_rules="$(ufw status numbered)"
    ufw --force delete deny in on "$old_iface" to "$old_ip" port "$old_port" proto tcp comment 'bmcluster inactive' >/dev/null
    [[ "$(ufw status numbered)" != "$before_ufw_rules" ]] || {
      echo 'ERROR: UFW did not remove the managed deny; refusing to loop' >&2; exit 1;
    }
  done
done
ufw insert 1 deny in on "$iface" to "$ip" port "$port" proto tcp comment 'bmcluster inactive'
ufw status verbose | grep -q '^Status: active$' || { echo 'ERROR: UFW became inactive during provisioning' >&2; exit 1; }
first_ufw_rule="$(ufw status numbered | awk '/^\[[[:space:]]*[0-9]+\]/ {print; exit}')"
[[ "$first_ufw_rule" == *"bmcluster inactive"* && "$first_ufw_rule" == *"$iface"* && "$first_ufw_rule" == *"$ip"* && "$first_ufw_rule" == *"$port"* ]] || {
  echo 'ERROR: the bmcluster deny is not the first UFW rule' >&2; exit 1;
}
owned_ufw_rule_count="$(ufw status numbered | awk '/^\[[[:space:]]*[0-9]+\]/ && /DENY IN/ && / # bmcluster inactive[[:space:]]*$/ {n++} END {print n+0}')"
[[ "$owned_ufw_rule_count" == 1 ]] || {
  echo 'ERROR: duplicate managed UFW denies remain' >&2; exit 1;
}
mapfile -t remaining_rules < <(managed_ufw_endpoints)
expected_rule="$(printf '%s\t%s\t%s' "$iface" "$ip" "$port")"
[[ "${#remaining_rules[@]}" == 1 && "${remaining_rules[0]}" == "$expected_rule" ]] || {
  echo 'ERROR: stale or unparsed bmcluster UFW rules remain' >&2; exit 1;
}
require_bmcluster_units_inactive_disabled
echo 'bmcluster verified and installed; service and socket disabled, SSH command denied, ingress closed.'
