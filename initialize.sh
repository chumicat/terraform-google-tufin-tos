#!/bin/bash
# ============================================================================
# TOS Aurora — GCP VM Initialization
# Prepares the VM for TOS installation per Tufin doc (Prepare-GCP.htm).
# Runs automatically at first boot via GCP metadata_startup_script.
#
# TWO-PHASE EXECUTION (kernel upgrade requires a reboot before loading modules):
#
#   Phase 1 — runs on first boot:
#     1. OS packages     — EPEL/ELRepo repos, wireguard-tools, rsync, tmux, wget, bind-utils
#     2. SELinux         — disable permanently (Tufin requirement)
#     3. Firewall        — disable firewalld (TOS manages its own iptables)
#     4. PATH            — add /usr/local/bin to root's .bashrc
#     5. Timezone        — set system timezone via timedatectl
#     6. NTP             — configure chrony with custom server (if ntp_server set)
#     7. Kernel upgrade  — dnf upgrade, then reboot
#
#   Phase 2 — runs automatically after the reboot (new kernel active):
#     7. Kernel modules  — write /etc/modules-load.d/tufin.conf and load now
#     8. Kernel params   — write /etc/sysctl.d/tufin.conf and apply now
#     9. etcd disk       — partition, format ext4, mount at K3S expected path
#    10. TOS package     — download, extract, run installer (if URL set in tfvars)
#
# Sentinel files:
#   /etc/tufin-init-phase1-done  — written before reboot; skips Phase 1 on re-run
#   /etc/tufin-init-done         — written at completion; skips entire script
#
# Manual steps after this script completes (not automated):
#   sudo su
#   tmux new-session -s tosinstall
#   /usr/local/bin/tos install --dry-run --modules=ST,SC \
#     --primary-vip=external --services-network=10.100.0.0/24 \
#     --load-model=<small|medium> -d --accept-eula
#   (remove --dry-run to do the actual install)
#
# Monitor progress:
#   gcloud compute instances get-serial-port-output <vm> --zone <zone>
#   Full log on VM: /var/log/tufin-init.log
#
# Why no LVM on the boot disk:
#   Rocky Linux 9 GCP image fills the root XFS partition to 100% of disk.
#   XFS cannot be shrunk, so there is no free space for new partitions.
#   The 650 GB root satisfies Tufin's directory requirements without LVM.
# ============================================================================

exec > /var/log/tufin-init.log 2>&1
set -ex

SENTINEL_PHASE1="/etc/tufin-init-phase1-done"
SENTINEL="/etc/tufin-init-done"

# ── Fully done: skip entirely ────────────────────────────────────────────────
if [ -f "$SENTINEL" ]; then
    echo "Initialization already completed — skipping."
    exit 0
fi

# ── Read configuration from GCP instance metadata ───────────────────────────
METADATA="http://metadata.google.internal/computeMetadata/v1/instance/attributes"
TOS_URL=$(curl -sf -H "Metadata-Flavor: Google" "$METADATA/tos-package-url" || true)
TOS_DIR=$(curl -sf -H "Metadata-Flavor: Google" "$METADATA/tos-package-dir" || true)
NTP_SERVER=$(curl -sf -H "Metadata-Flavor: Google" "$METADATA/ntp-server" || true)
TIMEZONE=$(curl -sf -H "Metadata-Flavor: Google" "$METADATA/timezone" || true)

# ============================================================================
# PHASE 1: OS setup — runs once on first boot, then reboots for new kernel
# ============================================================================

