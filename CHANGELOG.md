# Changelog

All notable changes to BDRman will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.1.0] - 2025-11-07

### 🚀 Major Improvements

#### CRITICAL Fixes

- **Fixed CRLF line endings** → Converted to LF (Unix format)
  - Resolves: `/usr/bin/env: 'bash\r': No such file or directory`
  - Script now executes correctly on Linux servers
  - All files normalized to LF-only

#### Security Enhancements

- **Telegram config validation**

  - Token format validation (numeric:alphanumeric pattern)
  - Chat ID validation (must be numeric)
  - File permission enforcement (chmod 600)
  - Ownership verification (root:root)
  - Test API call before saving config

- **User input sanitization**

  - Remote backup paths validated (no `..` or special chars)
  - Filename sanitization with `basename`
  - SSH host format validation
  - All scp/rsync calls use `printf '%q'` escaping

- **Secure curl wrapper**
  - All Telegram API calls use `--fail --max-time 10 --retry 2`
  - Proper error handling and logging
  - Prevents hanging on network issues
  - Returns meaningful error codes

#### Operational Improvements

- **Atomic backup system**

  - All `tar` operations create `.partial` files first
  - Rename to final name only on success
  - Automatic cleanup of failed backups
  - Prevents corrupted backup files

- **Concurrency control (flock)**

  - Lock file: `/var/lock/bdrman.lock`
  - Prevents simultaneous backup/snapshot operations
  - Graceful error messages when lock held
  - Automatic lock release on exit (trap)

- **Idempotent service control**

  - `systemctl start` only if service not already running
  - `docker start` only targets stopped containers
  - Informative messages: "already running" vs "started"
  - Safer emergency mode exit

- **Configurable timeouts**
  - Backup operations: 600s (10min) default
  - Docker operations: 120s (2min) default
  - General commands: 60s (1min) default
  - All blocking commands wrapped in `timeout`

#### Monitoring System Overhaul

- **Reduced monitoring frequency**

  - Check loop: 2s → 30s (configurable via `MONITORING_INTERVAL`)
  - Alert cooldown: 2s → 300s / 5min (configurable via `ALERT_COOLDOWN`)
  - Prevents Telegram API rate limiting
  - Reduces server load

- **Per-alert type cooldown**

  - Separate tracking for: ddos, cpu, memory, disk, bruteforce, services
  - Files: `/tmp/bdrman_last_alert_<type>`
  - Each alert type can fire independently
  - Smarter spam prevention

- **Configurable thresholds**
  - DDoS: 50 connections/IP (was hardcoded)
  - CPU: 90% (was hardcoded)
  - Memory: 90% (was hardcoded)
  - Disk: 90% (was hardcoded)
  - Failed logins: 10 (was hardcoded)
  - All configurable via `/etc/bdrman/config.conf`

### 🔧 New Features

#### Configuration System

- **`config.conf.example`** created

  - 100+ configuration options
  - Detailed comments for each setting
  - Copy to `/etc/bdrman/config.conf` and customize
  - Auto-loaded at startup if exists

- **CLI argument parsing**
  ```bash
  bdrman --help              # Show help
  bdrman --version           # Show version
  bdrman --auto-backup       # Run backup and exit
  bdrman --dry-run           # Test without changes
  bdrman --non-interactive   # Skip confirmations
  bdrman --check-deps        # Verify dependencies
  bdrman --debug             # Enable debug output
  bdrman --config FILE       # Use custom config
  ```

#### Dependency Checker

- **`check_dependencies()` function**
  - Required tools: docker, tar, rsync, curl, systemctl
  - Optional tools: jq, certbot, wg-quick, fail2ban
  - Install suggestions for missing packages
  - Interactive confirmation to continue with missing deps

#### Log Rotation

- **`logrotate.bdrman` configuration**
  - `/var/log/bdrman.log`: weekly, 4 weeks retention
  - `/var/log/bdrman_security_alerts.log`: daily, 30 days retention
  - Compression enabled (gzip)
  - Size limit: 10MB before forcing rotation
  - Install: `cp logrotate.bdrman /etc/logrotate.d/bdrman`

### 📝 Documentation

#### New Files

- `README.md` - Comprehensive guide

  - Installation instructions
  - Usage examples
  - Configuration guide
  - Security best practices
  - Troubleshooting section
  - Acceptance testing procedures

- `CHANGELOG.md` - This file

  - Detailed version history
  - Migration guides
  - Breaking changes

- `config.conf.example` - Configuration template

  - All available settings
  - Default values
  - Explanatory comments

- `logrotate.bdrman` - Log rotation config
  - Ready to copy to `/etc/logrotate.d/`

#### Updated Files

- `SECURITY_FEATURES_V3.md`
  - New monitoring intervals
  - Configuration examples
  - Cooldown explanations

### 🐛 Bug Fixes

- **Emergency exit clarification**

  - Changed confusing "restore" wording to "start"
  - Added explicit warnings: "NO data deleted, nothing reinstalled"
  - Updated Telegram command messages
  - Fixed documentation to be crystal clear

- **Backup failures handling**

  - All backup functions now return error codes
  - Proper error logging for failed operations
  - No silent failures

- **Telegram API failures**
  - Timeout prevents infinite hangs
  - Retry logic (2 attempts)
  - Error logging for debugging
  - User feedback on failures

### ⚠️ Breaking Changes

#### Monitoring Behavior

- **Alert frequency drastically reduced**
  - Old: Alerts every 2 seconds during threat
  - New: Alerts max once per 5 minutes per threat type
  - **Migration**: If you want old behavior, set in `config.conf`:
    ```bash
    MONITORING_INTERVAL=2
    ALERT_COOLDOWN=2
    ```

#### File Permissions

