#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 57-kvm — Install KVM virtualization stack.
#
# What this script does:
#
#   1. Installs QEMU/KVM, libvirt, and supporting packages.
#
#   2. Enables and starts libvirtd.
#
#   3. Validates that the KVM kernel module is loaded.
#
# Group membership (kvm, libvirt) is added by this step after the
# packages that create those groups are installed, so that membership
# is only granted when KVM is actually present on the host. A fresh
# login is required for group changes to take effect.
#
# Run as root (sudo ./init.sh 57-kvm).

echo "=== 57-kvm: installing KVM + libvirt packages ==="

apt-get install -y \
  qemu-kvm \
  libvirt-daemon-system \
  libvirt-clients \
  bridge-utils \
  virtinst

# Add the deploy user to the kvm and libvirt groups so they can manage
# VMs without sudo. These groups are created by the packages above.
# We own this membership here rather than in 20-groups so it is only
# granted when KVM is actually installed on the host.
if [[ -n "${SUDO_USER:-}" ]]; then
  usermod -aG kvm "$SUDO_USER"
  usermod -aG libvirt "$SUDO_USER"
  echo "Added $SUDO_USER to kvm and libvirt groups"
fi

echo ""
echo "=== 57-kvm: enabling libvirtd ==="
systemctl enable --now libvirtd

echo ""
echo "=== Post-condition assertions ==="

systemctl is-active libvirtd || { echo "ERROR: libvirtd not active" >&2; exit 1; }
echo "  PASS: libvirtd is active"

if lsmod | grep -q '^kvm\b'; then
  echo "  PASS: kvm kernel module loaded"
else
  echo "  INFO: kvm kernel module not loaded — bare-metal or nested virt required"
fi

echo ""
echo "57-kvm complete."
