#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 20-groups — Add the invoking user (SUDO_USER) to the groups listed
# in groups.txt.
#
# Reads SUDO_USER (set by sudo) and runs `usermod -aG` for each group.
# Run after 10-create-deploy-user so SUDO_USER exists, and before any
# step that needs the deploy user to belong to a specific group
# (typically 30-passwordless-sudo for the sudoers write, and any step
# that runs the deploy user's tools directly).
#
# Run as root (sudo ./init.sh 20-groups).

: "${SUDO_USER:?must run under sudo (e.g., sudo ./init.sh)}"

GROUPS_FILE="$(dirname "$0")/groups.txt"

echo "==> Adding $SUDO_USER to groups from groups.txt..."
while IFS= read -r group || [[ -n "$group" ]]; do
  # Skip blank lines and comments so groups.txt can be self-documenting.
  [[ -z "$group" || "$group" =~ ^[[:space:]]*# ]] && continue
  # Ensure the group exists. `-f` makes groupadd a no-op when the group
  # is already present, so this works for both pre-existing system
  # groups (adm, sudo, systemd-journal) and groups that another step
  # would otherwise create later (docker, owned by 50-docker). This
  # keeps 20-groups order-independent — it runs before or after 50-
  # docker and yields the same final state.
  groupadd -f "$group" 2>/dev/null || true
  usermod -aG "$group" "$SUDO_USER"
  echo "  -> Added to $group"
done < "$GROUPS_FILE"
echo "==> Done. You may need to log out and log back in for group changes to take effect."