- **Stricter Telegram config permissions**
  - Old: Permissions not enforced
  - New: Must be 600 (owner read/write only)
  - **Migration**: Script auto-fixes on next run, or manually:
    ```bash
    sudo chmod 600 /etc/bdrman/telegram.conf
    sudo chown root:root /etc/bdrman/telegram.conf
    ```

#### Lock Files

- **Operations may fail if another instance running**
  - Old: Multiple backups could run simultaneously
  - New: Locked to one operation at a time
  - **Migration**: If lock is stale, remove manually:
    ```bash
    sudo rm /var/lock/bdrman.lock
    ```

### 📦 Migration Guide (v3.0 → v3.1)

1. **Update script**

   ```bash
   sudo curl -fsSL https://raw.githubusercontent.com/burakdarende/bdrman/main/bdrman.sh -o /usr/local/bin/bdrman
   sudo chmod +x /usr/local/bin/bdrman
   ```

2. **Fix line endings** (CRITICAL)

   ```bash
   sudo sed -i 's/\r$//' /usr/local/bin/bdrman
   ```

3. **Create config file** (optional but recommended)

   ```bash
   sudo cp config.conf.example /etc/bdrman/config.conf
   sudo chmod 600 /etc/bdrman/config.conf
   sudo nano /etc/bdrman/config.conf  # Customize settings
   ```

4. **Install logrotate** (optional)

   ```bash
   sudo cp logrotate.bdrman /etc/logrotate.d/bdrman
   ```

5. **Restart monitoring** (if active)

   ```bash
   sudo systemctl restart bdrman-security-monitor
   ```

6. **Verify Telegram config**

   ```bash
   ls -la /etc/bdrman/telegram.conf
   # Should show: -rw------- 1 root root

   # If not:
   sudo chmod 600 /etc/bdrman/telegram.conf
   sudo chown root:root /etc/bdrman/telegram.conf
   ```

7. **Test**
   ```bash
   sudo bdrman --check-deps
   sudo bdrman --version
   sudo bdrman-telegram "Migration to v3.1 complete!"
   ```

### 🔍 Testing

#### Automated Tests Added

See `README.md` section "Testing & Validation" for 10 acceptance tests:

1. Line ending verification
2. Dependency checker
3. Config loading
4. Lock mechanism
5. Atomic backups
6. Alert cooldown
7. Input sanitization
8. Idempotent services
9. Curl timeout
10. Logrotate dry-run

#### Manual Testing Checklist

- [x] CRLF → LF conversion
- [x] Config file loading from `/etc/bdrman/config.conf`
- [x] CLI arguments (--help, --version, etc.)
- [x] Lock prevents concurrent backups
- [x] No .partial files after successful backup
- [x] Telegram alerts respect cooldown
- [x] Invalid remote paths rejected
- [x] Services not restarted if already running
- [x] Curl timeouts work (tested with iptables block)
- [x] Logrotate config valid

---

## [3.0.0] - 2025-11-06

### 🚀 Major Features

#### Real-time Security Monitoring

- DDoS detection (connection flooding)
- High CPU usage alerts (>90%)
- High memory usage alerts (>90%)
- Critical disk space alerts (>90%)
- Brute force login detection
- Service downtime detection

#### Automated Telegram Alerts

- Instant notifications for detected threats
- Detailed threat information
- Recommended actions included
- 2-second polling interval (too aggressive - fixed in v3.1)

#### Security Tools Suite

- Fail2Ban installation and configuration
- ClamAV antivirus with auto-update
- RKHunter rootkit detection
- Lynis security auditing
- AppArmor MAC system
- Aide file integrity checker
- Auditd Linux audit framework
- Psad port scan detector

#### DDoS Protection

- Automated iptables rules
- SYN flood protection
- ICMP flood mitigation
- Connection rate limiting
- Per-IP connection limits

#### Emergency Mode Improvements

- Emergency exit command added
- Service restoration without reinstall
- Firewall port reopening
- Both menu and Telegram access

#### Fun Features

- `/joke` - Server jokes
- `/fortune` - Fortune telling
- `/cowsay` - ASCII cow messages
- `/funstats` - Fun system statistics
- `/ascii_art` - Random ASCII art
- `/tip` - Linux tips

### 🐛 Known Issues (Fixed in v3.1)

- CRLF line endings cause execution failures
- Telegram rate limiting due to 2s polling
- No concurrency control on backups
- Hardcoded monitoring thresholds
- Missing input validation on remote backups

---

## [2.x.x] - Earlier Versions

### Features

- Basic CapRover backup/restore
- System monitoring
- Firewall management
- WireGuard VPN setup
- SSL certificate management
- Telegram bot basic integration

### Known Limitations

- No real-time security monitoring
- Manual security tool installation
- No DDoS protection
- Limited error handling
- No configuration file support

---

## Upgrade Notes

### From v2.x to v3.1

**IMPORTANT**: Follow migration guide above. Key changes:

1. Line endings MUST be fixed (CRLF → LF)
2. Monitoring frequency reduced 15x (2s → 30s)
3. Config file system introduced
4. Telegram permissions enforced

### Future Plans (v3.2+)

- [ ] Database backup integration (PostgreSQL, MySQL)
- [ ] Webhook support (Slack, Discord, generic)
- [ ] Multi-server management
- [ ] Web dashboard (optional)
- [ ] Backup encryption (GPG)
- [ ] Backup compression options (zstd, lz4)
- [ ] IPv6 support in DDoS detection
- [ ] GeoIP-based firewall rules
- [ ] Custom alert templates
- [ ] Alert aggregation (multiple alerts → single message)

---

**Maintained by**: Burak Darende  
**Repository**: https://github.com/burakdarende/bdrman  
**License**: MIT
