# BDRman v3.1 - Professional Server Management Tool

[![Version](https://img.shields.io/badge/version-3.1-blue.svg)](https://github.com/burakdarende/bdrman)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-5.0%2B-orange.svg)](https://www.gnu.org/software/bash/)

A comprehensive, secure, and production-ready server management panel for Linux systems with CapRover integration, real-time security monitoring, and Telegram alerting.

## 🚀 Features

### Core Management

- **CapRover Integration**: Backup, restore, and manage Docker volumes
- **System Monitoring**: Real-time CPU, memory, disk, and network monitoring
- **Backup System**: Atomic backups with `.partial` files, remote backup support
- **Security Suite**: 8 pre-configured security tools (Fail2Ban, ClamAV, RKHunter, etc.)
- **Telegram Bot**: Remote management and real-time alerts
- **WireGuard VPN**: Easy setup and management

### Security Features (v3.0+)

- **Real-time Threat Detection**: DDoS, brute force, resource exhaustion
- **Per-Alert Cooldown**: Prevents Telegram spam (5min default)
- **Configurable Thresholds**: CPU, memory, disk, connection limits
- **Automatic Incident Response**: Recommendations for detected threats
- **Secure Configuration**: Encrypted Telegram tokens, file permissions validation

### Operational Excellence (v3.1+)

- **Idempotent Operations**: Safe to run repeatedly without side effects
- **Atomic Backups**: No corrupted files with `.partial` → final rename
- **Concurrency Control**: `flock`-based locking prevents simultaneous operations
- **Input Sanitization**: Protection against injection in remote backup paths
- **Configurable Timeouts**: All blocking operations have limits
- **CLI Arguments**: `--help`, `--auto-backup`, `--dry-run`, `--check-deps`
- **Automatic Log Rotation**: Weekly rotation, 4-week retention

## 📋 Requirements

### Required

- Ubuntu 20.04+ / Debian 11+ (systemd-based)
- Root access
- Bash 5.0+
- Core utilities: `docker`, `tar`, `rsync`, `curl`, `systemctl`

### Optional

- `jq` - JSON parsing for enhanced features
- `certbot` - SSL certificate management
- `wg-quick` - WireGuard VPN
- `fail2ban` - Brute force protection

## 🔧 Installation

### Quick Install

```bash
# Download script
curl -fsSL https://raw.githubusercontent.com/burakdarende/bdrman/main/bdrman.sh -o /usr/local/bin/bdrman

# Make executable
chmod +x /usr/local/bin/bdrman

# Check dependencies
bdrman --check-deps

# Run
bdrman
```

### Full Setup

```bash
# 1. Install script
sudo curl -fsSL https://raw.githubusercontent.com/burakdarende/bdrman/main/bdrman.sh -o /usr/local/bin/bdrman
sudo chmod +x /usr/local/bin/bdrman

# 2. Copy example config
sudo cp config.conf.example /etc/bdrman/config.conf
sudo chmod 600 /etc/bdrman/config.conf

# 3. Install logrotate config
sudo cp logrotate.bdrman /etc/logrotate.d/bdrman

# 4. Customize config (optional)
sudo nano /etc/bdrman/config.conf

# 5. Run initial check
sudo bdrman --check-deps
```

## 📖 Usage

### Interactive Mode

```bash
sudo bdrman
```

### CLI Mode

```bash
# Create automatic backup
sudo bdrman --auto-backup

# Check dependencies
sudo bdrman --check-deps

# Dry-run mode (test without changes)
sudo bdrman --dry-run

# Show help
bdrman --help

# Show version
bdrman --version
```

### Configuration

Edit `/etc/bdrman/config.conf`:

```bash
# Monitoring frequency (30s recommended)
MONITORING_INTERVAL=30

# Alert cooldown (300s = 5min)
ALERT_COOLDOWN=300

# DDoS threshold (connections per IP)
DDOS_THRESHOLD=50

# Backup retention (days)
BACKUP_RETENTION_DAYS=7
```

## 🛡️ Security Features

### Security Monitoring Setup

```bash
# 1. Configure Telegram bot
sudo bdrman
→ 11) Telegram Bot
→ 1) Setup Telegram

# 2. Install security tools
sudo bdrman
→ 7) Security & Hardening
→ 5) Install Security Tools (All)

# 3. Enable monitoring
sudo bdrman
→ 7) Security & Hardening
→ 8) Setup Advanced Monitoring
```

### Alert Examples

**DDoS Detection:**

```
🚨 DDOS ALERT DETECTED

⚠️ Threat Level: HIGH
📊 Type: Connection Flood
🔍 Details:
   • Suspicious IPs: 3
   • Top Offender: `192.168.1.100`
   • Connections: 156
   • Threshold: 50

💡 Recommended Actions:
   1. /ddos_enable
   2. /caprover_protect
   3. /block 192.168.1.100
```

**High CPU Alert:**

```
⚠️ HIGH CPU ALERT

📊 CPU Usage: 95% (threshold: 90%)
🔝 Top Process: `node`

💡 Actions:
   /top - View all processes
   /docker - Check containers
```

## 🧪 Testing & Validation

### Acceptance Tests

Run these tests to verify all v3.1 improvements:

```bash
# 1. Line ending test (CRITICAL)
file /usr/local/bin/bdrman
# Expected: "POSIX shell script, ASCII text executable"
# Should NOT show "CRLF" or "with CRLF line terminators"

# 2. Dependency check
sudo bdrman --check-deps
# Should list all required/optional tools

# 3. Config loading
sudo bdrman --debug
# Should show "✅ Loaded config from /etc/bdrman/config.conf"

# 4. Lock mechanism test
# Terminal 1:
sudo bdrman
# Select 2) CapRover Backups → 1) Backup All Volumes

# Terminal 2 (while backup running):
sudo bdrman
# Select 2) CapRover Backups → 1) Backup All Volumes
# Expected: "❌ Another bdrman operation is running."

# 5. Atomic backup test
sudo bdrman --auto-backup
ls -la /var/backups/bdrman/
# Should NOT show any .partial files
# Only final .tar.gz files

# 6. Telegram alert cooldown test
# Trigger high CPU (e.g., stress test)
# Check logs:
tail -f /var/log/bdrman_security_alerts.log
# Alerts should be separated by ALERT_COOLDOWN seconds (default 300s)

# 7. Safe backup_remote test
sudo bdrman
# Select 3) Backups → 5) Send to Remote
# Try: remote="../etc", path="../../etc"
# Expected: "❌ Invalid path. Avoid special characters and .."

# 8. Idempotent service control
sudo systemctl start nginx
sudo bdrman
# Select 10) Incident Response → 3) Exit Emergency Mode
# Expected: "ℹ️  Nginx already running" (not restarted)

# 9. Curl timeout test
# Block Telegram API:
sudo iptables -A OUTPUT -d 149.154.160.0/20 -j DROP

# Try sending alert:
sudo bdrman-telegram "Test"
# Expected: "Failed to send Telegram message" (after 10s timeout)

# Restore:
sudo iptables -D OUTPUT -d 149.154.160.0/20 -j DROP

# 10. Logrotate test
sudo logrotate -d /etc/logrotate.d/bdrman
# Should show rotation plan without errors
```

### Unit Tests Checklist

- [x] CRLF → LF conversion
- [x] Config file loading
- [x] Dependency checker
- [x] Lock acquisition/release
- [x] Atomic backup creation
- [x] Per-alert cooldown
- [x] Input sanitization
- [x] Curl timeout handling
- [x] Idempotent service control
- [x] CLI argument parsing

## 📊 Performance

### Monitoring Intervals

| Component           | Old | New (v3.1)   | Reason                               |
| ------------------- | --- | ------------ | ------------------------------------ |
| Security check loop | 2s  | 30s          | Prevent Telegram rate-limiting       |
| Alert cooldown      | 2s  | 300s (5min)  | Reduce spam, per-alert type tracking |
| Backup timeout      | ∞   | 600s (10min) | Prevent hanging operations           |
| Curl timeout        | ∞   | 10s          | Prevent network hangs                |

### Resource Usage

- **Idle**: ~5MB RAM, <0.1% CPU
- **Monitoring Active**: ~15MB RAM, ~1% CPU
- **During Backup**: Depends on data size, CPU-bound (tar compression)

## 🔐 Security Best Practices

1. **Telegram Token Protection**

   ```bash
   sudo chmod 600 /etc/bdrman/telegram.conf
   sudo chown root:root /etc/bdrman/telegram.conf
   ```

2. **Lock File Permissions**

   ```bash
   sudo chmod 644 /var/lock/bdrman.lock
   ```

3. **Log File Security**

   ```bash
   sudo chmod 640 /var/log/bdrman.log
   sudo chmod 640 /var/log/bdrman_security_alerts.log
   ```

4. **Firewall Configuration**

   - Keep SSH port (22) open always
   - Restrict CapRover (3000) to trusted IPs if possible
   - Enable UFW: `sudo ufw enable`

5. **Regular Updates**

   ```bash
   # Update bdrman
   sudo curl -fsSL https://raw.githubusercontent.com/burakdarende/bdrman/main/bdrman.sh -o /usr/local/bin/bdrman

   # Update security tools
   sudo bdrman
   → 7) Security & Hardening → 7) Update Security Tools
   ```

## 🐛 Troubleshooting

### Script Won't Execute

```bash
# Check line endings
file /usr/local/bin/bdrman

# Fix if shows CRLF:
sudo sed -i 's/\r$//' /usr/local/bin/bdrman

# Verify:
bash -n /usr/local/bin/bdrman
```

### Telegram Alerts Not Working

```bash
# Check config
sudo cat /etc/bdrman/telegram.conf

# Check permissions
ls -la /etc/bdrman/telegram.conf
# Should show: -rw------- 1 root root

# Test manually
sudo bdrman-telegram "Test message"

# Check monitoring service
sudo systemctl status bdrman-security-monitor
sudo journalctl -u bdrman-security-monitor -f
```

### Lock File Issues

```bash
# Check if lock is stale
sudo cat /var/lock/bdrman.lock
# Shows: PID:operation:timestamp

# If process doesn't exist, remove lock
sudo rm /var/lock/bdrman.lock
```

### High False Positive Alerts

```bash
# Edit config
sudo nano /etc/bdrman/config.conf

# Increase thresholds:
DDOS_THRESHOLD=100          # Was 50
CPU_ALERT_THRESHOLD=95      # Was 90
ALERT_COOLDOWN=600          # 10 minutes instead of 5

# Restart monitoring
sudo systemctl restart bdrman-security-monitor
```

## 📚 Additional Resources

- [Security Features Documentation](SECURITY_FEATURES_V3.md)
- [Telegram Setup Guide](TELEGRAM_FIX_GUIDE.md)
- [Changelog](CHANGELOG.md)

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Test thoroughly (use acceptance tests above)
4. Submit a pull request

### Development Setup

```bash
# Clone repo
git clone https://github.com/burakdarende/bdrman.git
cd bdrman

# Make changes
nano bdrman.sh

# Test locally
sudo bash bdrman.sh --check-deps

# Test line endings
file bdrman.sh
```

## 📄 License

MIT License - see [LICENSE](LICENSE) file

## 👤 Author

**Burak Darende**

- GitHub: [@burakdarende](https://github.com/burakdarende)

## 🙏 Acknowledgments

- CapRover community for Docker volume management insights
- Security tools: Fail2Ban, ClamAV, RKHunter, Lynis, AppArmor, Aide, Auditd, Psad

---

**Version**: 3.1  
**Last Updated**: 2025-11-07  
**Status**: Production Ready ✅
