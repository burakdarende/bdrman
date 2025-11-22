#!/bin/bash
# BDRman Installer Script
# Usage: curl -s https://raw.githubusercontent.com/burakdarende/bdrman/main/install.sh | bash

set -e

echo "=== BDRman Installer ==="
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root"
  exit 1
fi

# Determine download URLs
REPO_URL="https://raw.githubusercontent.com/burakdarende/bdrman/main"
DEST_DIR="/usr/local/bin"
WEB_DEST="/opt/bdrman"

echo "⬇️  Downloading bdrman.sh..."
if curl -s -f -L "$REPO_URL/bdrman.sh" -o "$DEST_DIR/bdrman"; then
  echo "✅ bdrman.sh downloaded"
else
  echo "❌ Download failed. Check your internet connection."
  exit 1
fi

echo "⬇️  Downloading web_dashboard.py..."
mkdir -p "$WEB_DEST"
if curl -s -f -L "$REPO_URL/web_dashboard.py" -o "$WEB_DEST/web_dashboard.py"; then
  echo "✅ web_dashboard.py downloaded"
else
  echo "⚠️  Web dashboard download failed (optional)"
fi

echo "🔧 Setting permissions..."
chmod +x "$DEST_DIR/bdrman"
chown root:root "$DEST_DIR/bdrman"

if [ -f "$WEB_DEST/web_dashboard.py" ]; then
  chmod +x "$WEB_DEST/web_dashboard.py"
  chown root:root "$WEB_DEST/web_dashboard.py"
fi

echo "✅ Installation complete!"
echo ""
echo "📝 Installed files:"
echo "   • Main script: $DEST_DIR/bdrman"
echo "   • Web dashboard: $WEB_DEST/web_dashboard.py"
echo ""
echo "🚀 Run 'bdrman' to start."
echo "🌐 Web dashboard: python3 $WEB_DEST/web_dashboard.py"
echo ""
