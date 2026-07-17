#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 20-groups — Add the invoking user (SUDO_USER) to the baseline OS
# groups listed in groups.txt.
#
# Only unconditional, host-wide groups live here. Capability-specific
# groups (docker, kvm, libvirt) are added by the step that installs
# the corresponding service so that group membership tracks whether the
# service is actually present on this host.
#
# Reads SUDO_USER (set by sudo) and runs `usermod -aG` for each group.
# Run after 10-create-deploy-user so SUDO_USER exists.
#
# Run as root (sudo ./init.sh 20-groups).

: "${SUDO_USER:?must run under sudo (e.g., sudo ./init.sh)}"

GROUPS_FILE="$(dirname "$0")/groups.txt"

echo "==> Adding $SUDO_USER to groups from groups.txt..."
while IFS= read -r group || [[ -n "$group" ]]; do
  # Skip blank lines and comments so groups.txt can be self-documenting.
  [[ -z "$group" || "$group" =~ ^[[:space:]]*# ]] && continue
  # Ensure the group exists. `-f` makes groupadd a no-op when the
  # group is already present (e.g. adm, sudo, systemd-journal are
  # created by the OS or installed packages).
  groupadd -f "$group" 2>/dev/null || true
  usermod -aG "$group" "$SUDO_USER"
  echo "  -> Added to $group"
done < "$GROUPS_FILE"
echo "==> Done. You may need to log out and log back in for group changes to take effect."
