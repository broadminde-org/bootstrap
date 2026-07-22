#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 57-kvm — Install KVM virtualization stack.
#
# What this script does:
#
#   1. Installs QEMU/KVM, libvirt, and supporting packages.
#
#   2. Creates /opt/kvm/ (data/vm-images/isos subdirs), owned by
#      the deploy user. Apps reference these via their .env.
#
#   3. Enables and starts libvirtd.
#
#   4. Validates that the KVM kernel module is loaded (/dev/kvm).
#
#   5. Persists bridge-networking sysctls so VM NAT and bridge
#      forwarding survive reboots.
#
#   6. Reports the libvirt GID so apps (e.g. kvm-ctl) can set KVM_GID
#      in their .env for Docker volume permission matching.
#
#   7. Installs a udev rule that sets the group of QEMU serial-console
#      PTY devices to libvirt-qemu with mode 0660, so the deploy user
#      (already a member of libvirt-qemu) can read/write them without
#      sudo. The devpts mount defaults to gid=tty,mode=0600 on Debian,
#      which blocks non-root access — this rule overrides it.
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
  if ! groups "$SUDO_USER" 2>/dev/null | grep -q '\blibvirt\b'; then
    echo "  NOTE: Group changes require a new login to take effect."
  fi

  # Create /opt/kvm tree — owned by the deploy user so apps don't need root.
  # Subdirs match env vars that kvm-ctl and other KVM apps reference.
  KVM_OPT=/opt/kvm
  install -m 0755 -d "${KVM_OPT}/data" "${KVM_OPT}/vm-images" "${KVM_OPT}/isos"
  chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$KVM_OPT"
  echo "Created $KVM_OPT/{data,vm-images,isos} (owner: $SUDO_USER)"

  # Write system-wide env vars so all shells (and docker compose) pick them up.
  # /etc/profile.d/ scripts are sourced by login shells and bash --login.
  cat > /etc/profile.d/kvm.sh <<KVM_ENV_EOF
# Managed by bootstrap/init.d/57-kvm. Do not edit by hand.
export KVM_CTL_DATA_DIR=${KVM_OPT}/data
export KVM_CTL_VM_DISK_DIR=${KVM_OPT}/vm-images
export KVM_CTL_ISOS_DIR=${KVM_OPT}/isos
KVM_ENV_EOF
  chmod 0644 /etc/profile.d/kvm.sh
  echo "Wrote /etc/profile.d/kvm.sh (sourced by login shells)"
fi

echo ""
echo "=== 57-kvm: enabling libvirtd ==="
if ! systemctl enable --now libvirtd 2>/dev/null; then
  echo "ERROR: libvirtd failed to start. Check: sudo systemctl status libvirtd" >&2
  exit 1
fi

# Verify libvirtd is actually running (enable --now can succeed but
# the daemon may crash immediately).
if ! systemctl is-active --quiet libvirtd; then
  echo "ERROR: libvirtd is not active after enable. Check: sudo systemctl status libvirtd" >&2
  exit 1
fi
echo "  libvirtd is active"

echo ""
echo "=== Post-condition assertions ==="

# Verify KVM hardware acceleration is available. /dev/kvm is the
# authoritative check — it confirms both the kernel module is loaded
# AND the CPU has VT-x/AMD-V. lsmod alone can show the module present
# but without actual hardware support (e.g. in nested virt without
# proper config).
if [[ -e /dev/kvm ]]; then
  echo "  PASS: /dev/kvm present — KVM hardware acceleration available"
else
  if lsmod | grep -q '^kvm\b'; then
    echo "  WARNING: kvm module loaded but /dev/kvm missing — check BIOS VT-x/AMD-V" >&2
  else
    echo "  INFO: kvm kernel module not loaded — bare-metal or nested virt required"
  fi
fi

# ---------------------------------------------------------------------------
# Kernel sysctls for KVM/libvirt bridge networking.
#
# net.ipv4.ip_forward              — allows the host to forward packets
#                                    between VM virtual NICs and the
#                                    physical interface. Without it, VMs
#                                    have no outbound internet access.
#
# net.bridge.bridge-nf-call-iptables — routes bridged (L2) traffic through
#                                    iptables (L3) rules so ufw/Docker
#                                    firewall rules apply to VM traffic
#                                    crossing a libvirt bridge.
#
# net.bridge.bridge-nf-call-ip6tables — same for ip6tables (IPv6).
#
# Persisted in a sysctl.d drop-in so they survive reboots.
# ---------------------------------------------------------------------------
KVM_SYSCTL_FILE=/etc/sysctl.d/99-kvm-ctl.conf
install -m 0755 -d /etc/sysctl.d

