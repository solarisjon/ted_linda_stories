#!/usr/bin/env bash
# deploy.sh — Build image on server, install/restart via Quadlet systemd unit.
# Usage: ./deploy.sh
set -euo pipefail

# ── Load config ────────────────────────────────────────────────
if [[ ! -f .env ]]; then
  echo "Error: .env not found. Copy .env.example to .env and fill it in." >&2
  exit 1
fi
# shellcheck disable=SC1091
source .env

SERVER="${SERVER:?SERVER must be set in .env}"
REMOTE_DIR="${REMOTE_DIR:-/opt/ted-linda-stories}"
CONTAINER_NAME="${CONTAINER_NAME:-ted-linda-stories}"
PORT="${PORT:-80}"
SECRET_KEY="${SECRET_KEY:?SECRET_KEY must be set in .env}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:?ADMIN_PASSWORD must be set in .env}"

echo "==> Deploying Ted & Linda's Stories"
echo "    Target      : $SERVER"
echo "    Remote dir  : $REMOTE_DIR"
echo "    Host port   : $PORT"
echo ""

# ── Sync source to server ──────────────────────────────────────
echo "==> Syncing source files..."
rsync -az --progress \
  --exclude='.git' \
  --exclude='.env' \
  --exclude='__pycache__' \
  --exclude='*.pyc' \
  --exclude='*.tar.gz' \
  ./ "$SERVER:$REMOTE_DIR/"

# ── Seed stories dir on first deploy (--ignore-existing protects uploads) ──
echo "==> Seeding stories (skips any already on server)..."
rsync -az --ignore-existing stories/ "$SERVER:$REMOTE_DIR/stories/"

# ── Build & install on server ──────────────────────────────────
echo ""
echo "==> Building image and installing Quadlet service on server..."
ssh "$SERVER" bash <<REMOTE
set -euo pipefail
cd "$REMOTE_DIR"

echo "--- Ensuring stories directory exists with correct ownership ---"
mkdir -p "$REMOTE_DIR/stories"
chown -R 1001:1001 "$REMOTE_DIR/stories"

echo "--- Building image ---"
podman build --network=host -t "$CONTAINER_NAME:latest" .

echo "--- Writing container env file (root-only, not baked into image) ---"
mkdir -p /etc/containers/systemd
printf 'SECRET_KEY=%s\nADMIN_PASSWORD=%s\n' "$SECRET_KEY" "$ADMIN_PASSWORD" \
  > /etc/containers/systemd/$CONTAINER_NAME.env
chmod 600 /etc/containers/systemd/$CONTAINER_NAME.env

echo "--- Writing Quadlet .container unit ---"
# Quadlet processes this after 'systemctl daemon-reload' and creates a
# managed service that auto-starts on boot with the volume mount intact.
printf '%s\n' \
  '[Unit]' \
  'Description=Ted and Linda Stories web app' \
  'After=network-online.target' \
  'Wants=network-online.target' \
  '' \
  '[Container]' \
  "Image=localhost/$CONTAINER_NAME:latest" \
  'PublishPort=127.0.0.1:8080:8080' \
  "Volume=$REMOTE_DIR/stories:/stories:Z" \
  "EnvironmentFile=/etc/containers/systemd/$CONTAINER_NAME.env" \
  '' \
  '[Service]' \
  'Restart=always' \
  'TimeoutStartSec=60' \
  '' \
  '[Install]' \
  'WantedBy=multi-user.target default.target' \
  > /etc/containers/systemd/$CONTAINER_NAME.container

echo "--- Stopping any existing container (pre-Quadlet or stale) ---"
podman stop "$CONTAINER_NAME"         2>/dev/null && echo "Stopped." || echo "Not running."
podman rm   "$CONTAINER_NAME"         2>/dev/null && echo "Removed." || echo "Not found."
podman stop "systemd-$CONTAINER_NAME" 2>/dev/null || true
podman rm   "systemd-$CONTAINER_NAME" 2>/dev/null || true

echo "--- Reloading systemd (picks up Quadlet unit) ---"
systemctl daemon-reload

echo "--- Starting / restarting service ---"
# Quadlet units are generated (not installed), so use start/restart not enable.
# The generator ensures auto-start on boot via WantedBy in the .container file.
if systemctl is-active --quiet "$CONTAINER_NAME" 2>/dev/null; then
  systemctl restart "$CONTAINER_NAME"
  echo "Service restarted."
else
  systemctl start "$CONTAINER_NAME"
  echo "Service started."
fi

echo ""
echo "--- Container status ---"
podman ps --filter "name=systemd-$CONTAINER_NAME" \
  --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || \
  podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
REMOTE

echo ""
echo "==> Deploy complete!"
echo "    Visit: http://$SERVER (or your domain)"
