#!/usr/bin/env bash
# setup-server.sh — One-time setup on the Debian 13 VPS.
# Run this ONCE before your first deploy.
# Usage: ./setup-server.sh
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

echo "==> Setting up server: $SERVER"
echo "    Remote dir  : $REMOTE_DIR"
echo "    Host port   : $PORT"
echo ""

ssh "$SERVER" bash <<REMOTE
set -euo pipefail

echo "--- Installing Podman ---"
apt-get update -qq
apt-get install -y podman

echo "--- Podman version ---"
podman --version

echo "--- Creating app directory ---"
mkdir -p "$REMOTE_DIR"

echo "--- Enabling lingering for root (podman systemd) ---"
# For root deployments this is a no-op, but included for completeness
loginctl enable-linger root 2>/dev/null || true

echo ""
echo "Server setup complete. Run ./deploy.sh to deploy the app."
REMOTE
