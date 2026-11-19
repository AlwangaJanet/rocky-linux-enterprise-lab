#!/usr/bin/env bash
# Idempotent LVM Provisioning & Online Expansion Script for Rocky Linux 10
set -euo pipefail

VG_NAME="vg_app"
LV_NAME="lv_data"
MOUNT_POINT="/srv/app-data"
TARGET_SIZE="12G"
DISKS=("/dev/sda" "/dev/sdb" "/dev/sdc")

if [[ $EUID -ne 0 ]]; then
  echo "Error: Run as root (sudo $0)" >&2
  exit 1
fi

for disk in "${DISKS[@]}"; do
  if [[ ! -b "$disk" ]]; then
    echo "Error: Block device $disk not found." >&2
    exit 1
  fi
  if ! pvs "$disk" &>/dev/null; then
    echo "Initializing Physical Volume on $disk..."
    pvcreate "$disk"
  fi
done

if ! vgs "$VG_NAME" &>/dev/null; then
  echo "Creating Volume Group $VG_NAME..."
  vgcreate "$VG_NAME" "${DISKS[@]}"
else
  for disk in "${DISKS[@]}"; do
    if ! pvs --noheadings -o vg_name "$disk" | grep -qw "$VG_NAME"; then
      echo "Extending $VG_NAME with $disk..."
      vgextend "$VG_NAME" "$disk"
    fi
  done
fi

LV_PATH="/dev/${VG_NAME}/${LV_NAME}"
if ! lvs "$LV_PATH" &>/dev/null; then
  echo "Creating Logical Volume $LV_NAME ($TARGET_SIZE)..."
  lvcreate -L "$TARGET_SIZE" -n "$LV_NAME" "$VG_NAME"
  mkfs.xfs "$LV_PATH"
else
  echo "Ensuring $LV_PATH is extended to $TARGET_SIZE..."
  lvextend -r -L "$TARGET_SIZE" "$LV_PATH" || true
fi

mkdir -p "$MOUNT_POINT"
UUID=$(blkid -s UUID -o value "$LV_PATH")
if ! grep -q "$UUID" /etc/fstab; then
  echo "UUID=$UUID $MOUNT_POINT xfs defaults,nofail 0 0" >> /etc/fstab
  systemctl daemon-reload
fi

mount -a
df -hT "$MOUNT_POINT"