if [ ! -f "$SENTINEL_PHASE1" ]; then
    echo "=== PHASE 1 START ==="

    # ── PART 1: OS PACKAGES ─────────────────────────────────────────────────

    echo "=== Installing OS packages ==="
    dnf makecache

    # EPEL and ELRepo provide wireguard-tools for Rocky Linux 9
    dnf install -y \
        https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm \
        https://www.elrepo.org/elrepo-release-9.el9.elrepo.noarch.rpm

    dnf install -y wireguard-tools rsync tmux wget bind-utils

    # ── PART 2: SELinux ─────────────────────────────────────────────────────

    echo "=== Disabling SELinux ==="
    # TOS Aurora requires SELinux to be disabled (recommended) or in permissive mode.
    # Update config so the setting persists after the upcoming reboot.
    sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
    sed -i 's/^SELINUX=permissive/SELINUX=disabled/' /etc/selinux/config
    # Also disable for the current boot session (no-op if already disabled).
    setenforce 0 || true
    echo "SELinux config: $(grep '^SELINUX=' /etc/selinux/config)"

    # ── PART 3: FIREWALL ────────────────────────────────────────────────────

    echo "=== Disabling firewalld ==="
    # TOS Aurora manages its own iptables rules — firewalld must not be running.
    systemctl disable firewalld --now || true

    # ── PART 4: PATH ────────────────────────────────────────────────────────

    echo "=== Adding /usr/local/bin to root PATH ==="
    # TOS CLI and kubectl are installed at /usr/local/bin. Add permanently so
    # all future SSH sessions and sudo shells can find them without full path.
    grep -qxF 'export PATH="${PATH}:/usr/local/bin"' /root/.bashrc \
        || echo 'export PATH="${PATH}:/usr/local/bin"' >> /root/.bashrc
    export PATH="${PATH}:/usr/local/bin"

    # ── PART 5: TIMEZONE ────────────────────────────────────────────────────

    echo "=== Configuring timezone ==="
    # Falls back to Asia/Taipei if metadata key is empty (matches Terraform default).
    TIMEZONE="${TIMEZONE:-Asia/Taipei}"
    timedatectl set-timezone "$TIMEZONE"
    echo "Timezone set to: $(timedatectl show -p Timezone --value)"

    # ── PART 6: NTP ─────────────────────────────────────────────────────────

    if [ -n "$NTP_SERVER" ]; then
        echo "=== Configuring NTP: $NTP_SERVER ==="
        # Prepend the custom NTP server so it takes priority over the GCP default
        # (metadata.google.internal). chrony is pre-installed on Rocky Linux 9
        # GCP images and starts automatically.
        sed -i "1s|^|server ${NTP_SERVER} iburst\n|" /etc/chrony.conf
        systemctl enable chronyd
        systemctl restart chronyd
        # Step the clock immediately rather than waiting for gradual slew.
        chronyc makestep
        chronyc tracking
    else
        echo "ntp-server not set — retaining GCP default NTP (metadata.google.internal)."
    fi

    # ── PART 7: KERNEL UPGRADE ──────────────────────────────────────────────

    echo "=== Upgrading kernel and all packages ==="
    # Tufin requires the kernel to be up-to-date before TOS installation.
    # A reboot is required afterward to activate the new kernel before loading
    # the wireguard and br_netfilter modules in Phase 2.
    dnf upgrade -y

    touch "$SENTINEL_PHASE1"
    echo "=== Phase 1 complete — rebooting to activate new kernel ==="
    reboot
    exit 0
fi

# ============================================================================
# PHASE 2: Kernel configuration and disk setup — runs after reboot
# ============================================================================

echo "=== PHASE 2 START (post-reboot, new kernel active) ==="

# ── PART 7: KERNEL MODULES ──────────────────────────────────────────────────

echo "=== Configuring kernel modules ==="
tee /etc/modules-load.d/tufin.conf > /dev/null <<'EOF'
br_netfilter
wireguard
overlay
ebtables
ebtable_filter
EOF

# Load all modules now (they will also auto-load on every subsequent boot)
cat /etc/modules-load.d/tufin.conf | xargs modprobe -a

# Verify wireguard loaded
if ! lsmod | grep -q wireguard; then
    echo "ERROR: wireguard module failed to load." >&2
    exit 1
fi
echo "wireguard loaded successfully."

# ── PART 8: KERNEL PARAMETERS ───────────────────────────────────────────────

echo "=== Applying kernel parameters ==="
tee /etc/sysctl.d/tufin.conf > /dev/null <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 10000
net.ipv4.ip_forward = 1
EOF

