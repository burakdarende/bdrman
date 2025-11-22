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

# Determine download URL
REPO_URL="https://raw.githubusercontent.com/burakdarende/bdrman/main/bdrman.sh"
DEST="/usr/local/bin/bdrman"

echo "⬇️  Downloading bdrman.sh..."

if curl -s -f -L "$REPO_URL" -o "$DEST"; then
  echo "✅ Download successful"
else
  echo "❌ Download failed. Please check your internet connection."
  exit 1
fi

echo "🔧 Setting permissions..."
chmod +x "$DEST"
chown root:root "$DEST"

echo "✅ Installation complete!"
echo ""
echo "Run 'bdrman' to start."
echo ""
# Optional: Run immediately
# bdrman
