# Project 03: Multi-Team IAM, SGID/POSIX ACLs & Least-Privilege Sudo Governance
## Overview
Implemented and automated multi-team identity, collaborative directory permissions, and granular privilege delegation on **Rocky Linux 10** for two operational personas (`alice_ops` in `devops` and `bob_auditor` in `sec_audit`) without granting broad `wheel` root access.
## Access Control & Governance Architecture
- **Identity & Password Aging (`useradd`, `groupadd`, `chage`):**
- Provisioned isolated functional accounts `alice_ops` (`devops`) and `bob_auditor` (`sec_audit`).
- Enforced a 90-day maximum password rotation policy with a 7-day expiration warning (`chage -M 90 -W 7 alice_ops`).
- **Collaborative SGID Directory & Default POSIX ACLs (`chmod 2775`, `setfacl`):**
- Configured `/srv/app-data/releases` with `root:devops` ownership and mode `2775` (SGID) so newly created artifacts automatically inherit the `devops` group.
- Applied active and default (`-d`) POSIX ACL rules granting `devops` `rwx` collaboration and `bob_auditor` read-only (`r-x` / `r--`) audit access to existing and future files.
- **Least-Privilege Sudo Delegation (`/etc/sudoers.d/app-operations`):**
- Validated policy syntax via `visudo -cf` prior to installation (`0440`, `root:root`).
- Restricted `%devops` to `status`, `restart`, and `reload` exclusively on `app-web.service`, and `bob_auditor` to read-only `systemctl status` and `journalctl` inspection.
## Engineering & Troubleshooting Notes
1. **Offline ACL Tooling (Minimal ISO):** Installed the `acl` package (`setfacl`, `getfacl`) in an offline environment via `/dev/sr0` mounted at `/mnt/disc/Minimal`.
2. **Exact Argument Matching in `sudoers`:** `sudo` enforces literal argument matching; explicitly authorizing both `systemctl status app-web.service` and `systemctl status app-web.service --no-pager` prevented password prompts during non-interactive (`sudo -n`) checks while keeping unrelated units (`sshd.service`) blocked.
## Repository Structure
- `scripts/configure_iam_acl.sh` — Idempotent Bash script that provisions users/groups, applies `chage` aging, configures SGID and default ACLs, validates `sudoers.d` via `mktemp` + `visudo -cf`, and runs automated negative/positive access checks.
- `outputs/iam_acl_sudo_verification.txt` — Captured verification evidence covering `id`, `chage -l`, `getfacl`, `visudo -cf`, and `sudo -l`.
## Usage
chmod +x scripts/configure_iam_acl.sh
sudo ./scripts/configure_iam_acl.sh
