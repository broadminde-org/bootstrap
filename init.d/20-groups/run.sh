#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/user.sh"

# 20-groups — Add the deploy user to the baseline OS groups listed in
# groups.txt.
#
# Only unconditional, host-wide groups live here. Capability-specific
# groups (docker, kvm, libvirt) are added by the step that installs
# the corresponding service so that group membership tracks whether the
# service is actually present on this host.
#
# The deploy user is resolved via lib/user.sh (BOOTSTRAP_USER, else
# SUDO_USER). Run after 10-create-deploy-user so the user exists.
#
# Run as root (sudo ./init.sh 20-groups).

require_deploy_user

GROUPS_FILE="$(dirname "$0")/groups.txt"

echo "==> Adding $DEPLOY_USER to groups from groups.txt..."
while IFS= read -r group || [[ -n "$group" ]]; do
  # Skip blank lines and comments so groups.txt can be self-documenting.
  [[ -z "$group" || "$group" =~ ^[[:space:]]*# ]] && continue
  # Ensure the group exists. `-f` makes groupadd a no-op when the
  # group is already present (e.g. adm, sudo, systemd-journal are
  # created by the OS or installed packages).
  groupadd -f "$group"
  usermod -aG "$group" "$DEPLOY_USER"
  echo "  -> Added to $group"
done < "$GROUPS_FILE"
echo "==> Done. You may need to log out and log back in for group changes to take effect."
