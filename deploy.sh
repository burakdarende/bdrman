#!/bin/bash
# BDRman v3.1 Deployment Script
# Run this on your server to install all files correctly

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================"
echo "  BDRman v3.1 Deployment"
echo "======================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ This script must be run as root${NC}"
  echo "   Use: sudo bash deploy.sh"
  exit 1
fi

# Check if files exist in current directory
if [ ! -f "bdrman.sh" ]; then
  echo -e "${RED}❌ bdrman.sh not found in current directory${NC}"
  echo "   Please run this script from the bdrman repository folder"
  exit 1
fi

echo -e "${YELLOW}📋 Files to deploy:${NC}"
echo "   • bdrman.sh → /usr/local/bin/bdrman"
echo "   • config.conf.example → /etc/bdrman/config.conf"
echo "   • logrotate.bdrman → /etc/logrotate.d/bdrman"
echo "   • validate.sh → /usr/local/bin/bdrman-validate"
echo ""

read -rp "Continue with deployment? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
  echo "Deployment cancelled."
  exit 0
fi

echo ""
echo -e "${BLUE}🚀 Starting deployment...${NC}"
echo ""

# 1. Install main script
echo -n "[1/5] Installing main script... "
cp bdrman.sh /usr/local/bin/bdrman
chmod 755 /usr/local/bin/bdrman
chown root:root /usr/local/bin/bdrman
echo -e "${GREEN}✓${NC}"

# 2. Create /etc/bdrman directory and install config
echo -n "[2/5] Installing configuration... "
mkdir -p /etc/bdrman
if [ -f /etc/bdrman/config.conf ]; then
  echo -e "${YELLOW}⚠${NC}"
  echo "      Config already exists at /etc/bdrman/config.conf"
  read -rp "      Overwrite? (yes/no): " overwrite
  if [ "$overwrite" = "yes" ]; then
    cp config.conf.example /etc/bdrman/config.conf
    echo -e "      ${GREEN}✓ Overwritten${NC}"
  else
    cp config.conf.example /etc/bdrman/config.conf.new
    echo -e "      ${YELLOW}✓ Saved as config.conf.new${NC}"
  fi
else
  cp config.conf.example /etc/bdrman/config.conf
  echo -e "${GREEN}✓${NC}"
fi
chmod 600 /etc/bdrman/config.conf* 2>/dev/null || true
chown root:root /etc/bdrman/config.conf* 2>/dev/null || true

# 3. Install logrotate config
echo -n "[3/5] Installing logrotate config... "
cp logrotate.bdrman /etc/logrotate.d/bdrman
chmod 644 /etc/logrotate.d/bdrman
chown root:root /etc/logrotate.d/bdrman
echo -e "${GREEN}✓${NC}"

# 4. Install validation script
echo -n "[4/5] Installing validation script... "
cp validate.sh /usr/local/bin/bdrman-validate
chmod 755 /usr/local/bin/bdrman-validate
chown root:root /usr/local/bin/bdrman-validate
echo -e "${GREEN}✓${NC}"

# 5. Create required directories
echo -n "[5/5] Creating required directories... "
mkdir -p /var/log 2>/dev/null || true
mkdir -p /var/backups/bdrman 2>/dev/null || true
mkdir -p /var/lock 2>/dev/null || true
touch /var/log/bdrman.log 2>/dev/null || true
chmod 640 /var/log/bdrman.log 2>/dev/null || true
echo -e "${GREEN}✓${NC}"

echo ""
echo -e "${GREEN}======================================"
echo "  ✅ Deployment Complete!"
echo "======================================${NC}"
echo ""

# Show installed files
echo -e "${BLUE}📁 Installed files:${NC}"
echo ""
echo "Main script:"
echo "  /usr/local/bin/bdrman ($(stat -c %a /usr/local/bin/bdrman 2>/dev/null || stat -f %Lp /usr/local/bin/bdrman))"
echo ""
echo "Configuration:"
echo "  /etc/bdrman/config.conf ($(stat -c %a /etc/bdrman/config.conf 2>/dev/null || stat -f %Lp /etc/bdrman/config.conf))"
[ -f /etc/bdrman/config.conf.new ] && echo "  /etc/bdrman/config.conf.new (backup)"
echo ""
echo "Logrotate:"
echo "  /etc/logrotate.d/bdrman ($(stat -c %a /etc/logrotate.d/bdrman 2>/dev/null || stat -f %Lp /etc/logrotate.d/bdrman))"
echo ""
echo "Validation:"
echo "  /usr/local/bin/bdrman-validate ($(stat -c %a /usr/local/bin/bdrman-validate 2>/dev/null || stat -f %Lp /usr/local/bin/bdrman-validate))"
echo ""
echo "Directories:"
echo "  /etc/bdrman/"
echo "  /var/log/"
echo "  /var/backups/bdrman/"
echo "  /var/lock/"
echo ""

# Verify installation
echo -e "${BLUE}🔍 Verifying installation...${NC}"
echo ""

if command -v bdrman >/dev/null 2>&1; then
  echo -e "${GREEN}✓${NC} bdrman command available"
  VERSION=$(bdrman --version 2>/dev/null | head -1)
  echo "  $VERSION"
else
  echo -e "${RED}✗${NC} bdrman command not found in PATH"
fi

if command -v bdrman-validate >/dev/null 2>&1; then
  echo -e "${GREEN}✓${NC} bdrman-validate command available"
else
  echo -e "${RED}✗${NC} bdrman-validate command not found in PATH"
fi

echo ""
echo -e "${YELLOW}📝 Next steps:${NC}"
echo ""
echo "1. Edit configuration (optional):"
echo "   sudo nano /etc/bdrman/config.conf"
echo ""
echo "2. Run validation tests:"
echo "   sudo bdrman-validate"
echo ""
echo "3. Start bdrman:"
echo "   sudo bdrman"
echo ""
echo "4. Setup Telegram bot (recommended):"
echo "   sudo bdrman"
echo "   → 11) Telegram Bot → 1) Setup Telegram"
echo ""
echo "5. Enable security monitoring (recommended):"
echo "   sudo bdrman"
echo "   → 7) Security & Hardening → 8) Setup Advanced Monitoring"
echo ""
echo -e "${GREEN}🎉 Deployment successful!${NC}"
echo ""
