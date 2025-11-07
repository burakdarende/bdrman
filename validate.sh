#!/bin/bash
# BDRman v3.1 Validation Script
# Run this script to verify all improvements are working correctly

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================"
echo "  BDRman v3.1 Validation Script"
echo "======================================"
echo ""

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Test function
run_test(){
  local test_name="$1"
  local test_command="$2"
  local expected_pattern="$3"
  
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  echo -n "[$TESTS_TOTAL] $test_name... "
  
  if eval "$test_command" | grep -q "$expected_pattern"; then
    echo -e "${GREEN}✓ PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  else
    echo -e "${RED}✗ FAIL${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
}

# Critical tests
echo "=== CRITICAL TESTS ==="
echo ""

# Test 1: Line endings
echo -n "[1] Line ending check (CRLF → LF)... "
if file /usr/local/bin/bdrman | grep -q "CRLF"; then
  echo -e "${RED}✗ FAIL - File still has CRLF${NC}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
elif file /usr/local/bin/bdrman | grep -q "ASCII text executable"; then
  echo -e "${GREEN}✓ PASS${NC}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${YELLOW}⚠ UNKNOWN - Cannot verify${NC}"
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Test 2: Syntax check
echo -n "[2] Bash syntax validation... "
if bash -n /usr/local/bin/bdrman 2>/dev/null; then
  echo -e "${GREEN}✓ PASS${NC}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}✗ FAIL - Syntax errors found${NC}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Test 3: Execute permission
echo -n "[3] Execute permission check... "
if [ -x /usr/local/bin/bdrman ]; then
  echo -e "${GREEN}✓ PASS${NC}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}✗ FAIL - Not executable${NC}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

echo ""
echo "=== FEATURE TESTS ==="
echo ""

# Test 4: Config file exists
echo -n "[4] Config file template... "
if [ -f config.conf.example ]; then
  echo -e "${GREEN}✓ PASS${NC}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${YELLOW}⚠ WARNING - config.conf.example not found${NC}"
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Test 5: Logrotate config
echo -n "[5] Logrotate configuration... "
if [ -f logrotate.bdrman ]; then
  echo -e "${GREEN}✓ PASS${NC}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${YELLOW}⚠ WARNING - logrotate.bdrman not found${NC}"
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Test 6: CLI help
echo -n "[6] CLI --help argument... "
if bdrman --help 2>/dev/null | grep -q "Usage:"; then
  echo -e "${GREEN}✓ PASS${NC}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}✗ FAIL${NC}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Test 7: CLI version
echo -n "[7] CLI --version argument... "
if bdrman --version 2>/dev/null | grep -q "3.1"; then
  echo -e "${GREEN}✓ PASS${NC}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}✗ FAIL${NC}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Test 8: Dependency checker
echo -n "[8] Dependency checker... "
if bdrman --check-deps 2>/dev/null | grep -q "docker"; then
  echo -e "${GREEN}✓ PASS${NC}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}✗ FAIL${NC}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

echo ""
echo "=== SECURITY TESTS ==="
echo ""

# Test 9: Telegram config permissions (if exists)
echo -n "[9] Telegram config security... "
if [ -f /etc/bdrman/telegram.conf ]; then
  PERMS=$(stat -c %a /etc/bdrman/telegram.conf 2>/dev/null || stat -f %A /etc/bdrman/telegram.conf 2>/dev/null)
  if [ "$PERMS" = "600" ]; then
    echo -e "${GREEN}✓ PASS (chmod 600)${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "${RED}✗ FAIL (chmod $PERMS, should be 600)${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
else
  echo -e "${YELLOW}⚠ SKIP (telegram not configured)${NC}"
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Test 10: Lock file mechanism
echo -n "[10] Lock file directory... "
if [ -d /var/lock ]; then
  echo -e "${GREEN}✓ PASS${NC}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}✗ FAIL - /var/lock missing${NC}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Test 11: Log file writable
echo -n "[11] Log file writable... "
if touch /var/log/bdrman.log 2>/dev/null; then
  echo -e "${GREEN}✓ PASS${NC}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}✗ FAIL - Cannot write to /var/log/bdrman.log${NC}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Test 12: Backup directory
echo -n "[12] Backup directory... "
if mkdir -p /var/backups/bdrman 2>/dev/null; then
  echo -e "${GREEN}✓ PASS${NC}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}✗ FAIL${NC}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

echo ""
echo "=== CODE QUALITY TESTS ==="
echo ""

# Test 13: Shellcheck (if available)
echo -n "[13] ShellCheck analysis... "
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning /usr/local/bin/bdrman 2>/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "${YELLOW}⚠ WARNINGS FOUND (non-critical)${NC}"
  fi
else
  echo -e "${YELLOW}⚠ SKIP (shellcheck not installed)${NC}"
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Test 14: Function definitions
echo -n "[14] Core functions present... "
if grep -q "acquire_lock()" /usr/local/bin/bdrman && \
   grep -q "check_dependencies()" /usr/local/bin/bdrman && \
   grep -q "load_config()" /usr/local/bin/bdrman; then
  echo -e "${GREEN}✓ PASS${NC}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}✗ FAIL - Missing core functions${NC}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Test 15: Monitoring script
echo -n "[15] Security monitor script... "
if [ -f /etc/bdrman/security_monitor.sh ]; then
  if grep -q "MONITORING_INTERVAL" /etc/bdrman/security_monitor.sh; then
    echo -e "${GREEN}✓ PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "${YELLOW}⚠ WARNING - Old version detected${NC}"
  fi
else
  echo -e "${YELLOW}⚠ SKIP (monitoring not enabled)${NC}"
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Final summary
echo ""
echo "======================================"
echo "  VALIDATION SUMMARY"
echo "======================================"
echo ""
echo "Total tests: $TESTS_TOTAL"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
  echo -e "${GREEN}✅ ALL TESTS PASSED!${NC}"
  echo ""
  echo "BDRman v3.1 is ready for production use."
  exit 0
else
  echo -e "${RED}❌ SOME TESTS FAILED${NC}"
  echo ""
  echo "Please review the failed tests above and fix issues."
  echo "Common fixes:"
  echo "  • CRLF errors: sudo sed -i 's/\r$//' /usr/local/bin/bdrman"
  echo "  • Permissions: sudo chmod +x /usr/local/bin/bdrman"
  echo "  • Telegram config: sudo chmod 600 /etc/bdrman/telegram.conf"
  exit 1
fi
