#!/bin/bash
# BDRman Installer Script
# Usage: curl -s https://raw.githubusercontent.com/burakdarende/bdrman/main/install.sh | bash
# Or with token: curl -H "Authorization: token YOUR_TOKEN" ... | bash

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

# Check if we have a token in env or args (optional logic, but simple curl is safer)
# We assume the user runs the curl command with the token header if needed.
# If this script is run locally, we just download.

if curl -s -f -L "$REPO_URL" -o "$DEST"; then
  echo "✅ Download successful"
else
  # Try with token if provided as argument
  if [ -n "$1" ]; then
    echo "Trying with provided token..."
    if curl -H "Authorization: token $1" -s -f -L "$REPO_URL" -o "$DEST"; then
      echo "✅ Download successful (with token)"
    else
      echo "❌ Download failed. Check your token or internet connection."
      exit 1
    fi
  else
    echo "❌ Download failed. If this is a private repo, use:"
    echo 'curl -H "Authorization: token YOUR_TOKEN" -L ...'
    exit 1
  fi
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
