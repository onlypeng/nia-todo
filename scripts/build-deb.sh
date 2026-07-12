#!/bin/bash
# Build a .deb package for nia-todo server.
# Usage: ./scripts/build-deb.sh [version]
# Output: dist/nia-todo-server-v{version}-full.deb

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  VERSION=$(python3 -c "import json; print(json.load(open('src-tauri/tauri.conf.json'))['version'])")
fi
PKG_NAME="nia-todo-server"
DEB_NAME="nia-todo-server-v${VERSION}-full.deb"
BUILD_DIR=$(mktemp -d)
DEBROOT="${BUILD_DIR}/debroot"

echo "Building ${DEB_NAME} (version ${VERSION})..."

# ── Directory structure ──────────────────────
mkdir -p "${DEBROOT}/opt/nia-todo"
mkdir -p "${DEBROOT}/etc/nia-todo"
mkdir -p "${DEBROOT}/var/lib/nia-todo/backups"
mkdir -p "${DEBROOT}/var/lib/nia-todo/avatars"
mkdir -p "${DEBROOT}/var/cache/nia-todo/updates"
mkdir -p "${DEBROOT}/DEBIAN"
mkdir -p "${DEBROOT}/etc/systemd/system"
mkdir -p "${DEBROOT}/etc/sudoers.d"
mkdir -p "${DEBROOT}/lib/systemd/system"

# ── Copy application files ───────────────────
# Copy everything except build artifacts and dev files
for item in api web scripts packaging start.sh requirements.txt; do
  if [ -e "$item" ]; then
    cp -a "$item" "${DEBROOT}/opt/nia-todo/"
  fi
done

# Remove unnecessary files from the package
rm -rf "${DEBROOT}/opt/nia-todo/api/data" 2>/dev/null || true
mkdir -p "${DEBROOT}/opt/nia-todo/api/data"
: > "${DEBROOT}/opt/nia-todo/api/data/.gitkeep"

# Create run-service.sh wrapper
cat > "${DEBROOT}/opt/nia-todo/run-service.sh" <<'RUN'
#!/bin/bash
set -euo pipefail
cd /opt/nia-todo
export PATH="/opt/nia-todo/.venv/bin:${PATH}"
exec ./start.sh
RUN
chmod +x "${DEBROOT}/opt/nia-todo/run-service.sh"
chmod +x "${DEBROOT}/opt/nia-todo/start.sh"

# ── Build wheelhouse for offline install ─────
echo "Building wheelhouse..."
python3 -m pip install --upgrade pip
pip wheel -w "${DEBROOT}/opt/nia-todo/wheelhouse" -r requirements.txt

# ── Configuration ────────────────────────────
cat > "${DEBROOT}/etc/nia-todo/nia-todo.env" <<ENV
NIA_TODO_HOST=auto
NIA_TODO_PORT=8753
NIA_TODO_DATA_DIR=/var/lib/nia-todo
NIA_TODO_DB=nia-todo.db
ENV

# ── Systemd services ─────────────────────────
cp packaging/systemd/nia-todo.service "${DEBROOT}/lib/systemd/system/nia-todo.service"
sed -i 's#ExecStart=/opt/nia-todo/start.sh#ExecStart=/opt/nia-todo/run-service.sh#' "${DEBROOT}/lib/systemd/system/nia-todo.service"

cp packaging/systemd/nia-todo-backup.service "${DEBROOT}/lib/systemd/system/nia-todo-backup.service"
cp packaging/systemd/nia-todo-backup.timer "${DEBROOT}/lib/systemd/system/nia-todo-backup.timer"

# ── sudoers for server update ────────────────
cat > "${DEBROOT}/etc/sudoers.d/nia-todo-server-update" <<'SUDOERS'
nia-todo ALL=(root) NOPASSWD: /usr/local/bin/nia-todo-server-update ""
SUDOERS
chmod 440 "${DEBROOT}/etc/sudoers.d/nia-todo-server-update"

# ── DEBIAN/control ───────────────────────────
INSTALLED_SIZE=$(du -sk "${DEBROOT}" | cut -f1)
cat > "${DEBROOT}/DEBIAN/control" <<CONTROL
Package: ${PKG_NAME}
Version: ${VERSION}
Architecture: all
Maintainer: Tobias Kneidl <noreply@weedpump.com>
Installed-Size: ${INSTALLED_SIZE}
Depends: python3 (>= 3.11), python3-venv, python3-pip
Section: web
Priority: optional
Description: nia-todo self-hosted todo system
 Self-hosted todo system with SQLite + FastAPI + Web UI + offline PWA.
 Includes web frontend, systemd services, and backup tools.
CONTROL

# ── DEBIAN/scripts ───────────────────────────
cat > "${DEBROOT}/DEBIAN/preinst" <<'PREINST'
#!/bin/bash
set -e
# Create user and group if they don't exist
if ! getent group nia-todo >/dev/null; then
  groupadd --system nia-todo
