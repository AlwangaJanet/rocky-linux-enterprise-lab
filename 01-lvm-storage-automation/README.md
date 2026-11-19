# Project 01: Enterprise LVM Storage Provisioning, Live Expansion & Boot Recovery

## Objective
Provision resilient, scalable block storage on **Rocky Linux 10.2 (Kernel 6.12)** using Logical Volume Manager (LVM) and the XFS filesystem, perform a zero-downtime online expansion across hot-added virtual disks, and execute a `systemd` Emergency Mode recovery from a corrupted `/etc/fstab`.

## Storage Architecture
- **Physical Volumes (PVs):** `/dev/sda` (5 GB), `/dev/sdb` (5 GB), `/dev/sdc` (5 GB hot-added SCSI)
- **Volume Group (VG):** `vg_app` (~14.99 GB pooled capacity, ~2.99 GB unallocated buffer)
- **Logical Volume (LV):** `/dev/vg_app/lv_data` (expanded live from 8 GB to 12 GB)
- **Filesystem & Mount:** XFS mounted persistently at `/srv/app-data` via UUID in `/etc/fstab`

## Key Engineering Decisions
1. **Raw Disk PV Initialization (`pvcreate /dev/sdX`):** Initialized dedicated virtual data disks directly without partition tables to simplify capacity scaling and avoid partition boundary alignment overhead.
2. **XFS Filesystem (`mkfs.xfs`):** Selected for high-throughput parallel I/O and rapid online expansion (`lvextend -r` invoking `xfs_growfs`), while intentionally leaving unallocated extents in `vg_app` because XFS cannot shrink.
3. **UUID-Based Persistent Mounting:** Used `blkid` UUIDs in `/etc/fstab` rather than `/dev/sdX` device names so storage mounts remain immune to SCSI bus enumeration changes across reboots.
4. **Idempotent Bash Automation (`scripts/provision_lvm.sh`):** Built with `set -euo pipefail` and state guards (`pvs`, `vgs`, `lvs`, `grep -q`) so the script can be safely re-executed without data loss.

## Break/Fix Incident Drill: Emergency Mode Recovery
- **Fault Simulated:** Corrupted the UUID entry in `/etc/fstab`, forcing `systemd` to halt boot after the 90-second device timeout and drop into `emergency.target`.
- **Root Cause & Fix:** Because `mount -o remount,rw /` consults `/etc/fstab` (which contained the broken UUID), explicitly remounted the root Logical Volume via `mount -o remount,rw /dev/mapper/rlm-root /`, restored `/etc/fstab.bak`, ran `systemctl daemon-reload && mount -a`, and rebooted cleanly with zero data corruption (`sha256sum -c` verified).

## Repository Contents
- `scripts/provision_lvm.sh` — Idempotent LVM provisioning and online resize script
- `outputs/lvm_verification.txt` — Live verification outputs (`pvs`, `vgs`, `lvs`, `lsblk`, `df -hT`, `/etc/fstab`)
