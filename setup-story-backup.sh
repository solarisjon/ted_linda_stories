#!/usr/bin/env bash
# setup-story-backup.sh — One-time setup: back up stories to a GitHub repo via git.
#
# Usage:
#   ./setup-story-backup.sh https://github.com/YOUR_USER/YOUR_STORIES_REPO.git
#
# What it does:
#   1. Generates a dedicated SSH deploy key on the server
#   2. Initialises a git repo in the stories directory
#   3. Creates /usr/local/bin/stories-backup (the commit+push script)
#   4. Installs a systemd timer that runs it every hour
#
# After running, you'll be shown a public key to add to the GitHub repo
# as a deploy key (Settings → Deploy keys → Add deploy key, check "Allow writes").
set -euo pipefail

REPO_URL="${1:?Usage: $0 <github-repo-url>}"

if [[ ! -f .env ]]; then
  echo "Error: .env not found." >&2
  exit 1
fi
# shellcheck disable=SC1091
source .env

SERVER="${SERVER:?SERVER must be set in .env}"
REMOTE_DIR="${REMOTE_DIR:-/opt/ted-linda-stories}"

echo "==> Setting up story backup on $SERVER"
echo "    Stories dir : $REMOTE_DIR/stories"
echo "    GitHub repo : $REPO_URL"
echo ""

ssh "$SERVER" bash <<REMOTE
set -euo pipefail

STORIES_DIR="$REMOTE_DIR/stories"
KEY_FILE="/root/.ssh/stories_backup_ed25519"
REPO_URL="$REPO_URL"

# ── 1. Generate deploy key ─────────────────────────────────────
if [[ ! -f "\$KEY_FILE" ]]; then
  echo "--- Generating SSH deploy key ---"
  ssh-keygen -t ed25519 -C "stories-backup@\$(hostname)" -f "\$KEY_FILE" -N ""
else
  echo "--- SSH deploy key already exists, reusing ---"
fi

echo ""
echo "================================================================"
echo " DEPLOY KEY — add this to your GitHub repo:"
echo " GitHub repo → Settings → Deploy keys → Add deploy key"
echo " Title: stories-backup-server"
echo " Check: Allow write access"
echo "================================================================"
cat "\$KEY_FILE.pub"
echo "================================================================"
echo ""

# ── 2. Configure SSH to use this key for GitHub ────────────────
SSH_CONFIG="/root/.ssh/config"
if ! grep -q "Host github-stories" "\$SSH_CONFIG" 2>/dev/null; then
  cat >> "\$SSH_CONFIG" <<EOF

Host github-stories
  HostName github.com
  User git
  IdentityFile \$KEY_FILE
  IdentitiesOnly yes
EOF
  chmod 600 "\$SSH_CONFIG"
  echo "--- SSH config updated ---"
fi

# ── 3. Initialise git repo in stories dir ─────────────────────
cd "\$STORIES_DIR"
if [[ ! -d .git ]]; then
  git init
  git config user.email "backup@\$(hostname)"
  git config user.name  "Stories Backup"
fi

# Rewrite remote URL to use our named SSH host
REPO_SSH="\$(echo "$REPO_URL" | sed 's|https://github.com/|git@github-stories:|')"
if git remote get-url origin 2>/dev/null; then
  git remote set-url origin "\$REPO_SSH"
else
  git remote add origin "\$REPO_SSH"
fi

# Create .gitignore so we never accidentally commit secrets
cat > .gitignore <<'EOF'
*.tmp
EOF

echo "--- Git repo ready: \$(git remote get-url origin) ---"

# ── 4. Create the backup script ────────────────────────────────
cat > /usr/local/bin/stories-backup <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STORIES_DIR="$REMOTE_DIR/stories"
cd "\$STORIES_DIR"
git add -A
if git diff --cached --quiet; then
  exit 0   # nothing to commit
fi
git commit -m "backup: \$(date -u '+%Y-%m-%d %H:%M UTC')"
git push origin main --quiet
echo "Stories backed up at \$(date -u)"
EOF
chmod +x /usr/local/bin/stories-backup

# ── 5. Install systemd timer (runs every hour) ─────────────────
cat > /etc/systemd/system/stories-backup.service <<'EOF'
[Unit]
Description=Back up Ted & Linda's stories to GitHub
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/stories-backup
StandardOutput=journal
StandardError=journal
EOF

cat > /etc/systemd/system/stories-backup.timer <<'EOF'
[Unit]
Description=Run stories-backup every hour

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now stories-backup.timer

echo ""
echo "--- Timer installed ---"
systemctl list-timers stories-backup.timer --no-pager
REMOTE

echo ""
echo "==> Done. Next steps:"
echo ""
echo "  1. Copy the public key printed above"
echo "  2. Go to: $REPO_URL"
echo "     → Settings → Deploy keys → Add deploy key"
echo "     → Paste the key, check 'Allow write access', save"
echo ""
echo "  3. Then run the first push:"
echo "     ssh $SERVER 'cd /opt/ted-linda-stories/stories && git add -A && git commit -m \"initial backup\" && git push -u origin main'"
echo ""
echo "  After that, backups run automatically every hour."
