#!/bin/bash
# BDRman Installer Script
# Usage: curl -s https://raw.githubusercontent.com/burakdarende/bdrman/main/install.sh | bash

set -e

echo "========================================="
echo "   BDRman v4.0 - Automatic Installer"
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
REQUIRED_PACKAGES="curl wget tar rsync"

if command -v apt-get >/dev/null 2>&1; then
  apt-get install -y -qq $REQUIRED_PACKAGES
elif command -v yum >/dev/null 2>&1; then
  yum install -y -q $REQUIRED_PACKAGES
fi

# Install Python3 and venv
echo "🐍 Installing Python3 and dependencies..."
if command -v apt-get >/dev/null 2>&1; then
  apt-get install -y -qq python3 python3-pip python3-venv
elif command -v yum >/dev/null 2>&1; then
  yum install -y -q python3 python3-pip
fi

# Verify Python installation
if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ Python3 installation failed"
  exit 1
fi

echo "✅ Python3 installed: $(python3 --version)"

# Install optional but recommended packages
echo "📦 Installing optional packages (Docker, jq, sqlite3)..."
OPTIONAL_PACKAGES="docker.io jq sqlite3"

if command -v apt-get >/dev/null 2>&1; then
  apt-get install -y -qq $OPTIONAL_PACKAGES 2>/dev/null || echo "⚠️  Some optional packages skipped"
elif command -v yum >/dev/null 2>&1; then
  yum install -y -q docker jq sqlite 2>/dev/null || echo "⚠️  Some optional packages skipped"
fi

# Download URLs
REPO_URL="https://raw.githubusercontent.com/burakdarende/bdrman/main"
DEST_DIR="/usr/local/bin"
WEB_DEST="/opt/bdrman"

# Download main script
echo ""
if [ -f "bdrman.sh" ]; then
  echo "📂 Found local bdrman.sh, using it..."
  cp "bdrman.sh" "$DEST_DIR/bdrman"
  echo "✅ bdrman.sh installed from local source"
else
  echo "⬇️  Downloading bdrman.sh..."
  if curl -s -f -L "$REPO_URL/bdrman.sh" -o "$DEST_DIR/bdrman"; then
    echo "✅ bdrman.sh downloaded"
  else
    echo "❌ Download failed. Check your internet connection."
    exit 1
  fi
fi

# Download telegram_bot.py
echo "⬇️  Installing telegram_bot.py..."
if [ -f "telegram_bot.py" ]; then
  echo "📂 Found local telegram_bot.py, using it..."
  cp "telegram_bot.py" "$DEST_DIR/telegram_bot.py"
  echo "✅ telegram_bot.py installed from local source"
else
  if curl -s -f -L "$REPO_URL/telegram_bot.py" -o "$DEST_DIR/telegram_bot.py"; then
    echo "✅ telegram_bot.py downloaded"
  else
    echo "⚠️  Telegram bot download failed"
  fi
fi

# Install lib modules
echo "⬇️  Installing libraries..."
mkdir -p "$DEST_DIR/lib"
if [ -d "lib" ]; then
  cp -r lib/* "$DEST_DIR/lib/"
  echo "✅ Libraries installed from local source"
else
  # If remote install, we would need to download lib files individually or as tarball
  # For now assuming single file or local install
  if curl -s -f -L "$REPO_URL/lib/telegram.sh" -o "$DEST_DIR/lib/telegram.sh"; then
    echo "✅ lib/telegram.sh downloaded"
  fi
fi

# Set permissions
echo ""
echo "🔧 Setting permissions..."
chmod +x "$DEST_DIR/bdrman"
chown root:root "$DEST_DIR/bdrman"

if [ -f "$DEST_DIR/telegram_bot.py" ]; then
  chmod +x "$DEST_DIR/telegram_bot.py"
  chown root:root "$DEST_DIR/telegram_bot.py"
fi

# Create required directories
echo "📁 Creating required directories..."
mkdir -p /etc/bdrman
mkdir -p /var/backups/bdrman
mkdir -p /var/log
chmod 700 /etc/bdrman
chmod 700 /var/backups/bdrman

# Create log file
touch /var/log/bdrman.log
chmod 640 /var/log/bdrman.log

# Setup Python Environment for Telegram Bot
echo ""
echo "🐍 Setting up Python environment for Telegram Bot..."

# Install Python3 and venv if missing
if ! command -v python3 &> /dev/null; then
  echo "Installing Python3..."
  if [ -f /etc/debian_version ]; then
    apt-get update && apt-get install -y python3 python3-pip python3-venv
  elif [ -f /etc/redhat-release ]; then
    yum install -y python3 python3-pip
  fi
fi

# Create virtual environment
VENV_DIR="/opt/bdrman/venv"
mkdir -p "/opt/bdrman"
python3 -m venv "$VENV_DIR"

if [ $? -eq 0 ]; then
  echo "✅ Virtual environment created at $VENV_DIR"
  
  # Install Dependencies
  echo "📦 Installing Python dependencies..."
  "$VENV_DIR/bin/pip" install --quiet --upgrade pip
  "$VENV_DIR/bin/pip" install --quiet python-telegram-bot psutil requests
  
  if [ $? -eq 0 ]; then
    echo "✅ Dependencies installed (python-telegram-bot, psutil)"
  else
    echo "❌ Failed to install Python dependencies"
  fi
else
  echo "❌ Failed to create virtual environment"
fi

# Create Systemd Service for Telegram Bot
echo ""
echo "⚙️  Creating systemd service..."
cat > /etc/systemd/system/bdrman-telegram.service <<EOF
[Unit]
Description=BDRman Telegram Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/bdrman
Environment="PATH=$VENV_DIR/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=$VENV_DIR/bin/python3 /usr/local/bin/telegram_bot.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
echo "✅ Service created: bdrman-telegram.service"
    
# Installation complete
echo ""
echo "========================================="
echo "   ✅ Installation Complete!"
echo "========================================="
echo ""
echo "📝 Installed components:"
echo "   • Main script:     $DEST_DIR/bdrman"
echo "   • Telegram Bot:    $DEST_DIR/telegram_bot.py"
echo "   • Config dir:      /etc/bdrman"
echo "   • Backup dir:      /var/backups/bdrman"
echo "   • Log file:        /var/log/bdrman.log"
echo ""
echo "🚀 Quick start:"
echo "   bdrman              # Interactive menu"
echo "   bdrman status       # System status"
echo "   bdrman telegram     # Manage Telegram Bot"
echo "   bdrman --help       # Show all commands"
echo ""
echo "🤖 To activate the bot:"
echo "   Run 'bdrman telegram setup' to enter your Token and Chat ID."
echo ""
echo "📖 For more info: https://github.com/burakdarende/bdrman"
echo ""
