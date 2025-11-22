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
echo "⬇️  Downloading bdrman.sh..."
if curl -s -f -L "$REPO_URL/bdrman.sh" -o "$DEST_DIR/bdrman"; then
  echo "✅ bdrman.sh downloaded"
else
  echo "❌ Download failed. Check your internet connection."
  exit 1
fi

# Download web dashboard
echo "⬇️  Downloading web_dashboard.py..."
mkdir -p "$WEB_DEST"
if curl -s -f -L "$REPO_URL/web_dashboard.py" -o "$WEB_DEST/web_dashboard.py"; then
  echo "✅ web_dashboard.py downloaded"
else
  echo "⚠️  Web dashboard download failed (optional)"
fi

# Set permissions
echo ""
echo "🔧 Setting permissions..."
chmod +x "$DEST_DIR/bdrman"
chown root:root "$DEST_DIR/bdrman"

if [ -f "$WEB_DEST/web_dashboard.py" ]; then
  chmod +x "$WEB_DEST/web_dashboard.py"
  chown root:root "$WEB_DEST/web_dashboard.py"
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

# Setup web dashboard (if downloaded)
if [ -f "$WEB_DEST/web_dashboard.py" ]; then
  echo ""
  echo "🌐 Setting up web dashboard..."
  
  # Create virtual environment
  python3 -m venv "$WEB_DEST/venv"
  
  if [ $? -eq 0 ]; then
    echo "✅ Virtual environment created"
    
    # Install Flask
    echo "📦 Installing Flask..."
    "$WEB_DEST/venv/bin/pip" install --quiet --upgrade pip
    "$WEB_DEST/venv/bin/pip" install --quiet flask
    
    if [ $? -eq 0 ]; then
      # Verify Flask
      if "$WEB_DEST/venv/bin/python3" -c "import flask" 2>/dev/null; then
        echo "✅ Flask installed and verified"
      else
        echo "⚠️  Flask verification failed"
      fi
    else
      echo "⚠️  Flask installation failed"
    fi
  else
    echo "⚠️  Virtual environment creation failed"
  fi
fi

# Installation complete
echo ""
echo "========================================="
echo "   ✅ Installation Complete!"
echo "========================================="
echo ""
echo "📝 Installed components:"
echo "   • Main script:     $DEST_DIR/bdrman"
echo "   • Web dashboard:   $WEB_DEST/web_dashboard.py"
echo "   • Config dir:      /etc/bdrman"
echo "   • Backup dir:      /var/backups/bdrman"
echo "   • Log file:        /var/log/bdrman.log"
echo ""
echo "🚀 Quick start:"
echo "   bdrman              # Interactive menu"
echo "   bdrman status       # System status"
echo "   bdrman web start    # Start web dashboard"
echo "   bdrman --help       # Show all commands"
echo ""
echo "🌐 Web dashboard will be available at:"
echo "   http://$(hostname -I | awk '{print $1}'):8443"
echo ""
echo "📖 For more info: https://github.com/burakdarende/bdrman"
echo ""
