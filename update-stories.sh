#!/usr/bin/env bash
# update-stories.sh — Sync story files to server WITHOUT rebuilding the image.
# Use this when you've only added/edited stories locally (fast, no rebuild needed).
# Stories on the server are served directly from the volume-mounted host directory,
# so they're live immediately after rsync — no container restart needed.
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

echo "==> Syncing stories to $SERVER..."
rsync -az --progress stories/ "$SERVER:$REMOTE_DIR/stories/"

echo ""
echo "==> Done — stories are live immediately (volume mount, no restart needed)."
