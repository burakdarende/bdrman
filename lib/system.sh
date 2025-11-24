# ============= SYSTEM STATUS & MANAGEMENT =============

system_status(){
  clear_and_banner
  echo "=== SYSTEM STATUS ==="
  echo "--------------------------------"
  echo "Version: ${VERSION}"
  echo "Hostname: $(hostname)"
  echo "OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
  echo "Kernel: $(uname -r)"
  echo "Uptime: $(uptime -p)"
  echo "--------------------------------"
  echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
  echo "Memory Usage: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
  echo "Disk Usage: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
  echo "--------------------------------"
  pause
}

show_version(){
  clear_and_banner
  echo "=== VERSION INFORMATION ==="
  echo ""
  echo "🤖 BDRman Version: ${VERSION}"
  echo "🐧 OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
  echo "⚙️  Kernel: $(uname -r)"
  echo "💻 Hostname: $(hostname)"
  echo ""
  echo "📂 Installation Path: /usr/local/bin/bdrman"
  echo "📋 Config Path: /etc/bdrman"
  echo "📊 Logs: /var/log/bdrman*.log"
  echo ""
}

system_update(){
  echo "=== BDRMAN UPDATE SYSTEM ==="
  echo ""
  echo "This will update BDRman to the latest version from GitHub."
  echo "✅ Your settings will be preserved:"
  echo "   - Telegram configuration (/etc/bdrman/telegram.conf)"
  echo "   - All backups (/var/backups/bdrman)"
  echo "   - System logs"
  echo ""
  
  read -rp "Continue with update? (yes/no): " ans
  if [ "$ans" != "yes" ]; then 
    echo "Update cancelled."
    return
  fi
  
  echo ""
  echo "📦 Step 1/4: Backing up current configuration..."
  
  # Create backup directory
  BACKUP_TEMP="/tmp/bdrman_update_backup_$(date +%s)"
  mkdir -p "$BACKUP_TEMP"
  
  # Backup configs
  if [ -d /etc/bdrman ]; then
    cp -r /etc/bdrman "$BACKUP_TEMP/" 2>/dev/null
    echo "   ✅ Config backed up"
  fi
  
  # Backup current version info
  if [ -f /usr/local/bin/bdrman ]; then
    cp /usr/local/bin/bdrman "$BACKUP_TEMP/bdrman.old" 2>/dev/null
    echo "   ✅ Current version saved"
  fi
  
  echo ""
  echo "⬇️  Step 2/4: Downloading latest version..."
  
  # Download latest installer
  if ! curl -s -f -L "https://raw.githubusercontent.com/burakdarende/bdrman/main/install.sh?v=$(date +%s)" -o "/tmp/bdrman_install_latest.sh"; then
    echo "❌ Failed to download installer"
    echo "   Your system was not modified."
    rm -rf "$BACKUP_TEMP"
    return 1
  fi
  
  echo "   ✅ Downloaded successfully"
  
  echo ""
  echo "🔧 Step 3/4: Installing update..."
  
  # Run installer
  if bash "/tmp/bdrman_install_latest.sh"; then
    echo "   ✅ Installation complete"
    # Overwrite installed script with the current source version (if this script is newer)
    if [ -f "$(dirname "$0")/bdrman.sh" ]; then
      cp "$(dirname "$0")/bdrman.sh" "/usr/local/bin/bdrman"
      chmod +x "/usr/local/bin/bdrman"
      echo "   ✅ Updated /usr/local/bin/bdrman with local version"
    fi
  else
    echo "❌ Installation failed"
    echo "   Restoring backup..."
    
    # Restore from backup
    if [ -d "$BACKUP_TEMP/bdrman" ]; then
      cp -r "$BACKUP_TEMP/bdrman"/* /etc/bdrman/ 2>/dev/null
    fi
    
    rm -rf "$BACKUP_TEMP"
    return 1
  fi
  
  echo ""
  echo "🔄 Step 4/4: Restoring your settings..."
  
  # Restore telegram config (most important)
  if [ -f "$BACKUP_TEMP/bdrman/telegram.conf" ]; then
    cp "$BACKUP_TEMP/bdrman/telegram.conf" /etc/bdrman/telegram.conf
    chmod 600 /etc/bdrman/telegram.conf
    echo "   ✅ Telegram config restored"
  fi
  
  # Restore telegram bot script if it was customized
  if [ -f "$BACKUP_TEMP/bdrman/telegram_bot.py" ]; then
    # Only restore if user had customizations (check if different from new version)
    if ! diff -q "$BACKUP_TEMP/bdrman/telegram_bot.py" /etc/bdrman/telegram_bot.py >/dev/null 2>&1; then
      echo "   ⚠️  You had a custom telegram_bot.py"
      echo "   ℹ️  New version installed, old saved to telegram_bot.py.backup"
      cp "$BACKUP_TEMP/bdrman/telegram_bot.py" /etc/bdrman/telegram_bot.py.backup
    fi
  fi
  
  # Clean up temp files
  rm -rf "$BACKUP_TEMP"
  rm -f /tmp/bdrman_install_latest.sh
  
  echo ""
  echo "🔄 Restarting services..."
  
  # Restart telegram bot if it was running
  if systemctl is-active --quiet bdrman-telegram 2>/dev/null; then
    systemctl restart bdrman-telegram
    echo "   ✅ Telegram bot restarted"
  fi
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "✅ UPDATE COMPLETE!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "📝 What was updated:"
  echo "   • BDRman core scripts"
  echo "   • All library modules"
  echo "   • Telegram bot (if installed)"
  echo ""
  echo "🎯 Your settings were preserved:"
  echo "   • Telegram configuration"
  echo "   • All backups"
  echo "   • Custom configurations"
  echo ""
  echo "📌 Current version: ${VERSION}"
  echo ""
  
  # Restart Telegram bot if it's running (to load new code)
  if systemctl is-active --quiet bdrman-telegram 2>/dev/null; then
    echo "🔄 Restarting Telegram bot..."
    systemctl restart bdrman-telegram
    sleep 2  # Wait for bot to initialize
    echo "   ✅ Bot restarted"
  fi

  # Reload VERSION from the newly installed script
  if [ -f "/usr/local/bin/bdrman" ]; then
    source "/usr/local/bin/bdrman"
    echo "🔁 Reloaded VERSION: ${VERSION}"
  fi
  
  # Send Telegram notification if configured
  if [ -f /etc/bdrman/telegram.conf ]; then
    source /etc/bdrman/telegram.conf 2>/dev/null
    if [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ]; then
      HOSTNAME=$(hostname)
      # Read NEW version from updated bdrman script (not old VERSION variable!)
      NEW_VERSION=$(grep 'VERSION=' /usr/local/bin/bdrman | head -1 | cut -d'=' -f2 | tr -d '"')
      MESSAGE="✅ *BDRman Update Complete*%0A%0A🤖 Version: ${NEW_VERSION}%0A💻 Server: ${HOSTNAME}%0A⏰ $(date '+%Y-%m-%d %H:%M:%S')%0A%0AAll systems ready!"
      curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${MESSAGE}" \
        -d "parse_mode=Markdown" > /dev/null 2>&1
      echo "📱 Telegram notification sent (Version: ${NEW_VERSION})"
      echo ""
    fi
  fi
  echo "💡 Next steps:"
  echo "   • Test Telegram bot: Send /help to your bot"
  echo "   • Check status: systemctl status bdrman-telegram"
  echo ""
  
  log_success "BDRman updated successfully"
  
  read -rp "Press Enter to continue..."
}

check_updates(){
  # Check local version vs remote version
  # This is a placeholder logic
  echo "Checking for updates..."
  # In a real scenario, we would fetch version.txt from GitHub
}

uninstall_bdrman(){
  echo "=== DEEP CLEAN UNINSTALL ==="
  echo "⚠️  DANGER: This will PERMANENTLY REMOVE BDRman and ALL associated data."
  echo "    - Binaries: /usr/local/bin/bdrman*"
  echo "    - Configs:  /etc/bdrman"
  echo "    - Data:     /opt/bdrman (venv, libs)"
  echo "    - Logs:     /var/log/bdrman*"
  echo "    - Services: bdrman-telegram.service"
  echo "    - Cron:     Weekly reports"
  echo ""
  echo "    Backups in $BACKUP_DIR will be PRESERVED unless you choose to delete them."
  
  read -rp "Are you SURE? Type 'uninstall' to confirm: " ans
  if [ "$ans" != "uninstall" ]; then echo "Cancelled."; pause; return; fi

  echo "🛑 Stopping services..."
  systemctl stop bdrman-telegram 2>/dev/null
  systemctl disable bdrman-telegram 2>/dev/null
  rm -f /etc/systemd/system/bdrman-telegram.service
  systemctl daemon-reload
  
  echo "🗑️  Removing binaries and libraries..."
  rm -f /usr/local/bin/bdrman
  rm -f /usr/local/bin/bdrman-telegram
  
  # Remove new library location
  rm -rf /usr/local/lib/bdrman
  
  # Clean up legacy library location if it exists and looks like ours
  if [ -d "/usr/local/bin/lib" ]; then
    if [ -f "/usr/local/bin/lib/core.sh" ] && [ -f "/usr/local/bin/lib/bdrman.sh" ]; then
       rm -rf "/usr/local/bin/lib"
    elif [ -f "/usr/local/bin/lib/core.sh" ]; then
       # Be safer, just remove known files
       rm -f /usr/local/bin/lib/*.sh
       rmdir /usr/local/bin/lib 2>/dev/null || true
    fi
  fi
  
  echo "🗑️  Removing data and configs..."
  rm -rf /opt/bdrman
  rm -rf /etc/bdrman
  rm -f /var/log/bdrman*
  
  echo "🗑️  Cleaning cron jobs..."
  crontab -l 2>/dev/null | grep -v "telegram_weekly_report.sh" | crontab -
  
  read -rp "❓ Do you want to delete all backups in $BACKUP_DIR? (y/n): " del_backups
  if [[ "$del_backups" =~ ^[Yy]$ ]]; then
    rm -rf "$BACKUP_DIR"
    echo "🗑️  Backups deleted."
  else
    echo "✅ Backups preserved at $BACKUP_DIR"
  fi
  
  echo "✅ BDRman has been completely removed. Goodbye!"
  exit 0
}

system_fix_permissions(){
  echo "=== FIX PERMISSIONS ==="
  echo "Fixing permissions for BDRman files..."
  
  # Configs
  chmod 600 /etc/bdrman/*.conf 2>/dev/null
  chmod 700 /etc/bdrman 2>/dev/null
  
  # Binaries
  chmod +x /usr/local/bin/bdrman
  chmod +x /usr/local/bin/bdrman-telegram
  
  # Logs
  touch "$LOGFILE"
  chmod 640 "$LOGFILE"
  
  success "Permissions fixed."
}

# ============= LOGS & MONITORING =============
logs_bdrman(){
  echo "=== BDRMAN LOGS ==="
  if [ -f "$LOGFILE" ]; then
    tail -n 50 "$LOGFILE" | less
  else
    echo "Log file not found."
  fi
}

logs_system_errors(){
  echo "=== SYSTEM CRITICAL ERRORS ==="
  journalctl -p 3 -xb | tail -n 50 | less
}

logs_wireguard(){
  echo "=== WIREGUARD LOGS ==="
  journalctl -u wg-quick@wg0 -n 50 --no-pager | less
}

logs_docker(){
  echo "=== DOCKER LOGS ==="
  journalctl -u docker -n 50 --no-pager | less
}

logs_firewall(){
  echo "=== FIREWALL LOGS ==="
  if [ -f /var/log/ufw.log ]; then
    tail -n 50 /var/log/ufw.log | less
  else
    dmesg | grep UFW | tail -n 50 | less
  fi
}

logs_all_critical(){
  echo "=== ALL CRITICAL ISSUES ==="
  echo "--- System Errors ---"
  journalctl -p 3 -n 10 --no-pager
  echo ""
  echo "--- Failed Services ---"
  systemctl --failed --no-pager
  echo ""
  echo "--- Disk Space ---"
  df -h /
}

logs_custom_search(){
  read -rp "Enter search term: " term
  if [ -n "$term" ]; then
    grep -r "$term" /var/log/syslog 2>/dev/null | tail -n 20
  fi
}

monitor_resources(){
  if command_exists htop; then
    htop
  else
    top
  fi
}

monitor_alerts(){
  echo "=== SETUP ALERTS ==="
  echo "Use Telegram setup for alerts."
  telegram_setup
}

monitor_uptime(){
  echo "=== UPTIME & SERVICE STATUS ==="
  uptime
  echo ""
  systemctl status docker nginx wg-quick@wg0 --no-pager
}

# ============= METRICS COLLECTION =============
metrics_collect(){
  # Simple metrics collection to a CSV file
  METRICS_FILE="/var/log/bdrman_metrics.csv"
  
  if [ ! -f "$METRICS_FILE" ]; then
    echo "timestamp,cpu,mem,disk" > "$METRICS_FILE"
  fi
  
  TS=$(date +%s)
  CPU=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
  MEM=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
  DISK=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
  
  echo "$TS,$CPU,$MEM,$DISK" >> "$METRICS_FILE"
}

metrics_report(){
  METRICS_FILE="/var/log/bdrman_metrics.csv"
  if [ ! -f "$METRICS_FILE" ]; then
    echo "No metrics data found."
    return
  fi
  
  echo "=== PERFORMANCE REPORT ==="
  echo "Last 10 entries:"
  tail -10 "$METRICS_FILE"
}

metrics_graph(){
  # Simple ASCII graph (placeholder)
  echo "Graph feature requires python or gnuplot (not implemented in bash only)"
  metrics_report
}

metrics_start_daemon(){
  # Start a background loop
  nohup bash -c "while true; do bdrman metrics collect; sleep 60; done" >/dev/null 2>&1 &
  echo "Metrics daemon started (pid $!)"
}

# ============= ADVANCED TOOLS =============
nginx_manage(){
  echo "=== NGINX MANAGEMENT ==="
  echo "1) Status"
  echo "2) Restart"
  echo "3) Test Config"
  echo "4) Reload"
  echo "5) Edit Config"
  read -rp "Choice: " c
  case "$c" in
    1) systemctl status nginx --no-pager ;;
    2) systemctl restart nginx && echo "Restarted" ;;
    3) nginx -t ;;
    4) systemctl reload nginx && echo "Reloaded" ;;
    5) nano /etc/nginx/nginx.conf ;;
  esac
}

perf_optimize(){
  echo "=== PERFORMANCE OPTIMIZATION ==="
  echo "1) Clear PageCache, dentries and inodes"
  echo "2) Optimize TCP stack (sysctl)"
  echo "3) Clean package cache"
  read -rp "Choice: " c
  case "$c" in
    1) 
      sync; echo 3 > /proc/sys/vm/drop_caches
      echo "✅ Caches cleared"
      ;;
    2)
      echo "Applying TCP optimizations..."
      cat >> /etc/sysctl.conf << EOF
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_slow_start_after_idle = 0
EOF
      sysctl -p
      echo "✅ TCP optimized"
      ;;
    3)
      apt clean
      apt autoremove -y
      echo "✅ Package cache cleaned"
      ;;
  esac
}

incident_health_check(){
  echo "=== SYSTEM HEALTH CHECK ==="
  echo "Checking core services..."
  
  SERVICES=("docker" "nginx" "ssh" "cron")
  [ -f /etc/wireguard/wg0.conf ] && SERVICES+=("wg-quick@wg0")
  
  ALL_OK=true
  for svc in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$svc"; then
      echo "✅ $svc: RUNNING"
    else
      echo "❌ $svc: FAILED/STOPPED"
      ALL_OK=false
    fi
  done
  
  echo ""
  echo "Checking disk space..."
  df -h / | awk 'NR==2 {print $5 " used"}'
  
  echo ""
  if [ "$ALL_OK" = true ]; then
    success "System Health: GOOD"
  else
    error "System Health: ISSUES FOUND"
  fi
}

incident_auto_recovery(){
  echo "=== AUTO RECOVERY SETUP ==="
  echo "This will setup a cron job to check services and restart them if failed."
  
  cat > /usr/local/bin/bdrman-recovery << 'EOF'
#!/bin/bash
SERVICES="docker nginx ssh"
for svc in $SERVICES; do
  if ! systemctl is-active --quiet "$svc"; then
    echo "$(date): $svc is down. Restarting..." >> /var/log/bdrman_recovery.log
    systemctl restart "$svc"
  fi
done
EOF
  chmod +x /usr/local/bin/bdrman-recovery
  
  (crontab -l 2>/dev/null | grep -v "bdrman-recovery"; echo "*/5 * * * * /usr/local/bin/bdrman-recovery") | crontab -
  
  success "Auto-recovery enabled (checks every 5 mins)"
}

