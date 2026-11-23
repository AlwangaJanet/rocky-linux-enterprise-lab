#!/usr/bin/env bash
# Idempotent IAM, SGID/POSIX ACLs, and Least-Privilege Sudo Script (Rocky Linux 10)
set -euo pipefail
RELEASE_DIR="/srv/app-data/releases"
SUDOERS_FILE="/etc/sudoers.d/app-operations"
# 1. Safety Guard: Require root privileges
if [[ $EUID -ne 0 ]]; then
  echo "Error: Run as root (sudo $0)" >&2
  exit 1
fi
echo "[OK] Pre-flight root check passed."
# 2. Provision Departmental Groups & Users Idempotently
groupadd -f devops
groupadd -f sec_audit

if id -u alice_ops >/dev/null 2>&1; then
  usermod -aG devops alice_ops
else
  useradd -m -s /bin/bash -G devops alice_ops
fi

if id -u bob_auditor >/dev/null 2>&1; then
  usermod -aG sec_audit bob_auditor
else
  useradd -m -s /bin/bash -G sec_audit bob_auditor
fi
chage -M 90 -W 7 alice_ops
echo "[OK] Users, groups, and 90-day password policy verified."

# 3. Configure Collaborative SGID Directory & Default POSIX ACLs
mkdir -p "$RELEASE_DIR"
chown root:devops "$RELEASE_DIR"
chmod 2775 "$RELEASE_DIR"

setfacl -m u:bob_auditor:rx "$RELEASE_DIR"
setfacl -m g:devops:rwx "$RELEASE_DIR"
setfacl -d -m g:devops:rwx "$RELEASE_DIR"
setfacl -d -m u:bob_auditor:rx "$RELEASE_DIR"
echo "[OK] SGID (2775) and POSIX ACLs applied to $RELEASE_DIR."

# 4. Stage, Validate (visudo -cf), and Install Least-Privilege Sudo Rules
TMP_SUDOERS=$(mktemp)
cat << 'SUDO' > "$TMP_SUDOERS"
# Least-privilege operational sudo rules (Project 03)
%devops ALL=(root) NOPASSWD: /usr/bin/systemctl status app-web.service, /usr/bin/systemctl status app-web.service --no-pager, /usr/bin/systemctl restart app-web.service, /usr/bin/systemctl reload app-web.service
bob_auditor ALL=(root) NOPASSWD: /usr/bin/systemctl status app-web.service, /usr/bin/systemctl status app-web.service --no-pager, /usr/bin/journalctl -u app-web.service --no-pager
SUDO

if visudo -cf "$TMP_SUDOERS" >/dev/null; then
  install -o root -g root -m 0440 "$TMP_SUDOERS" "$SUDOERS_FILE"
  rm -f "$TMP_SUDOERS"
  echo "[OK] Sudoers policy validated with visudo and installed at $SUDOERS_FILE."
else
  rm -f "$TMP_SUDOERS"
  echo "Error: Sudoers syntax validation failed; aborting without modifying $SUDOERS_FILE." >&2
  exit 1
fi

# 5. Automated End-to-End Verification (ACL Inheritance & Sudo Boundaries)
su - alice_ops -c "echo 'v1.0.0 release artifact' > ${RELEASE_DIR}/release-v1.txt"
su - bob_auditor -c "grep -Fq 'v1.0.0 release artifact' ${RELEASE_DIR}/release-v1.txt"
if su - bob_auditor -c "echo 'tamper' >> ${RELEASE_DIR}/release-v1.txt" 2>/dev/null; then
  echo "Error: bob_auditor unexpectedly wrote to $RELEASE_DIR!" >&2
  exit 1
fi
su - alice_ops -c "sudo -n /usr/bin/systemctl status app-web.service --no-pager >/dev/null"
if su - alice_ops -c "sudo -n /usr/bin/systemctl restart sshd.service" 2>/dev/null; then
  echo "Error: alice_ops unexpectedly permitted to restart sshd.service!" >&2
  exit 1
fi
echo "[OK] Verification passed: SGID/ACL inheritance and least-privilege sudo boundaries enforced."
