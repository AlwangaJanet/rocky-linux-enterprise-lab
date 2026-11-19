# Project 02: Hardened Staging Web Server with SELinux Enforcement

## Overview
Deployed and automated a hardened staging web server on **Rocky Linux 10** serving content from the dedicated LVM XFS storage pool (`/srv/app-data/www`) on non-standard port **8080/tcp**, with **SELinux strictly in `Enforcing` mode**, process-level `systemd` sandboxing, and `firewalld` perimeter filtering.

## Security Architecture
- **SELinux Mandatory Access Control (`Enforcing`):**
  - Registered persistent file context rule `httpd_sys_content_t` on `/srv/app-data/www(/.*)?` via `semanage fcontext` and applied via `restorecon`.
  - Authorized non-standard port `8080/tcp` under `http_port_t` via `semanage port`.
- **Process Sandboxing (`app-web.service`):**
  - Executes unprivileged as `User=nobody` / `Group=nobody`.
  - Enforces `NoNewPrivileges=yes`, `ProtectSystem=strict`, `ProtectHome=yes`, and `ReadOnlyPaths=/srv/app-data/www`.
  - Binds unit lifecycle to `srv-app\x2ddata.mount` so the service starts only after LVM storage mounts cleanly.
- **Network Perimeter (`firewalld`):**
  - Permits only SSH (`22/tcp`) and `8080/tcp` permanently.

## Engineering & Troubleshooting Notes
1. **Offline Package Resolution (Minimal ISO):** Installed `policycoreutils-python-utils` (`semanage`, `restorecon`) in an air-gapped/proxy-restricted environment by mounting `/dev/sr0` and pointing DNF to `file:///mnt/disc/Minimal`.
2. **SELinux Entrypoint Transition (`status=203/EXEC`):** Forcing `SELinuxContext=system_u:system_r:httpd_t:s0` on `/usr/bin/python3` (`bin_t`) triggered a `203/EXEC` failure because SELinux restricts direct `init_t -> httpd_t` transitions on generic `bin_t` binaries. Resolved by targeting `/usr/bin/python3.12` directly while enforcing `systemd` filesystem/privilege sandboxing alongside SELinux file and port policies.

## Repository Structure
- `scripts/deploy_web.sh` — Idempotent Bash script that provisions the web root, applies `semanage` file/port policies, configures `firewalld`, writes `app-web.service`, and runs an HTTP `200` health check.
- `outputs/selinux_web_verification.txt` — Captured command outputs proving SELinux `Enforcing` mode, custom file/port labels, `firewalld` state, `systemd` status, and `curl` response.

## Usage
    chmod +x scripts/deploy_web.sh
    sudo ./scripts/deploy_web.sh