# ============= MENUS =============
logs_menu(){
  while true; do
    clear_and_banner
    echo "=== LOGS & MONITORING ==="
    echo "0) Back"
    echo "1) BDRman Script Logs"
    echo "2) System Critical Errors"
    echo "3) WireGuard Logs"
    echo "4) Docker/CapRover Logs"
    echo "5) Firewall Logs (UFW)"
    echo "6) All Critical Issues Summary"
    echo "7) Custom Search in Logs"
    echo "8) Full BDRman Log File (less)"
    read -rp "Select (0-8): " c
    case "$c" in
      0) break ;;
      1) logs_bdrman; pause ;;
      2) logs_system_errors; pause ;;
      3) logs_wireguard; pause ;;
      4) logs_docker; pause ;;
      5) logs_firewall; pause ;;
      6) logs_all_critical; pause ;;
      7) logs_custom_search; pause ;;
      8) [ -f "$LOGFILE" ] && less "$LOGFILE" || echo "Log file not found."; pause ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}

monitoring_menu(){
  while true; do
    clear_and_banner
    echo "=== MONITORING & ALERTS ==="
    echo "0) Back"
    echo "1) Resource Monitor (CPU/RAM/Disk)"
    echo "2) Setup Email Alerts"
    echo "3) Uptime & Service Status"
    read -rp "Select (0-3): " c
    case "$c" in
      0) break ;;
      1) monitor_resources; pause ;;
      2) monitor_alerts; pause ;;
      3) monitor_uptime; pause ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}

