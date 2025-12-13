#!/bin/bash.............
# BDRman Installer Script
# Usage: curl -s https://raw.githubusercontent.com/burakdarende/bdrman/main/install.sh | bash

set -e

# Download URLs
REPO_URL="https://raw.githubusercontent.com/burakdarende/bdrman/main"
DEST_DIR="/usr/local/bin"
LIB_DEST="/usr/local/lib/bdrman"
CONFIG_DIR="/etc/bdrman"

# Determine Version
VERSION="Latest"
if [ -f "bdrman.sh" ]; then
  # Local file
  VERSION=$(grep '^VERSION=' bdrman.sh | cut -d'"' -f2)
else
  # Remote file (fast check)
  # Try to fetch version line only
  REMOTE_VER=$(curl -s "$REPO_URL/bdrman.sh" | grep '^VERSION=' | cut -d'"' -f2 || true)
  if [ -n "$REMOTE_VER" ]; then
    VERSION="$REMOTE_VER"
  fi
fi

echo "========================================="
echo "   BDRman v$VERSION - Automatic Installer"
echo "========================================="
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (use sudo)"
  exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
else
  echo "⚠️  Cannot detect OS. Assuming Debian/Ubuntu."
  OS="ubuntu"
fi

echo "📋 Detected OS: $OS"
echo ""

# Update package list
echo "📦 Updating package list..."
if command -v apt-get >/dev/null 2>&1; then
  apt-get update -qq
elif command -v yum >/dev/null 2>&1; then
  yum check-update -q || true
fi

# Install required dependencies
echo "📦 Installing required dependencies..."
REQUIRED_PACKAGES="curl wget tar rsync python3 python3-pip"

if command -v apt-get >/dev/null 2>&1; then
  apt-get install -y -qq $REQUIRED_PACKAGES
elif command -v yum >/dev/null 2>&1; then
  yum install -y -q $REQUIRED_PACKAGES
fi

# Install optional but recommended packages
echo "📦 Installing optional packages (Docker, jq, sqlite3)..."
OPTIONAL_PACKAGES="docker.io jq sqlite3 wireguard"

if command -v apt-get >/dev/null 2>&1; then
  apt-get install -y -qq $OPTIONAL_PACKAGES 2>/dev/null || echo "⚠️  Some optional packages skipped"
elif command -v yum >/dev/null 2>&1; then
  yum install -y -q docker jq sqlite wireguard-tools 2>/dev/null || echo "⚠️  Some optional packages skipped"
fi



# Create directories
mkdir -p "$CONFIG_DIR"
mkdir -p "$LIB_DEST"
mkdir -p /var/log
mkdir -p /var/backups/bdrman

# Install main script
echo ""
echo "⬇️  Installing BDRman..."
if [ -f "bdrman.sh" ] && [ -d ".git" ]; then
  echo "📂 Found local bdrman.sh (Git Repo), using it..."
  cp "bdrman.sh" "$DEST_DIR/bdrman"
else
  echo "⬇️  Downloading bdrman.sh..."
  curl -s -f -L "$REPO_URL/bdrman.sh?v=$(date +%s)" -o "$DEST_DIR/bdrman"
fi
chmod +x "$DEST_DIR/bdrman"

# Install libraries
echo "⬇️  Installing libraries..."
if [ -d "lib" ] && [ -d ".git" ]; then
  echo "📂 Found local lib directory (Git Repo), copying..."
  cp -r lib/* "$LIB_DEST/"
else
  echo "⬇️  Downloading libraries..."
  # List of libs to download
  LIBS=("core" "vpn" "caprover" "security" "backup" "system" "docker" "telegram")
  for lib in "${LIBS[@]}"; do
    curl -s -f -L "$REPO_URL/lib/$lib.sh?v=$(date +%s)" -o "$LIB_DEST/$lib.sh"
    echo "   - $lib.sh installed"
  done
fi

# Install Telegram Bot Script
echo "⬇️  Installing Telegram Bot..."
# Stop service if running to allow file update
systemctl stop bdrman-telegram 2>/dev/null || true

if [ -f "telegram_bot.py" ] && [ -d ".git" ]; then
  echo "📂 Found local telegram_bot.py (Git Repo), using it..."
  cp "telegram_bot.py" "$CONFIG_DIR/telegram_bot.py"
else
  curl -s -f -L "$REPO_URL/telegram_bot.py?v=$(date +%s)" -o "$CONFIG_DIR/telegram_bot.py"
fi
chmod +x "$CONFIG_DIR/telegram_bot.py"

# Install Python Dependencies
echo "🐍 Installing Python dependencies..."
# Try to install globally (might require --break-system-packages on newer Debian/Ubuntu)
pip3 install --upgrade pip --break-system-packages 2>/dev/null || pip3 install --upgrade pip
pip3 install python-telegram-bot psutil requests --break-system-packages 2>/dev/null || pip3 install python-telegram-bot psutil requests

# Setup Systemd Service
echo "⚙️  Configuring systemd service..."
cat > /etc/systemd/system/bdrman-telegram.service <<EOF
[Unit]
Description=BDRman Telegram Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$CONFIG_DIR
ExecStart=/usr/bin/python3 $CONFIG_DIR/telegram_bot.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
# Don't start it yet, user needs to configure it first (token)
# But we can enable it
systemctl enable bdrman-telegram.service

# Restart service if config exists (Update scenario)
if [ -f "$CONFIG_DIR/telegram.conf" ]; then
  echo "🔄 Restarting Telegram Bot..."
  systemctl restart bdrman-telegram
fi

# Set permissions
chmod 700 "$CONFIG_DIR"
chmod 600 "$CONFIG_DIR"/*.conf 2>/dev/null || true
touch /var/log/bdrman.log
chmod 640 /var/log/bdrman.log

# Setup Log Rotation
if [ -f "$LIB_DEST/core.sh" ]; then
  source "$LIB_DEST/core.sh"
fi

if [ -f "$LIB_DEST/system.sh" ]; then
  source "$LIB_DEST/system.sh"
  system_setup_logrotate
fi

echo ""
echo "========================================="
echo "   ✅ Installation Complete!"
echo "========================================="
echo ""
echo "📝 Installed components:"
echo "   • Main script:     $DEST_DIR/bdrman"
echo "   • Libraries:       $LIB_DEST/"
echo "   • Bot Script:      $CONFIG_DIR/telegram_bot.py"
echo "   • Config dir:      $CONFIG_DIR"
echo ""
echo "🚀 Quick start:"
echo "   bdrman              # Interactive menu"
echo "   bdrman telegram     # Manage Telegram Bot"
echo ""
echo "🤖 To activate the bot:"
echo "   Run 'bdrman' -> Option 9 -> Option 1 (Initial Setup)"
echo ""
