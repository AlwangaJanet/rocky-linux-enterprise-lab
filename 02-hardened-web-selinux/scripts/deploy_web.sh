#!/usr/bin/env bash
# Idempotent Hardened Web Server & SELinux Deployment Script (Rocky Linux 10)
set -euo pipefail

WEB_ROOT="/srv/app-data/www"
PORT="8080"
SERVICE_NAME="app-web.service"

# 1. Safety Guard: Ensure script runs as root
if [[ $EUID -ne 0 ]]; then
  echo "Error: Run as root (sudo $0)" >&2
  exit 1
fi
echo "[OK] Pre-flight root check passed."

# 2. Ensure Web Root & Default Page Exist
mkdir -p "$WEB_ROOT"
if [[ ! -f "$WEB_ROOT/index.html" ]]; then
  echo "<h1>Rocky Linux 10 Hardened Web Server - Port $PORT</h1>" > "$WEB_ROOT/index.html"
fi

# 3. Apply Persistent SELinux File Context (using -C to check local rules cleanly)
FCONTEXT_PATTERN="${WEB_ROOT}(/.*)?"
LOCAL_FCONTEXTS=$(semanage fcontext -l -C)
if grep -Fq "$FCONTEXT_PATTERN" <<< "$LOCAL_FCONTEXTS"; then
  semanage fcontext -m -t httpd_sys_content_t "$FCONTEXT_PATTERN"
else
  semanage fcontext -a -t httpd_sys_content_t "$FCONTEXT_PATTERN"
fi
restorecon -Rv "$WEB_ROOT"
echo "[OK] SELinux file contexts verified on $WEB_ROOT."

# 4. Authorize Custom Port in SELinux Policy (http_port_t)
LOCAL_PORTS=$(semanage port -l -C)
if grep -Eq "^http_port_t\s+tcp\s+.*\b${PORT}\b" <<< "$LOCAL_PORTS"; then
  echo "[OK] SELinux port ${PORT}/tcp already authorized as http_port_t."
elif semanage port -l | grep -Eq "\btcp\b.*\b${PORT}\b"; then
  semanage port -m -t http_port_t -p tcp "$PORT"
  echo "[OK] SELinux port ${PORT}/tcp modified to http_port_t."
else
  semanage port -a -t http_port_t -p tcp "$PORT"
  echo "[OK] SELinux port ${PORT}/tcp added as http_port_t."
fi

# 5. Open Port in firewalld Permanently
if ! firewall-cmd --permanent --query-port="${PORT}/tcp" >/dev/null; then
  firewall-cmd --permanent --add-port="${PORT}/tcp"
  firewall-cmd --reload
  echo "[OK] Firewalld opened ${PORT}/tcp and reloaded."
else
  echo "[OK] Firewalld already allows ${PORT}/tcp."
fi

# 6. Write Hardened systemd Unit File & Enable Service
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}"
cat << UNIT > "$UNIT_PATH"
[Unit]
Description=Hardened Staging Web Server (Port ${PORT})
After=network.target srv-app\x2ddata.mount
Requires=srv-app\x2ddata.mount

[Service]
Type=simple
User=nobody
Group=nobody
WorkingDirectory=${WEB_ROOT}
ExecStart=/usr/bin/python3.12 -m http.server ${PORT} --bind 0.0.0.0
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadOnlyPaths=${WEB_ROOT}
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"
echo "[OK] Systemd unit $SERVICE_NAME deployed and active."

# 7. Automated End-to-End Health Check
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${PORT}")
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "[OK] Verification passed: HTTP $HTTP_CODE returned on port ${PORT} with SELinux $(getenforce)."
else
  echo "Error: Expected HTTP 200 on port ${PORT}, got $HTTP_CODE" >&2
  exit 1
fi
