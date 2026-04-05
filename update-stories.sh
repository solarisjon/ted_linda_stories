#!/usr/bin/env bash
# update-stories.sh — Sync story files and restart WITHOUT rebuilding the image.
# Use this when you've only added/edited stories (fast, no rebuild needed).
# Usage: ./update-stories.sh
set -euo pipefail

if [[ ! -f .env ]]; then
  echo "Error: .env not found." >&2
  exit 1
fi
# shellcheck disable=SC1091
source .env

SERVER="${SERVER:?SERVER must be set in .env}"
REMOTE_DIR="${REMOTE_DIR:-/opt/ted-linda-stories}"
CONTAINER_NAME="${CONTAINER_NAME:-ted-linda-stories}"

echo "==> Syncing stories to $SERVER..."
rsync -az --progress stories/ "$SERVER:$REMOTE_DIR/stories/"

echo "==> Restarting container to pick up new stories..."
ssh "$SERVER" bash <<REMOTE
set -euo pipefail

# Stop and re-run with updated stories bind-mount
podman stop "$CONTAINER_NAME"
podman rm   "$CONTAINER_NAME"

PORT=\$(podman inspect "$CONTAINER_NAME" 2>/dev/null \
  | python3 -c "import sys,json; c=json.load(sys.stdin); \
    p=c[0]['HostConfig']['PortBindings']; \
    print(list(p.values())[0][0]['HostPort'])" 2>/dev/null || echo "80")

# Fallback: just use the port from .env if inspect fails
PORT="${PORT:-80}"

podman run -d \
  --name "$CONTAINER_NAME" \
  --restart=always \
  -p "\$PORT":8080 \
  -v "$REMOTE_DIR/stories":/stories:ro,Z \
  "$CONTAINER_NAME:latest"

echo "Done — stories updated, container restarted."
podman ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}"
REMOTE
