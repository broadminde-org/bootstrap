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
# Group membership (kvm, libvirt) is handled by 20-groups and must
# have run before this step so the deploy user can manage VMs without
# sudo. A fresh login is required after group changes take effect.
#
# Run as root (sudo ./init.sh 57-kvm).

echo "=== 57-kvm: installing KVM + libvirt packages ==="

apt-get install -y \
  qemu-kvm \
  libvirt-daemon-system \
  libvirt-clients \
  bridge-utils \
  virtinst

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