NEED_SYSCTLS=0
for setting in net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables; do
  val="$(sysctl -n "$setting" 2>/dev/null || echo '0')"
  if [[ "$val" != "1" ]]; then
    NEED_SYSCTLS=1
    break
  fi
done

if [[ "$NEED_SYSCTLS" -eq 0 ]]; then
  echo "  KVM sysctls already active — skipping drop-in."
else
  cat > "$KVM_SYSCTL_FILE" <<'KVM_SYSCTL_EOF'
# Managed by bootstrap/init.d/57-kvm.
# Required for KVM/libvirt bridge networking; do not edit by hand.
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
KVM_SYSCTL_EOF
  sysctl --system >/dev/null
  echo "  Applied KVM sysctls via ${KVM_SYSCTL_FILE}"
fi

# ---------------------------------------------------------------------------
# Report libvirt GID — apps like kvm-ctl need this for Docker volume
# permission matching (KVM_GID in .env).
# ---------------------------------------------------------------------------
LIBVIRT_GID="$(getent group libvirt | cut -d: -f3 || echo '')"
if [[ -n "$LIBVIRT_GID" ]]; then
  echo ""
  echo "  libvirt GID: $LIBVIRT_GID (set KVM_GID=$LIBVIRT_GID in app .env)"
fi

# ---------------------------------------------------------------------------
# AppArmor check — libvirt AppArmor profiles can block non-standard
# storage paths for VM images and ISOs.
# ---------------------------------------------------------------------------
if command -v aa-status &>/dev/null && aa-status --enabled 2>/dev/null; then
  echo "  AppArmor is enabled. Verify libvirt profiles allow your storage paths."
  echo "  See: /etc/apparmor.d/libvirt/"
fi

# ---------------------------------------------------------------------------
# udev rule — fix PTY permissions for QEMU serial consoles.
#
# The devpts filesystem on Debian is mounted with gid=tty,mode=0600,
# which forces all PTY nodes to be group:tty with owner-only (0600)
# permissions. QEMU runs as libvirt-qemu, so its serial-console PTYs
# are owned by libvirt-qemu:tty with no group access — blocking the
# deploy user (who is in the libvirt-qemu group) from reading them
# via virsh console or direct PTY access.
#
# This udev rule matches PTYs owned by libvirt-qemu and overrides the
# group to libvirt-qemu with mode 0660, granting read/write to
# members of that group.
# ---------------------------------------------------------------------------
UDEV_RULE_FILE=/etc/udev/rules.d/99-kvm-pty.rules
UDEV_RULE='SUBSYSTEM=="tty", KERNEL=="pts/*", OWNER=="libvirt-qemu", GROUP="libvirt-qemu", MODE="0660"'
UDEV_RULE_HEADER="# Managed by bootstrap/init.d/57-kvm. Do not edit by hand."

NEED_UDEV=0
if [[ ! -f "$UDEV_RULE_FILE" ]]; then
  NEED_UDEV=1
else
  CURRENT_RULE="$(grep -v '^#' "$UDEV_RULE_FILE" | grep -v '^$' || true)"
  if [[ "$CURRENT_RULE" != "$UDEV_RULE" ]]; then
    NEED_UDEV=1
  fi
fi

if [[ "$NEED_UDEV" -eq 1 ]]; then
  install -m 0755 -d /etc/udev/rules.d
  printf '%s\n%s\n' "$UDEV_RULE_HEADER" "$UDEV_RULE" > "$UDEV_RULE_FILE"
  udevadm control --reload
  udevadm trigger --subsystem-match=tty
  echo "  Installed udev rule: ${UDEV_RULE_FILE}"
  echo "  (PTY devices owned by libvirt-qemu will get group:libvirt-qemu mode:0660)"
else
  echo "  udev rule already up to date — skipping."
fi

echo ""
echo "57-kvm complete."
