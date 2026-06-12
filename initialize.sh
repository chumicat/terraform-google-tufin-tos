#!/bin/bash
# ============================================================================
# TOS Aurora — GCP etcd Disk Initialization
# Partitions, formats, and mounts the secondary etcd disk at the path K3S
# expects. Run once before TOS installation.
#
# Why no LVM on the boot disk:
#   Rocky Linux 9 GCP-optimized image allocates the root XFS partition to
#   fill the entire boot disk. XFS cannot be shrunk, so there is no free
#   space available to create new partitions for LVM. The 650GB root
#   filesystem satisfies Tufin's directory size requirements (/opt min 400GB,
#   /var min 200GB, /tmp min 25GB) within the single filesystem — no separate
#   mount points are needed.
#
# What this script does:
#   1. Auto-detects the boot disk (whatever is mounted at /)
#   2. Auto-detects the etcd disk (the other disk)
#   3. Creates a partition, formats ext4, mounts at /var/lib/rancher/k3s/server/db
#   4. Persists mount in /etc/fstab
#
# Matches the Tufin doc manual etcd procedure exactly.
# ============================================================================

exec > /var/log/tufin-disk-setup.log 2>&1
set -ex

# ── Sentinel: prevent re-running ────────────────────────────────────────────
SENTINEL="/etc/tufin-disk-setup-done"
if [ -f "$SENTINEL" ]; then
    echo "etcd disk setup already completed — skipping."
    exit 0
fi

# ── Detect boot disk and etcd disk ──────────────────────────────────────────
# Boot disk: the disk that owns the partition mounted at /
# etcd disk: everything else (there is exactly one other disk in this setup)

ROOT_PART=$(findmnt -n -o SOURCE /)
BOOT_DISK=$(lsblk -n -o PKNAME "$ROOT_PART")
BOOT_DISK="/dev/${BOOT_DISK}"
echo "Boot disk detected: ${BOOT_DISK}"

# Find the first disk that is not the boot disk
ETCD_DISK=$(lsblk -d -n -p -o NAME | grep -v "^${BOOT_DISK}$" | head -1)
if [ -z "$ETCD_DISK" ]; then
    echo "ERROR: etcd disk not found." >&2
    exit 1
fi
echo "etcd disk detected: ${ETCD_DISK}"

# Wait for udev to settle
udevadm settle
sleep 3

# ── Partition the etcd disk ──────────────────────────────────────────────────
# Use GPT (matches GCP disk convention) with a single primary partition.
# Per Tufin doc: msdos label, primary partition, ext4.
# We use GPT here to match GCP's own partition convention.

parted -s -a optimal "$ETCD_DISK" mklabel gpt mkpart primary ext4 1MiB 100%
partprobe "$ETCD_DISK"
udevadm settle
sleep 2

# ── Format ext4 with UUID and ETCD label ────────────────────────────────────
BLOCK_UUID="$(uuidgen)"
ETCD_PART="${ETCD_DISK}1"
mkfs.ext4 -L ETCD -U "$BLOCK_UUID" "$ETCD_PART"

# ── Verify partition is visible ──────────────────────────────────────────────
blkid | grep "$BLOCK_UUID"

# ── Create mount point ───────────────────────────────────────────────────────
mkdir -p /var/lib/rancher/k3s/server/db

# ── Persist in fstab ─────────────────────────────────────────────────────────
cp /etc/fstab /etc/fstab.bak
echo "UUID=${BLOCK_UUID} /var/lib/rancher/k3s/server/db ext4 defaults 0 0" >> /etc/fstab

# ── Mount now (no reboot needed for a new disk) ──────────────────────────────
systemctl daemon-reload
mount /var/lib/rancher/k3s/server/db

# ── Verify ───────────────────────────────────────────────────────────────────
mount | grep "/var/lib/rancher/k3s/server/db"
echo "etcd disk mounted successfully."

# ── Download TOS package (optional) ─────────────────────────────────────────
# Reads the package URL from GCP instance metadata. If the value is non-empty,
# creates /opt/upgrade and downloads the file into it.
# Set tos_package_url in terraform.tfvars (or prod.tfvars) to enable.

METADATA="http://metadata.google.internal/computeMetadata/v1/instance/attributes"
TOS_URL=$(curl -sf -H "Metadata-Flavor: Google" "$METADATA/tos-package-url" || true)
TOS_DIR=$(curl -sf -H "Metadata-Flavor: Google" "$METADATA/tos-package-dir" || true)

if [ -n "$TOS_URL" ]; then
    echo "Downloading TOS package from: $TOS_URL"
    echo "Destination directory: $TOS_DIR"
    dnf install -y wget
    install -d -m 0777 "$TOS_DIR"
    wget -P "$TOS_DIR" "$TOS_URL"
    echo "Download complete: $(ls "$TOS_DIR")"
else
    echo "tos-package-url not set — skipping download."
fi

# ── Done ─────────────────────────────────────────────────────────────────────
touch "$SENTINEL"
echo "Initialization complete. No reboot required."