sysctl --system

# ── PART 9: etcd DISK ───────────────────────────────────────────────────────

echo "=== Setting up etcd disk ==="

# Boot disk: the disk owning the partition mounted at /
ROOT_PART=$(findmnt -n -o SOURCE /)
BOOT_DISK=$(lsblk -n -o PKNAME "$ROOT_PART")
BOOT_DISK="/dev/${BOOT_DISK}"
echo "Boot disk: ${BOOT_DISK}"

# etcd disk: the first disk that is not the boot disk
ETCD_DISK=$(lsblk -d -n -p -o NAME | grep -v "^${BOOT_DISK}$" | head -1)
if [ -z "$ETCD_DISK" ]; then
    echo "ERROR: etcd disk not found." >&2
    exit 1
fi
echo "etcd disk: ${ETCD_DISK}"

udevadm settle
sleep 3

# GPT partition — matches GCP disk convention
parted -s -a optimal "$ETCD_DISK" mklabel gpt mkpart primary ext4 1MiB 100%
partprobe "$ETCD_DISK"
udevadm settle
sleep 2

# Format ext4 with label — matches Tufin doc manual etcd procedure
BLOCK_UUID="$(uuidgen)"
ETCD_PART="${ETCD_DISK}1"
mkfs.ext4 -L ETCD -U "$BLOCK_UUID" "$ETCD_PART"
blkid | grep "$BLOCK_UUID"

# Mount point expected by K3S
mkdir -p /var/lib/rancher/k3s/server/db

# Persist in fstab
cp /etc/fstab /etc/fstab.bak
echo "UUID=${BLOCK_UUID} /var/lib/rancher/k3s/server/db ext4 defaults 0 0" >> /etc/fstab
systemctl daemon-reload
mount /var/lib/rancher/k3s/server/db

mount | grep "/var/lib/rancher/k3s/server/db"
echo "etcd disk mounted successfully."

# ── PART 10: TOS PACKAGE ────────────────────────────────────────────────────

if [ -n "$TOS_URL" ]; then
    echo "=== Downloading TOS package ==="
    echo "URL: $TOS_URL"
    echo "Dir: $TOS_DIR"

    install -d -m 0777 "$TOS_DIR"
    wget -P "$TOS_DIR" "$TOS_URL"

    # Extract the tarball — filename varies by version so use glob
    TARBALL=$(ls "$TOS_DIR"/*.tgz "$TOS_DIR"/*.tar.gz 2>/dev/null | head -1)
    if [ -z "$TARBALL" ]; then
        echo "ERROR: no .tgz or .tar.gz found in $TOS_DIR after download." >&2
        exit 1
    fi
    echo "Extracting: $TARBALL"
    tar -zxvf "$TARBALL" -C "$TOS_DIR"

    # Find and run the installer — installs the TOS CLI to /usr/local/bin/tos
    RUN_FILE=$(ls "$TOS_DIR"/*.run 2>/dev/null | head -1)
    if [ -z "$RUN_FILE" ]; then
        echo "ERROR: no .run file found in $TOS_DIR after extraction." >&2
        exit 1
    fi
    echo "Running TOS installer: $RUN_FILE"
    chmod +x "$RUN_FILE"
    bash "$RUN_FILE"
    chmod +x /usr/local/bin/tos
    echo "TOS CLI installed at: $(ls -lh /usr/local/bin/tos)"
else
    echo "tos-package-url not set — skipping TOS package download."
fi

# ============================================================================
# DONE
# ============================================================================

touch "$SENTINEL"
echo "=== Initialization complete. VM is ready for TOS installation. ==="
echo ""
echo "Next steps (run manually as root):"
echo "  1. sudo su"
echo "  2. tmux new-session -s tosinstall"
echo "  3. tos install --dry-run --modules=ST,SC --primary-vip=external --services-network=10.100.0.0/24 --load-model=medium -d --accept-eula"
echo "     (remove --dry-run to do the actual install)"