settings_menu(){
  while true; do
    clear_and_banner
    echo "=== SETTINGS ==="
    echo "0) Back"
    echo "1) Update BDRman"
    echo "2) Uninstall BDRman"
    echo "3) Change Hostname"
    echo "4) Configure Timezone"
    read -rp "Select (0-4): " c
    case "$c" in
      0) break ;;
      1)
        system_update
        if [ $? -eq 0 ]; then
          echo "🔄 Reloading BDRman..."
          sleep 2
          exec "$0" "$@"
        fi
        pause
        ;; 
      2) uninstall_bdrman; pause ;;
      3)
        read -rp "New Hostname: " h
        if [ -n "$h" ]; then
          hostnamectl set-hostname "$h"
          echo "127.0.0.1 $h" >> /etc/hosts
          success "Hostname changed to $h"
        fi
        pause
        ;;
      4)
        dpkg-reconfigure tzdata
        pause
        ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}

advanced_menu(){
  while true; do
    clear_and_banner
    echo "=== ADVANCED TOOLS ==="
    echo "0) Back"
    echo "1) Nginx Management"
    echo "2) Network Diagnostics"
    echo "3) Performance & Cleanup"
    echo "4) System Snapshot & Restore"
    echo "5) Configuration as Code"
    echo "6) Advanced Firewall"
    echo "7) 🔧 Fix Permissions (Self-Repair)"
    echo "8) 🗑️  Uninstall BDRman"
    read -rp "Select (0-8): " c
    case "$c" in
      0) break ;;
      1) nginx_manage; pause ;;
      2) network_diag; pause ;;
      3) perf_optimize; pause ;;
      4) snapshot_menu; pause ;;
      5) config_menu; pause ;;
      6) firewall_advanced; pause ;;
      7) system_fix_permissions; pause ;;
      8) system_uninstall ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}
