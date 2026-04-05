#!/usr/bin/env bash
# deploy.sh — Build image on server, restart the container.
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

# ── Build & restart on server ──────────────────────────────────
echo ""
echo "==> Building and restarting container on server..."
ssh "$SERVER" bash <<REMOTE
set -euo pipefail
cd "$REMOTE_DIR"

echo "--- Building image ---"
podman build --network=host -t "$CONTAINER_NAME:latest" .

echo "--- Stopping existing container (if any) ---"
podman stop "$CONTAINER_NAME" 2>/dev/null && echo "Stopped." || echo "Not running."
podman rm   "$CONTAINER_NAME" 2>/dev/null && echo "Removed." || echo "Not found."

echo "--- Starting container ---"
# Stories are mounted as a volume so uploads survive restarts/rebuilds
podman run -d \
  --name "$CONTAINER_NAME" \
  --restart=always \
  -p "$PORT":8080 \
  -v "$REMOTE_DIR/stories":/stories:Z \
  -e SECRET_KEY="$SECRET_KEY" \
  -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
  "$CONTAINER_NAME:latest"

echo ""
echo "--- Container status ---"
podman ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# ── Generate & install systemd unit for auto-start on reboot ──
echo ""
echo "--- Installing systemd service ---"
podman generate systemd \
  --name "$CONTAINER_NAME" \
  --restart-policy=always \
  --files \
  --new

UNIT_FILE="container-${CONTAINER_NAME}.service"
if [[ -f "\$UNIT_FILE" ]]; then
  mv "\$UNIT_FILE" /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable "$CONTAINER_NAME" 2>/dev/null || \
    systemctl enable "container-$CONTAINER_NAME" 2>/dev/null || true
  echo "Systemd service enabled."
fi
REMOTE

echo ""
echo "==> Deploy complete!"
echo "    Visit: http://$SERVER (or your domain)"