fi
if ! id nia-todo >/dev/null 2>&1; then
  useradd --system --gid nia-todo --home-dir /opt/nia-todo --shell /usr/sbin/nologin nia-todo
fi
exit 0
PREINST
chmod 755 "${DEBROOT}/DEBIAN/preinst"

cat > "${DEBROOT}/DEBIAN/postinst" <<'POSTINST'
#!/bin/bash
set -e

APP_DIR="/opt/nia-todo"
DATA_DIR="/var/lib/nia-todo"
ETC_DIR="/etc/nia-todo"

# Create runtime directories
mkdir -p "${DATA_DIR}/backups" "${DATA_DIR}/avatars" "${DATA_DIR}"

# Backup existing database if present
if [ -f "${DATA_DIR}/nia-todo.db" ]; then
  cp "${DATA_DIR}/nia-todo.db" "${DATA_DIR}/backups/pre-install-$(date +%Y%m%d-%H%M%S).db" || true
fi

# One-time migration from pre-public-package layout
if [ -d "${APP_DIR}/api/data" ]; then
  cp -an "${APP_DIR}/api/data/." "${DATA_DIR}/" || true
fi
rm -rf "${APP_DIR}/api/data"
mkdir -p "${APP_DIR}/api/data"
: > "${APP_DIR}/api/data/.gitkeep"

# Create virtualenv and install dependencies
python3 -m venv "${APP_DIR}/.venv"
if [ -d "${APP_DIR}/wheelhouse" ]; then
  "${APP_DIR}/.venv/bin/pip" install --no-index --find-links="${APP_DIR}/wheelhouse" -r "${APP_DIR}/requirements.txt"
  rm -rf "${APP_DIR}/wheelhouse"
else
  "${APP_DIR}/.venv/bin/pip" install -r "${APP_DIR}/requirements.txt"
fi

# Install CLI tools
install -m 755 "${APP_DIR}/scripts/nia-todo-backup.sh" /usr/local/bin/nia-todo-backup
install -m 755 "${APP_DIR}/scripts/nia-todo-restore.sh" /usr/local/bin/nia-todo-restore
install -m 755 "${APP_DIR}/scripts/nia-todo-admin-password-reset.sh" /usr/local/bin/nia-todo-admin-password-reset
install -m 755 "${APP_DIR}/scripts/nia-todo-server-update.sh" /usr/local/bin/nia-todo-server-update
install -d -m 0755 -o root -g root /var/cache/nia-todo/updates

# Set permissions
chown -R nia-todo:nia-todo "${APP_DIR}" "${DATA_DIR}"
chmod 750 "${DATA_DIR}"
[ ! -f "${DATA_DIR}/vapid_keys.json" ] || chmod 600 "${DATA_DIR}/vapid_keys.json"
chown -R root:root "${ETC_DIR}"

# Enable and start services
systemctl daemon-reload
systemctl enable nia-todo.service
systemctl enable --now nia-todo-backup.timer
systemctl restart nia-todo.service

echo "nia-todo installed/updated in ${APP_DIR}."
echo "Service: systemctl status nia-todo"
echo "Backup timer: systemctl status nia-todo-backup.timer"
echo "Setup: http://YOUR-SERVER:8753/setup"

exit 0
POSTINST
chmod 755 "${DEBROOT}/DEBIAN/postinst"

cat > "${DEBROOT}/DEBIAN/prerm" <<'PRERM'
#!/bin/bash
set -e
if [ "$1" = "remove" ] || [ "$1" = "deconfigure" ]; then
  systemctl stop nia-todo.service || true
  systemctl disable nia-todo.service || true
fi
exit 0
PRERM
chmod 755 "${DEBROOT}/DEBIAN/prerm"

cat > "${DEBROOT}/DEBIAN/postrm" <<'POSTRM'
#!/bin/bash
set -e
if [ "$1" = "purge" ]; then
  systemctl daemon-reload || true
  rm -rf /var/lib/nia-todo /var/cache/nia-todo /etc/nia-todo
  rm -f /usr/local/bin/nia-todo-backup /usr/local/bin/nia-todo-restore
  rm -f /usr/local/bin/nia-todo-admin-password-reset /usr/local/bin/nia-todo-server-update
  rm -f /etc/sudoers.d/nia-todo-server-update
  echo "nia-todo fully removed."
fi
exit 0
POSTRM
chmod 755 "${DEBROOT}/DEBIAN/postrm"

# ── Build the .deb ───────────────────────────
mkdir -p "${ROOT}/dist"
dpkg-deb --build --root-owner-group "${DEBROOT}" "${ROOT}/dist/${DEB_NAME}"

# Clean up
rm -rf "${BUILD_DIR}"

echo ""
echo "✅ Built: dist/${DEB_NAME}"
echo "   Size: $(du -h "${ROOT}/dist/${DEB_NAME}" | cut -f1)"
echo "   SHA256: $(sha256sum "${ROOT}/dist/${DEB_NAME}" | cut -d' ' -f1)"
