#!/usr/bin/env bash
# bdrman - Server Management Panel (English version)
# Author: Burak Darende

if [ "$EUID" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    echo "Root privileges required, relaunching with sudo..."
    exec sudo bash "$0" "$@"
  else
    echo "This script requires root access."
    exit 1
  fi
fi

LOGFILE="/var/log/bdrman.log"
BACKUP_DIR="/var/backups/bdrman"
CONFIG_FILE="/etc/bdrman/config.conf"

log(){
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOGFILE" >/dev/null
}

log_error(){
  echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $*" | tee -a "$LOGFILE" >/dev/null
}

log_success(){
  echo "$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS: $*" | tee -a "$LOGFILE" >/dev/null
}

command_exists(){
  command -v "$1" >/dev/null 2>&1
}

pause(){
  read -rp $'\nPress ENTER to continue...'
}

clear_and_banner(){
  clear
  COLS=$(tput cols 2>/dev/null || echo 80)
  BLUE="\e[1;34m"; YELLOW="\e[1;33m"; RESET="\e[0m"

  banner_lines=(
"888888b.   8888888b.  8888888b.       888     888 8888888b.   .d8888b.       888b     d888                       "
"888  \"88b  888  \"Y88b 888   Y88b      888     888 888   Y88b d88P  Y88b      8888b   d8888                       "
"888  .88P  888    888 888    888      888     888 888    888 Y88b.           88888b.d88888                       "
"8888888K.  888    888 888   d88P      Y88b   d88P 888   d88P  \"Y888b.        888Y88888P888  8888b.  88888b.      "
"888  \"Y88b 888    888 8888888P\"        Y88b d88P  8888888P\"      \"Y88b.      888 Y888P 888     \"88b 888 \"88b     "
"888    888 888    888 888 T88b          Y88o88P   888              \"888      888  Y8P  888 .d888888 888  888     "
"888   d88P 888  .d88P 888  T88b          Y888P    888        Y88b  d88P      888   \"   888 888  888 888  888 d8b "
"8888888P\"  8888888P\"  888   T88b          Y8P     888         \"Y8888P\"       888       888 \"Y888888 888  888 Y8P "
  )

  for line in "${banner_lines[@]}"; do
    padding=$(( (COLS - ${#line}) / 2 ))
    if [ "$padding" -gt 0 ]; then
      printf "%*s" "$padding" ""
    fi
    echo -e "${BLUE}${line}${RESET}"
  done

  subtitle="BDR - SERVER MANAGEMENT PANEL"
  padding=$(( (COLS - ${#subtitle}) / 2 ))
  printf "%*s" "$padding" ""
  echo -e "${YELLOW}${subtitle}${RESET}"
  echo
}

# ============= VPN (WireGuard) =============
vpn_status(){
  if command_exists wg-quick; then
    systemctl status wg-quick@wg0 --no-pager || wg show || echo "WireGuard service info not available."
  else
    echo "WireGuard not installed or not in PATH."
  fi
}

vpn_add_client(){
  if [ -f "/usr/local/bin/wireguard-install.sh" ]; then
    bash /usr/local/bin/wireguard-install.sh
    log "wireguard-install.sh executed"
  elif [ -f "./wireguard-install.sh" ]; then
    bash ./wireguard-install.sh
    log "local wireguard-install.sh executed"
  else
    echo "wireguard-install.sh not found. Place it in /usr/local/bin or current directory."
  fi
}

vpn_restart(){
  systemctl restart wg-quick@wg0 && echo "WireGuard restarted." || echo "Restart failed."
}

# ============= CAPROVER =============
caprover_check(){
  if command_exists docker; then
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | grep -i 'caprover' || echo "CapRover container not found."
  else
    echo "Docker not installed."
  fi
}

caprover_logs(){
  if command_exists docker; then
    CAP_CONTAINER=$(docker ps --filter "name=caprover" --format "{{.Names}}" | head -n1)
    if [ -n "$CAP_CONTAINER" ]; then
      docker logs --tail 200 -f "$CAP_CONTAINER"
    else
      echo "CapRover container not found."
    fi
  else
    echo "Docker not installed."
  fi
}

caprover_restart(){
  if command_exists docker; then
    CAP_CONTAINER=$(docker ps --filter "name=caprover" --format "{{.Names}}" | head -n1)
    if [ -n "$CAP_CONTAINER" ]; then
      docker restart "$CAP_CONTAINER" && echo "CapRover restarted ($CAP_CONTAINER)." || echo "Restart failed."
    else
      echo "CapRover container not found."
    fi
  else
    echo "Docker not installed."
  fi
}

# ============= FIREWALL (UFW) =============
fw_status(){ ufw status verbose 2>/dev/null || echo "UFW not installed."; }
fw_enable(){ ufw enable && echo "Firewall enabled." || echo "Enable failed."; }
fw_disable(){ ufw disable && echo "Firewall disabled." || echo "Disable failed."; }
fw_allow_port(){
  read -rp "Port to allow (e.g. 22/tcp or 80): " port
  [ -n "$port" ] && ufw allow "$port" && echo "Allowed $port" || echo "Port empty."
}
fw_deny_ip(){
  read -rp "IP to block: " ip
  [ -n "$ip" ] && ufw deny from "$ip" && echo "Blocked $ip" || echo "IP empty."
}
fw_reset(){
  read -rp "This will reset all UFW rules. Continue? (y/n): " ans
  [[ "$ans" =~ [Yy] ]] && ufw --force reset && echo "Firewall reset." || echo "Cancelled."
}

# ============= LOGS & MONITORING =============
logs_bdrman(){
  if [ -f "$LOGFILE" ]; then
    echo "=== BDRman Script Logs (last 50 lines) ==="
    tail -n 50 "$LOGFILE" | while IFS= read -r line; do
      if [[ "$line" =~ ERROR|FAIL|CRITICAL ]]; then
        echo -e "\e[1;31m$line\e[0m"  # Red for errors
      elif [[ "$line" =~ WARN|WARNING ]]; then
        echo -e "\e[1;33m$line\e[0m"  # Yellow for warnings
      else
        echo -e "\e[0;37m$line\e[0m"  # Normal
      fi
    done
  else
    echo "Log file not found: $LOGFILE"
  fi
}

logs_system_errors(){
  echo "=== System Critical Errors (last 100 lines) ==="
  if command_exists journalctl; then
    journalctl -p err -n 100 --no-pager | tail -n 50
  else
    echo "journalctl not available. Checking /var/log/syslog..."
    grep -i "error\|critical\|fail" /var/log/syslog 2>/dev/null | tail -n 50 || echo "No syslog found."
  fi
}

logs_wireguard(){
  echo "=== WireGuard Logs ==="
  if command_exists journalctl; then
    journalctl -u wg-quick@wg0 -n 100 --no-pager || echo "No WireGuard service logs."
  else
    echo "journalctl not available."
  fi
}

logs_docker(){
  echo "=== Docker/CapRover Logs ==="
  if command_exists docker; then
    echo "--- Recent Docker Events (last 20) ---"
    docker events --since 24h --until 1s 2>/dev/null | tail -n 20 || echo "No recent events."
    echo ""
    echo "--- CapRover Container Logs (last 100 lines) ---"
    CAP_CONTAINER=$(docker ps --filter "name=caprover" --format "{{.Names}}" | head -n1)
    if [ -n "$CAP_CONTAINER" ]; then
      docker logs --tail 100 "$CAP_CONTAINER" 2>&1 | tail -n 50
    else
      echo "CapRover container not found."
    fi
  else
    echo "Docker not installed."
  fi
}

logs_firewall(){
  echo "=== UFW Firewall Logs ==="
  if [ -f /var/log/ufw.log ]; then
    tail -n 50 /var/log/ufw.log
  else
    echo "UFW log file not found. Checking journalctl..."
    journalctl -u ufw -n 50 --no-pager 2>/dev/null || echo "No UFW logs available."
  fi
}

logs_all_critical(){
  echo "=== ALL CRITICAL ERRORS (Combined) ==="
  echo ""
  echo "--- System Errors ---"
  journalctl -p err -n 20 --no-pager 2>/dev/null | tail -n 10
  echo ""
  echo "--- Failed Services ---"
  systemctl --failed --no-pager 2>/dev/null || echo "systemctl not available."
  echo ""
  echo "--- Docker Issues ---"
  docker ps --filter "status=exited" --filter "status=dead" 2>/dev/null || echo "No Docker issues or Docker not installed."
  echo ""
  echo "--- Disk Usage Warnings ---"
  df -h | awk '$5+0 > 80 {print "⚠️  "$0}' || echo "Disk usage OK."
  echo ""
  echo "--- Memory Usage ---"
  free -h | grep -E "^Mem" | awk '{used=$3; total=$2; print "Used: "used" / Total: "total}'
}

logs_custom_search(){
  read -rp "Enter search term (regex supported): " search_term
  if [ -z "$search_term" ]; then
    echo "Search term empty."
    return
  fi
  echo "=== Searching in system logs for: $search_term ==="
  journalctl -n 500 --no-pager 2>/dev/null | grep -i "$search_term" | tail -n 30 || echo "No matches found."
}

# ============= BACKUP & RESTORE =============
backup_create(){
  echo "=== CREATE BACKUP ==="
  mkdir -p "$BACKUP_DIR"
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"
  
  echo "Creating backup at: $BACKUP_FILE"
  tar -czf "$BACKUP_FILE" \
    /etc/wireguard 2>/dev/null \
    /etc/ufw 2>/dev/null \
    /etc/nginx 2>/dev/null \
    /etc/ssh/sshd_config 2>/dev/null \
    "$LOGFILE" 2>/dev/null \
    || true
  
  if [ -f "$BACKUP_FILE" ]; then
    echo "✅ Backup created: $BACKUP_FILE"
    log_success "Backup created: $BACKUP_FILE"
  else
    echo "❌ Backup failed!"
    log_error "Backup creation failed"
  fi
}

backup_list(){
  echo "=== AVAILABLE BACKUPS ==="
  if [ -d "$BACKUP_DIR" ]; then
    ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "No backups found."
  else
    echo "Backup directory not found."
  fi
}

backup_restore(){
  echo "=== RESTORE FROM BACKUP ==="
  backup_list
  echo ""
  read -rp "Enter backup filename to restore: " backup_name
  if [ -z "$backup_name" ]; then
    echo "No file specified."
    return
  fi
  
  RESTORE_FILE="$BACKUP_DIR/$backup_name"
  if [ ! -f "$RESTORE_FILE" ]; then
    echo "❌ Backup file not found: $RESTORE_FILE"
    return
  fi
  
  read -rp "⚠️  This will overwrite current configs. Continue? (yes/no): " confirm
  if [[ "$confirm" != "yes" ]]; then
    echo "Restore cancelled."
    return
  fi
  
  tar -xzf "$RESTORE_FILE" -C / && echo "✅ Restore completed!" || echo "❌ Restore failed!"
  log "Restored from: $RESTORE_FILE"
}

backup_auto_setup(){
  echo "=== SETUP AUTOMATIC BACKUP ==="
  echo "This will create a daily backup cron job at 2 AM"
  read -rp "Continue? (y/n): " ans
  [[ "$ans" =~ [Yy] ]] || return
  
  CRON_CMD="0 2 * * * $0 --auto-backup"
  (crontab -l 2>/dev/null | grep -v "bdrman"; echo "$CRON_CMD") | crontab -
  echo "✅ Automatic backup scheduled (daily at 2 AM)"
  log_success "Auto backup cron job created"
}

backup_remote(){
  echo "=== SEND BACKUP TO REMOTE SERVER ==="
  read -rp "Remote server (user@host): " remote
  read -rp "Remote path: " remote_path
  
  if [ -z "$remote" ] || [ -z "$remote_path" ]; then
    echo "Missing information."
    return
  fi
  
  backup_list
  read -rp "Backup file to send: " backup_file
  LOCAL_FILE="$BACKUP_DIR/$backup_file"
  
  if [ ! -f "$LOCAL_FILE" ]; then
    echo "File not found."
    return
  fi
  
  echo "Sending $LOCAL_FILE to $remote:$remote_path"
  scp "$LOCAL_FILE" "$remote:$remote_path" && echo "✅ Sent successfully!" || echo "❌ Transfer failed!"
}

# ============= SECURITY & HARDENING =============
security_ssh_harden(){
  echo "=== SSH HARDENING ==="
  SSHD_CONFIG="/etc/ssh/sshd_config"
  
  if [ ! -f "$SSHD_CONFIG" ]; then
    echo "sshd_config not found."
    return
  fi
  
  echo "Current SSH port:"
  grep "^Port" "$SSHD_CONFIG" || echo "Default (22)"
  echo ""
  
  read -rp "1) Change SSH port\n2) Disable root login\n3) Disable password auth\n4) Apply all\nChoice: " choice
  
  case "$choice" in
    1)
      read -rp "New SSH port: " new_port
      if [[ "$new_port" =~ ^[0-9]+$ ]]; then
        sed -i.bak "s/^#*Port .*/Port $new_port/" "$SSHD_CONFIG"
        echo "✅ SSH port changed to $new_port"
        log "SSH port changed to $new_port"
      fi
      ;;
    2)
      sed -i.bak "s/^#*PermitRootLogin .*/PermitRootLogin no/" "$SSHD_CONFIG"
      echo "✅ Root login disabled"
      ;;
    3)
      sed -i.bak "s/^#*PasswordAuthentication .*/PasswordAuthentication no/" "$SSHD_CONFIG"
      echo "✅ Password authentication disabled"
      ;;
    4)
      read -rp "New SSH port (default 2222): " new_port
      new_port=${new_port:-2222}
      sed -i.bak \
        -e "s/^#*Port .*/Port $new_port/" \
        -e "s/^#*PermitRootLogin .*/PermitRootLogin no/" \
        -e "s/^#*PasswordAuthentication .*/PasswordAuthentication no/" \
        "$SSHD_CONFIG"
      echo "✅ All hardening applied"
      ;;
  esac
  
  read -rp "Restart SSH service? (y/n): " ans
  [[ "$ans" =~ [Yy] ]] && systemctl restart sshd && echo "SSH restarted"
}

security_fail2ban(){
  echo "=== FAIL2BAN MANAGEMENT ==="
  
  if ! command_exists fail2ban-client; then
    echo "Fail2Ban not installed."
    read -rp "Install now? (y/n): " ans
    if [[ "$ans" =~ [Yy] ]]; then
      apt update && apt install -y fail2ban
      systemctl enable fail2ban
      systemctl start fail2ban
      echo "✅ Fail2Ban installed and started"
    fi
    return
  fi
  
  echo "1) Status"
  echo "2) Banned IPs"
  echo "3) Unban IP"
  read -rp "Choice: " choice
  
  case "$choice" in
    1) fail2ban-client status ;;
    2) fail2ban-client status sshd 2>/dev/null || echo "No bans" ;;
    3)
      read -rp "IP to unban: " ip
      fail2ban-client set sshd unbanip "$ip" && echo "✅ Unbanned $ip"
      ;;
  esac
}

security_ssl(){
  echo "=== SSL CERTIFICATE MANAGEMENT ==="
  
  if ! command_exists certbot; then
    echo "Certbot not installed."
    read -rp "Install now? (y/n): " ans
    if [[ "$ans" =~ [Yy] ]]; then
      apt update && apt install -y certbot python3-certbot-nginx
      echo "✅ Certbot installed"
    fi
    return
  fi
  
  echo "1) List certificates"
  echo "2) Get new certificate"
  echo "3) Renew certificates"
  echo "4) Check expiry dates"
  read -rp "Choice: " choice
  
  case "$choice" in
    1) certbot certificates ;;
    2)
      read -rp "Domain name: " domain
      certbot --nginx -d "$domain"
      ;;
    3) certbot renew ;;
    4) certbot certificates | grep -E "Expiry|Domains" ;;
  esac
}

security_updates(){
  echo "=== AUTOMATIC SECURITY UPDATES ==="
  
  if ! dpkg -l | grep -q unattended-upgrades; then
    echo "unattended-upgrades not installed."
    read -rp "Install? (y/n): " ans
    if [[ "$ans" =~ [Yy] ]]; then
      apt update && apt install -y unattended-upgrades
      dpkg-reconfigure -plow unattended-upgrades
      echo "✅ Automatic updates configured"
    fi
  else
    echo "Status: Installed"
    systemctl status unattended-upgrades --no-pager
  fi
}

# ============= MONITORING & ALERTS =============
monitor_resources(){
  echo "=== RESOURCE MONITORING ==="
  
  echo "--- CPU Usage ---"
  top -bn1 | grep "Cpu(s)" | awk '{print "CPU: " $2 "%"}'
  echo ""
  
  echo "--- Memory Usage ---"
  free -h | grep -E "^Mem"
  echo ""
  
  echo "--- Disk Usage ---"
  df -h | grep -vE "^Filesystem|tmpfs|cdrom"
  echo ""
  
  echo "--- Load Average ---"
  uptime
  echo ""
  
  echo "--- Top Processes ---"
  ps aux --sort=-%mem | head -n 6
}

monitor_alerts(){
  echo "=== ALERT SETUP ==="
  echo "Configure alerts for:"
  echo "1) Disk usage > 90%"
  echo "2) Memory usage > 90%"
  echo "3) Service down"
  echo ""
  read -rp "Email for alerts: " email
  
  if [ -z "$email" ]; then
    echo "No email provided."
    return
  fi
  
  mkdir -p /etc/bdrman
  cat > /etc/bdrman/monitor.sh << 'EOF'
#!/bin/bash
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
MEM_USAGE=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')

if [ "$DISK_USAGE" -gt 90 ]; then
  echo "⚠️ Disk usage: ${DISK_USAGE}%" | mail -s "ALERT: High Disk Usage" EMAIL_PLACEHOLDER
fi

if [ "$MEM_USAGE" -gt 90 ]; then
  echo "⚠️ Memory usage: ${MEM_USAGE}%" | mail -s "ALERT: High Memory Usage" EMAIL_PLACEHOLDER
fi
EOF
  
  sed -i "s/EMAIL_PLACEHOLDER/$email/g" /etc/bdrman/monitor.sh
  chmod +x /etc/bdrman/monitor.sh
  
  # Add to cron
  (crontab -l 2>/dev/null | grep -v "monitor.sh"; echo "*/15 * * * * /etc/bdrman/monitor.sh") | crontab -
  
  echo "✅ Monitoring alerts configured (checks every 15 minutes)"
  log_success "Alert monitoring configured for $email"
}

monitor_uptime(){
  echo "=== UPTIME MONITORING ==="
  echo "System uptime:"
  uptime
  echo ""
  echo "Service status:"
  systemctl is-active docker 2>/dev/null && echo "✅ Docker: Running" || echo "❌ Docker: Not running"
  systemctl is-active nginx 2>/dev/null && echo "✅ Nginx: Running" || echo "❌ Nginx: Not active"
  systemctl is-active wg-quick@wg0 2>/dev/null && echo "✅ WireGuard: Running" || echo "❌ WireGuard: Not active"
}

# ============= DATABASE MANAGEMENT =============
db_menu_main(){
  echo "=== DATABASE MANAGEMENT ==="
  echo "1) PostgreSQL"
  echo "2) MySQL/MariaDB"
  read -rp "Choice: " choice
  
  case "$choice" in
    1) db_postgresql ;;
    2) db_mysql ;;
  esac
}

db_postgresql(){
  echo "=== PostgreSQL Management ==="
  
  if ! command_exists psql; then
    echo "PostgreSQL not installed."
    return
  fi
  
  echo "1) List databases"
  echo "2) Create database"
  echo "3) Create user"
  echo "4) Backup database"
  echo "5) Restore database"
  read -rp "Choice: " choice
  
  case "$choice" in
    1) sudo -u postgres psql -c '\l' ;;
    2)
      read -rp "Database name: " dbname
      sudo -u postgres createdb "$dbname" && echo "✅ Database created"
      ;;
    3)
      read -rp "Username: " username
      read -rsp "Password: " password
      echo ""
      sudo -u postgres psql -c "CREATE USER $username WITH PASSWORD '$password';"
      ;;
    4)
      read -rp "Database name: " dbname
      sudo -u postgres pg_dump "$dbname" > "$BACKUP_DIR/${dbname}_$(date +%Y%m%d).sql"
      echo "✅ Backup saved to $BACKUP_DIR"
      ;;
    5)
      read -rp "Database name: " dbname
      read -rp "SQL file path: " sqlfile
      sudo -u postgres psql "$dbname" < "$sqlfile"
      ;;
  esac
}

db_mysql(){
  echo "=== MySQL/MariaDB Management ==="
  
  if ! command_exists mysql; then
    echo "MySQL not installed."
    return
  fi
  
  echo "1) List databases"
  echo "2) Create database"
  echo "3) Backup database"
  read -rp "Choice: " choice
  
  case "$choice" in
    1) mysql -e "SHOW DATABASES;" ;;
    2)
      read -rp "Database name: " dbname
      mysql -e "CREATE DATABASE $dbname;"
      ;;
    3)
      read -rp "Database name: " dbname
      mysqldump "$dbname" > "$BACKUP_DIR/${dbname}_$(date +%Y%m%d).sql"
      echo "✅ Backup saved"
      ;;
  esac
}

# ============= NGINX MANAGEMENT =============
nginx_manage(){
  echo "=== NGINX MANAGEMENT ==="
  
  if ! command_exists nginx; then
    echo "Nginx not installed."
    return
  fi
  
  echo "1) Status"
  echo "2) Test configuration"
  echo "3) Reload"
  echo "4) Restart"
  echo "5) View error log"
  echo "6) List sites"
  read -rp "Choice: " choice
  
  case "$choice" in
    1) systemctl status nginx --no-pager ;;
    2) nginx -t ;;
    3) nginx -s reload && echo "✅ Reloaded" ;;
    4) systemctl restart nginx && echo "✅ Restarted" ;;
    5) tail -n 50 /var/log/nginx/error.log ;;
    6) ls -la /etc/nginx/sites-enabled/ ;;
  esac
}

# ============= USER MANAGEMENT =============
user_manage(){
  echo "=== USER MANAGEMENT ==="
  echo "1) List users"
  echo "2) Add user"
  echo "3) Delete user"
  echo "4) Add user to sudo"
  echo "5) List SSH keys"
  echo "6) Add SSH key"
  read -rp "Choice: " choice
  
  case "$choice" in
    1) cat /etc/passwd | grep -E "/bin/bash|/bin/sh" | cut -d: -f1 ;;
    2)
      read -rp "Username: " username
      adduser "$username" && echo "✅ User created"
      log "User created: $username"
      ;;
    3)
      read -rp "Username to delete: " username
      read -rp "⚠️  Delete home dir too? (y/n): " delhome
      if [[ "$delhome" =~ [Yy] ]]; then
        deluser --remove-home "$username"
      else
        deluser "$username"
      fi
      echo "✅ User deleted"
      ;;
    4)
      read -rp "Username: " username
      usermod -aG sudo "$username" && echo "✅ Added to sudo group"
      ;;
    5)
      read -rp "Username: " username
      [ -f "/home/$username/.ssh/authorized_keys" ] && cat "/home/$username/.ssh/authorized_keys" || echo "No keys found"
      ;;
    6)
      read -rp "Username: " username
      read -rp "Paste SSH public key: " sshkey
      mkdir -p "/home/$username/.ssh"
      echo "$sshkey" >> "/home/$username/.ssh/authorized_keys"
      chown -R "$username:$username" "/home/$username/.ssh"
      chmod 700 "/home/$username/.ssh"
      chmod 600 "/home/$username/.ssh/authorized_keys"
      echo "✅ SSH key added"
      ;;
  esac
}

# ============= NETWORK DIAGNOSTICS =============
network_diag(){
  echo "=== NETWORK DIAGNOSTICS ==="
  echo "1) Open ports"
  echo "2) Active connections"
  echo "3) Network interfaces"
  echo "4) DNS test"
  echo "5) Ping test"
  echo "6) Route table"
  read -rp "Choice: " choice
  
  case "$choice" in
    1) ss -tuln | grep LISTEN ;;
    2) ss -tunap | grep ESTAB ;;
    3) ip addr show ;;
    4)
      read -rp "Domain to test: " domain
      nslookup "$domain"
      ;;
    5)
      read -rp "Host to ping: " host
      ping -c 4 "$host"
      ;;
    6) ip route show ;;
  esac
}

# ============= PERFORMANCE & CLEANUP =============
perf_optimize(){
  echo "=== PERFORMANCE OPTIMIZATION ==="
  echo "1) Clean package cache"
  echo "2) Clean old logs"
  echo "3) Docker cleanup"
  echo "4) Check swap"
  echo "5) Optimize swap"
  read -rp "Choice: " choice
  
  case "$choice" in
    1)
      apt clean && apt autoclean && apt autoremove -y
      echo "✅ Package cache cleaned"
      ;;
    2)
      journalctl --vacuum-time=7d
      find /var/log -type f -name "*.log.*" -mtime +30 -delete
      echo "✅ Old logs cleaned"
      ;;
    3)
      docker system prune -af
      docker volume prune -f
      echo "✅ Docker cleaned"
      ;;
    4)
      free -h
      swapon --show
      ;;
    5)
      echo "Current swappiness:"
      cat /proc/sys/vm/swappiness
      read -rp "New swappiness value (10-60, recommended 10): " swapval
      sysctl vm.swappiness="$swapval"
      echo "vm.swappiness=$swapval" >> /etc/sysctl.conf
      echo "✅ Swappiness set to $swapval"
      ;;
  esac
}

# ============= SYSTEM SNAPSHOT & RESTORE =============
snapshot_create(){
  echo "=== CREATE SYSTEM SNAPSHOT ==="
  
  if ! command_exists rsync; then
    echo "rsync not installed. Installing..."
    apt update && apt install -y rsync
  fi
  
  SNAPSHOT_DIR="/var/snapshots"
  mkdir -p "$SNAPSHOT_DIR"
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  SNAPSHOT_NAME="snapshot_$TIMESTAMP"
  
  echo "Creating snapshot: $SNAPSHOT_NAME"
  echo "This may take several minutes..."
  
  rsync -aAXv --delete \
    --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/var/snapshots/*","/var/backups/*"} \
    / "$SNAPSHOT_DIR/$SNAPSHOT_NAME/" 2>&1 | tee -a "$LOGFILE" | tail -n 20
  
  if [ $? -eq 0 ]; then
    echo "✅ Snapshot created: $SNAPSHOT_DIR/$SNAPSHOT_NAME"
    log_success "System snapshot created: $SNAPSHOT_NAME"
    
    # Create snapshot info file
    cat > "$SNAPSHOT_DIR/$SNAPSHOT_NAME/snapshot_info.txt" << EOF
Snapshot created: $(date)
Hostname: $(hostname)
Kernel: $(uname -r)
Disk usage: $(df -h / | tail -1)
EOF
  else
    echo "❌ Snapshot creation failed!"
    log_error "Snapshot creation failed"
  fi
}

snapshot_list(){
  echo "=== AVAILABLE SNAPSHOTS ==="
  SNAPSHOT_DIR="/var/snapshots"
  
  if [ ! -d "$SNAPSHOT_DIR" ]; then
    echo "No snapshots directory found."
    return
  fi
  
  echo ""
  for snapshot in "$SNAPSHOT_DIR"/snapshot_*; do
    if [ -d "$snapshot" ]; then
      snapshot_name=$(basename "$snapshot")
      size=$(du -sh "$snapshot" 2>/dev/null | cut -f1)
      echo "📸 $snapshot_name (Size: $size)"
      
      if [ -f "$snapshot/snapshot_info.txt" ]; then
        cat "$snapshot/snapshot_info.txt" | sed 's/^/   /'
      fi
      echo ""
    fi
  done
}

snapshot_restore(){
  echo "=== RESTORE FROM SNAPSHOT ==="
  snapshot_list
  echo ""
  
  read -rp "⚠️  WARNING: This will restore your entire system! Enter snapshot name: " snapshot_name
  
  SNAPSHOT_DIR="/var/snapshots"
  SNAPSHOT_PATH="$SNAPSHOT_DIR/$snapshot_name"
  
  if [ ! -d "$SNAPSHOT_PATH" ]; then
    echo "❌ Snapshot not found: $snapshot_name"
    return
  fi
  
  echo ""
  echo "🔴 CRITICAL WARNING 🔴"
  echo "This will OVERWRITE your current system with the snapshot!"
  echo "Snapshot: $snapshot_name"
  read -rp "Type 'YES I UNDERSTAND' to continue: " confirm
  
  if [ "$confirm" != "YES I UNDERSTAND" ]; then
    echo "Restore cancelled."
    return
  fi
  
  echo "Starting system restore..."
  rsync -aAXv --delete \
    --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/var/snapshots/*"} \
    "$SNAPSHOT_PATH/" / 2>&1 | tee -a "$LOGFILE" | tail -n 20
  
  if [ $? -eq 0 ]; then
    echo "✅ System restored successfully!"
    echo "⚠️  REBOOT REQUIRED! Reboot now? (y/n)"
    read -rp "Choice: " reboot_choice
    if [[ "$reboot_choice" =~ [Yy] ]]; then
      log "System restored from snapshot: $snapshot_name - REBOOTING"
      reboot
    fi
  else
    echo "❌ Restore failed!"
    log_error "Snapshot restore failed: $snapshot_name"
  fi
}

snapshot_delete(){
  echo "=== DELETE SNAPSHOT ==="
  snapshot_list
  echo ""
  
  read -rp "Snapshot name to delete: " snapshot_name
  SNAPSHOT_DIR="/var/snapshots"
  SNAPSHOT_PATH="$SNAPSHOT_DIR/$snapshot_name"
  
  if [ ! -d "$SNAPSHOT_PATH" ]; then
    echo "❌ Snapshot not found."
    return
  fi
  
  read -rp "⚠️  Delete $snapshot_name? (yes/no): " confirm
  if [ "$confirm" = "yes" ]; then
    rm -rf "$SNAPSHOT_PATH"
    echo "✅ Snapshot deleted"
    log "Snapshot deleted: $snapshot_name"
  fi
}

# ============= INCIDENT RESPONSE & RECOVERY =============
incident_emergency_mode(){
  echo "=== 🚨 EMERGENCY MODE 🚨 ==="
  echo ""
  echo "This will:"
  echo "1) Stop all non-critical services"
  echo "2) Enable minimal firewall rules"
  echo "3) Create emergency backup"
  echo "4) Enable verbose logging"
  echo ""
  
  read -rp "Enter EMERGENCY MODE? (yes/no): " confirm
  [ "$confirm" != "yes" ] && return
  
  log "EMERGENCY MODE ACTIVATED"
  
  # Create emergency backup
  echo "Creating emergency backup..."
  backup_create
  
  # Stop non-critical services
  echo "Stopping non-critical services..."
  systemctl stop nginx 2>/dev/null
  systemctl stop apache2 2>/dev/null
  docker stop $(docker ps -q) 2>/dev/null
  
  # Enable strict firewall
  echo "Enabling strict firewall..."
  ufw --force enable
  ufw default deny incoming
  ufw allow 22/tcp
  ufw allow from 127.0.0.1
  
  echo "✅ EMERGENCY MODE ACTIVE"
  echo "System is now in minimal state."
  echo "Only SSH (port 22) is accessible."
  log_success "Emergency mode activated"
}

incident_rollback(){
  echo "=== QUICK ROLLBACK ==="
  echo ""
  echo "Available rollback options:"
  echo "1) Restore last backup"
  echo "2) Restore last snapshot"
  echo "3) Restart all services"
  echo "4) Reset firewall to defaults"
  read -rp "Choice: " choice
  
  case "$choice" in
    1)
      echo "Finding latest backup..."
      LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | head -1)
      if [ -n "$LATEST_BACKUP" ]; then
        echo "Restoring: $LATEST_BACKUP"
        tar -xzf "$LATEST_BACKUP" -C / && echo "✅ Backup restored"
        log "Rollback: restored backup $LATEST_BACKUP"
      else
        echo "No backups found."
      fi
      ;;
    2)
      LATEST_SNAPSHOT=$(ls -td /var/snapshots/snapshot_* 2>/dev/null | head -1)
      if [ -n "$LATEST_SNAPSHOT" ]; then
        echo "Latest snapshot: $(basename $LATEST_SNAPSHOT)"
        read -rp "Restore this snapshot? (yes/no): " confirm
        [ "$confirm" = "yes" ] && snapshot_restore
      else
        echo "No snapshots found."
      fi
      ;;
    3)
      echo "Restarting all services..."
      systemctl restart docker nginx wg-quick@wg0 2>/dev/null
      echo "✅ Services restarted"
      log "Rollback: all services restarted"
      ;;
    4)
      ufw --force reset
      ufw default deny incoming
      ufw default allow outgoing
      ufw allow 22/tcp
      ufw allow 80/tcp
      ufw allow 443/tcp
      ufw --force enable
      echo "✅ Firewall reset to defaults"
      ;;
  esac
}

incident_health_check(){
  echo "=== SYSTEM HEALTH CHECK ==="
  
  ISSUES=0
  
  echo ""
  echo "Checking critical services..."
  
  # Check SSH
  if systemctl is-active --quiet sshd || systemctl is-active --quiet ssh; then
    echo "✅ SSH is running"
  else
    echo "❌ SSH is DOWN!"
    ((ISSUES++))
  fi
  
  # Check Docker
  if systemctl is-active --quiet docker; then
    echo "✅ Docker is running"
  else
    echo "⚠️  Docker is not running"
  fi
  
  # Check Nginx
  if systemctl is-active --quiet nginx; then
    echo "✅ Nginx is running"
  else
    echo "⚠️  Nginx is not running"
  fi
  
  # Check disk space
  DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
  if [ "$DISK_USAGE" -lt 90 ]; then
    echo "✅ Disk usage: ${DISK_USAGE}%"
  else
    echo "❌ Disk usage critical: ${DISK_USAGE}%"
    ((ISSUES++))
  fi
  
  # Check memory
  MEM_USAGE=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')
  if [ "$MEM_USAGE" -lt 90 ]; then
    echo "✅ Memory usage: ${MEM_USAGE}%"
  else
    echo "⚠️  High memory usage: ${MEM_USAGE}%"
  fi
  
  # Check failed services
  FAILED=$(systemctl --failed --no-pager --no-legend | wc -l)
  if [ "$FAILED" -eq 0 ]; then
    echo "✅ No failed services"
  else
    echo "❌ Failed services: $FAILED"
    systemctl --failed --no-pager
    ((ISSUES++))
  fi
  
  echo ""
  if [ "$ISSUES" -eq 0 ]; then
    echo "🟢 System health: GOOD"
  else
    echo "🔴 System health: $ISSUES critical issues found!"
  fi
}

incident_auto_recovery(){
  echo "=== SETUP AUTO-RECOVERY ==="
  
  cat > /etc/bdrman/auto_recovery.sh << 'EOF'
#!/bin/bash
# Auto-recovery script for BDRman

LOGFILE="/var/log/bdrman.log"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - AUTO-RECOVERY: $*" >> "$LOGFILE"
}

# Check and restart Docker
if ! systemctl is-active --quiet docker; then
  log "Docker down, restarting..."
  systemctl restart docker
fi

# Check and restart Nginx
if ! systemctl is-active --quiet nginx; then
  log "Nginx down, restarting..."
  systemctl restart nginx
fi

# Check and restart WireGuard
if ! systemctl is-active --quiet wg-quick@wg0; then
  log "WireGuard down, restarting..."
  systemctl restart wg-quick@wg0
fi

# Check disk space
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 95 ]; then
  log "CRITICAL: Disk usage $DISK_USAGE% - cleaning Docker"
  docker system prune -af 2>&1 | tail -5 >> "$LOGFILE"
fi
EOF

  chmod +x /etc/bdrman/auto_recovery.sh
  
  # Add to cron (every 5 minutes)
  (crontab -l 2>/dev/null | grep -v "auto_recovery.sh"; echo "*/5 * * * * /etc/bdrman/auto_recovery.sh") | crontab -
  
  echo "✅ Auto-recovery configured (runs every 5 minutes)"
  log_success "Auto-recovery script installed"
}

# ============= CONFIGURATION AS CODE =============
config_export(){
  echo "=== EXPORT CONFIGURATION ==="
  
  CONFIG_EXPORT_DIR="$BACKUP_DIR/config_export_$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$CONFIG_EXPORT_DIR"
  
  echo "Exporting system configuration..."
  
  # Export UFW rules
  if command_exists ufw; then
    ufw status verbose > "$CONFIG_EXPORT_DIR/ufw_rules.txt"
  fi
  
  # Export crontab
  crontab -l > "$CONFIG_EXPORT_DIR/crontab.txt" 2>/dev/null || echo "No crontab"
  
  # Export network config
  ip addr show > "$CONFIG_EXPORT_DIR/network_interfaces.txt"
  ip route show > "$CONFIG_EXPORT_DIR/routes.txt"
  
  # Export Docker containers
  if command_exists docker; then
    docker ps -a --format "{{.Names}}\t{{.Image}}\t{{.Ports}}" > "$CONFIG_EXPORT_DIR/docker_containers.txt"
  fi
  
  # Export installed packages
  dpkg -l > "$CONFIG_EXPORT_DIR/installed_packages.txt"
  
  # Export systemd services
  systemctl list-unit-files --type=service --state=enabled > "$CONFIG_EXPORT_DIR/enabled_services.txt"
  
  # Create YAML manifest
  cat > "$CONFIG_EXPORT_DIR/manifest.yaml" << EOF
# BDRman Configuration Export
# Generated: $(date)
# Hostname: $(hostname)

system:
  hostname: $(hostname)
  kernel: $(uname -r)
  os: $(cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2)

networking:
  interfaces: $(ip addr show | grep "^[0-9]" | cut -d: -f2 | tr '\n' ',' | sed 's/,$//')

services:
  docker: $(systemctl is-active docker 2>/dev/null || echo "not-installed")
  nginx: $(systemctl is-active nginx 2>/dev/null || echo "not-installed")
  wireguard: $(systemctl is-active wg-quick@wg0 2>/dev/null || echo "not-installed")

firewall:
  status: $(ufw status | head -1)
EOF
  
  # Create archive
  tar -czf "$CONFIG_EXPORT_DIR.tar.gz" -C "$BACKUP_DIR" "$(basename $CONFIG_EXPORT_DIR)"
  
  echo "✅ Configuration exported to: $CONFIG_EXPORT_DIR.tar.gz"
  log_success "Configuration exported"
  
  echo ""
  echo "Export includes:"
  echo "  - Firewall rules"
  echo "  - Cron jobs"
  echo "  - Network configuration"
  echo "  - Docker containers"
  echo "  - Installed packages"
  echo "  - System services"
  echo "  - YAML manifest"
}

config_import(){
  echo "=== IMPORT CONFIGURATION ==="
  echo ""
  
  ls -lh "$BACKUP_DIR"/config_export_*.tar.gz 2>/dev/null || echo "No exports found."
  echo ""
  
  read -rp "Config archive to import: " archive_name
  ARCHIVE_PATH="$BACKUP_DIR/$archive_name"
  
  if [ ! -f "$ARCHIVE_PATH" ]; then
    echo "❌ Archive not found."
    return
  fi
  
  TEMP_DIR="/tmp/config_import_$$"
  mkdir -p "$TEMP_DIR"
  tar -xzf "$ARCHIVE_PATH" -C "$TEMP_DIR"
  
  CONFIG_DIR=$(find "$TEMP_DIR" -type d -name "config_export_*" | head -1)
  
  if [ -z "$CONFIG_DIR" ]; then
    echo "❌ Invalid archive."
    rm -rf "$TEMP_DIR"
    return
  fi
  
  echo "Found configuration from: $(basename $CONFIG_DIR)"
  echo ""
  echo "Available imports:"
  echo "1) Firewall rules"
  echo "2) Cron jobs"
  echo "3) Show manifest"
  echo "4) All (interactive)"
  read -rp "Choice: " choice
  
  case "$choice" in
    1)
      if [ -f "$CONFIG_DIR/ufw_rules.txt" ]; then
        echo "Current UFW rules will be replaced."
        read -rp "Continue? (y/n): " confirm
        if [[ "$confirm" =~ [Yy] ]]; then
          # This is informational only - manual import recommended
          cat "$CONFIG_DIR/ufw_rules.txt"
          echo ""
          echo "ℹ️  Review rules above and apply manually for safety."
        fi
      fi
      ;;
    2)
      if [ -f "$CONFIG_DIR/crontab.txt" ]; then
        echo "Importing cron jobs..."
        cat "$CONFIG_DIR/crontab.txt"
        read -rp "Apply these cron jobs? (y/n): " confirm
        if [[ "$confirm" =~ [Yy] ]]; then
          crontab "$CONFIG_DIR/crontab.txt"
          echo "✅ Cron jobs imported"
        fi
      fi
      ;;
    3)
      if [ -f "$CONFIG_DIR/manifest.yaml" ]; then
        cat "$CONFIG_DIR/manifest.yaml"
      fi
      ;;
    4)
      echo "Interactive import not yet implemented."
      echo "Review files in: $CONFIG_DIR"
      ;;
  esac
  
  rm -rf "$TEMP_DIR"
}

config_template(){
  echo "=== CONFIGURATION TEMPLATES ==="
  echo ""
  echo "1) Secure Server Template"
  echo "2) Web Server Template"
  echo "3) VPN Server Template"
  echo "4) Docker Host Template"
  read -rp "Choose template: " choice
  
  case "$choice" in
    1)
      echo "Applying Secure Server template..."
      # SSH hardening
      sed -i.bak \
        -e "s/^#*PermitRootLogin .*/PermitRootLogin no/" \
        -e "s/^#*PasswordAuthentication .*/PasswordAuthentication no/" \
        /etc/ssh/sshd_config
      
      # Firewall
      ufw --force enable
      ufw default deny incoming
      ufw default allow outgoing
      ufw allow 22/tcp
      
      # Install fail2ban
      apt install -y fail2ban
      systemctl enable fail2ban
      
      echo "✅ Secure Server template applied"
      ;;
    2)
      echo "Web Server template - ports 80, 443 opened"
      ufw allow 80/tcp
      ufw allow 443/tcp
      echo "✅ Web Server template applied"
      ;;
    3)
      echo "VPN Server template - WireGuard port opened"
      ufw allow 51820/udp
      echo "✅ VPN Server template applied"
      ;;
    4)
      echo "Docker Host template - Docker configured"
      # Docker daemon config for security
      mkdir -p /etc/docker
      cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
      systemctl restart docker
      echo "✅ Docker Host template applied"
      ;;
  esac
}

# ============= ADVANCED FIREWALL FEATURES =============
firewall_advanced(){
  echo "=== ADVANCED FIREWALL ==="
  echo ""
  echo "1) Port Knocking Setup"
  echo "2) Rate Limiting"
  echo "3) GeoIP Blocking (coming soon)"
  echo "4) DDoS Protection Rules"
  echo "5) Show Active Blocks"
  read -rp "Choice: " choice
  
  case "$choice" in
    1)
      echo "=== PORT KNOCKING SETUP ==="
      if ! command_exists knockd; then
        echo "knockd not installed."
        read -rp "Install? (y/n): " ans
        if [[ "$ans" =~ [Yy] ]]; then
          apt update && apt install -y knockd
        else
          return
        fi
      fi
      
      echo "Port knocking allows SSH access only after knocking specific ports."
      read -rp "SSH port (default 22): " ssh_port
      ssh_port=${ssh_port:-22}
      
      cat > /etc/knockd.conf << EOF
[options]
        logfile = /var/log/knockd.log

[openSSH]
        sequence    = 7000,8000,9000
        seq_timeout = 5
        command     = /sbin/iptables -I INPUT -s %IP% -p tcp --dport $ssh_port -j ACCEPT
        tcpflags    = syn

[closeSSH]
        sequence    = 9000,8000,7000
        seq_timeout = 5
        command     = /sbin/iptables -D INPUT -s %IP% -p tcp --dport $ssh_port -j ACCEPT
        tcpflags    = syn
EOF
      
      systemctl enable knockd
      systemctl start knockd
      
      echo "✅ Port knocking configured"
      echo "Knock sequence: 7000, 8000, 9000"
      echo "Close sequence: 9000, 8000, 7000"
      echo ""
      echo "Example: knock <server_ip> 7000 8000 9000"
      ;;
      
    2)
      echo "=== RATE LIMITING ==="
      echo "Limiting SSH connections to prevent brute force..."
      
      ufw limit 22/tcp comment 'Rate limit SSH'
      
      # Additional iptables rules for more aggressive rate limiting
      iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set
      iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP
      
      echo "✅ Rate limiting applied (max 4 connections per minute)"
      ;;
      
    3)
      echo "GeoIP blocking - Coming soon"
      echo "Requires geoipupdate package"
      ;;
      
    4)
      echo "=== DDoS PROTECTION ==="
      echo "Applying DDoS mitigation rules..."
      
      # SYN flood protection
      iptables -A INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT
      iptables -A INPUT -p tcp --syn -j DROP
      
      # Ping flood protection
      iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT
      iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
      
      # Port scanning protection
      iptables -N port-scanning
      iptables -A port-scanning -p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit 1/s --limit-burst 2 -j RETURN
      iptables -A port-scanning -j DROP
      
      echo "✅ DDoS protection rules applied"
      echo "ℹ️  These rules are not persistent. Consider using iptables-persistent."
      ;;
      
    5)
      echo "=== ACTIVE FIREWALL BLOCKS ==="
      echo ""
      echo "UFW denied connections (recent):"
      grep "UFW BLOCK" /var/log/ufw.log 2>/dev/null | tail -20 || echo "No blocks found"
      echo ""
      echo "iptables DROP rules:"
      iptables -L INPUT -v -n | grep DROP
      ;;
  esac
}

# ============= TELEGRAM BOT INTEGRATION =============
telegram_setup(){
  echo "=== TELEGRAM BOT SETUP ==="
  echo ""
  echo "To use Telegram bot, you need:"
  echo "1) Bot token from @BotFather"
  echo "2) Your chat ID (send /start to @userinfobot to get it)"
  echo ""
  
  read -rp "Bot Token: " bot_token
  read -rp "Chat ID: " chat_id
  
  if [ -z "$bot_token" ] || [ -z "$chat_id" ]; then
    echo "Both token and chat ID are required."
    return
  fi
  
  # Save config
  mkdir -p /etc/bdrman
  cat > /etc/bdrman/telegram.conf << EOF
BOT_TOKEN="$bot_token"
CHAT_ID="$chat_id"
EOF
  
  chmod 600 /etc/bdrman/telegram.conf
  
  # Create notification function
  cat > /usr/local/bin/bdrman-telegram << 'EOF'
#!/bin/bash
if [ ! -f /etc/bdrman/telegram.conf ]; then
  echo "Telegram not configured"
  exit 1
fi

source /etc/bdrman/telegram.conf

MESSAGE="$1"
HOSTNAME=$(hostname)

curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="${CHAT_ID}" \
  -d text="🖥️ *${HOSTNAME}*%0A%0A${MESSAGE}" \
  -d parse_mode="Markdown" > /dev/null

EOF
  
  chmod +x /usr/local/bin/bdrman-telegram
  
  # Create weekly report script
  telegram_create_weekly_report
  
  # Setup cron for weekly report (Monday at 12:00)
  (crontab -l 2>/dev/null | grep -v "telegram_weekly_report.sh"; echo "0 12 * * 1 /etc/bdrman/telegram_weekly_report.sh") | crontab -
  
  # Test notification
  /usr/local/bin/bdrman-telegram "✅ Telegram bot configured!%0A%0A📅 Weekly reports: Monday at 12:00%0A💬 Commands: Send /help to see all available commands"
  
  echo "✅ Telegram bot configured"
  echo "✅ Weekly reports enabled (Monday at 12:00)"
  echo ""
  echo "Usage: bdrman-telegram \"Your message\""
  log_success "Telegram bot configured"
}

telegram_create_weekly_report(){
  cat > /etc/bdrman/telegram_weekly_report.sh << 'EOFSCRIPT'
#!/bin/bash
if [ ! -f /etc/bdrman/telegram.conf ]; then
  exit 1
fi

source /etc/bdrman/telegram.conf

HOSTNAME=$(hostname)
UPTIME=$(uptime -p)
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}')
DISK_USED=$(df -h / | tail -1 | awk '{print $3}')
DISK_TOTAL=$(df -h / | tail -1 | awk '{print $2}')
MEM_USAGE=$(free -h | grep Mem | awk '{print $3"/"$2}')
MEM_PERCENT=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')
LOAD=$(uptime | awk -F'load average:' '{print $2}')
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')

DOCKER_RUNNING=$(docker ps --format "{{.Names}}" 2>/dev/null | wc -l)
DOCKER_TOTAL=$(docker ps -a --format "{{.Names}}" 2>/dev/null | wc -l)
DOCKER_STOPPED=$(docker ps -a --filter "status=exited" --format "{{.Names}}" 2>/dev/null | wc -l)

# Failed services
FAILED_COUNT=$(systemctl --failed --no-pager --no-legend 2>/dev/null | wc -l)
if [ "$FAILED_COUNT" -gt 0 ]; then
  FAILED_SERVICES=$(systemctl --failed --no-pager --no-legend 2>/dev/null | cut -d' ' -f2 | tr '\n' ',' | sed 's/,$//')
else
  FAILED_SERVICES="None"
fi

# Disk warnings
DISK_NUM=$(echo $DISK_USAGE | sed 's/%//')
if [ "$DISK_NUM" -ge 90 ]; then
  DISK_ICON="🔴"
elif [ "$DISK_NUM" -ge 80 ]; then
  DISK_ICON="🟡"
else
  DISK_ICON="🟢"
fi

# Memory warnings
if [ "$MEM_PERCENT" -ge 90 ]; then
  MEM_ICON="🔴"
elif [ "$MEM_PERCENT" -ge 80 ]; then
  MEM_ICON="🟡"
else
  MEM_ICON="🟢"
fi

REPORT="📊 *WEEKLY SYSTEM REPORT*%0A"
REPORT+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━%0A%0A"
REPORT+="🖥️ *Server:* \`${HOSTNAME}\`%0A"
REPORT+="📅 *Date:* $(date '+%Y-%m-%d %H:%M')%0A"
REPORT+="⏱️ *Uptime:* ${UPTIME}%0A%0A"

REPORT+="*💻 RESOURCES*%0A"
REPORT+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━%0A"
REPORT+="${DISK_ICON} *Disk:* ${DISK_USAGE} (${DISK_USED}/${DISK_TOTAL})%0A"
REPORT+="${MEM_ICON} *Memory:* ${MEM_PERCENT}%25 (${MEM_USAGE})%0A"
REPORT+="⚡ *CPU Usage:* ${CPU_USAGE}%0A"
REPORT+="📈 *Load Average:* ${LOAD}%0A%0A"

REPORT+="*🐳 DOCKER*%0A"
REPORT+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━%0A"
REPORT+="✅ Running: ${DOCKER_RUNNING}%0A"
REPORT+="⏸️ Stopped: ${DOCKER_STOPPED}%0A"
REPORT+="📦 Total: ${DOCKER_TOTAL}%0A%0A"

REPORT+="*⚙️ SERVICES STATUS*%0A"
REPORT+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━%0A"

# Check key services
if systemctl is-active --quiet docker 2>/dev/null; then
  REPORT+="✅ Docker%0A"
else
  REPORT+="❌ Docker (DOWN)%0A"
fi

if systemctl is-active --quiet nginx 2>/dev/null; then
  REPORT+="✅ Nginx%0A"
else
  REPORT+="⚠️ Nginx (not active)%0A"
fi

if systemctl is-active --quiet wg-quick@wg0 2>/dev/null; then
  REPORT+="✅ WireGuard%0A"
else
  REPORT+="⚠️ WireGuard (not active)%0A"
fi

if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
  REPORT+="✅ SSH%0A"
else
  REPORT+="❌ SSH (DOWN!)%0A"
fi

REPORT+="%0A"

if [ "$FAILED_COUNT" -gt 0 ]; then
  REPORT+="*❌ FAILED SERVICES*%0A"
  REPORT+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━%0A"
  REPORT+="Count: ${FAILED_COUNT}%0A"
  REPORT+="Services: ${FAILED_SERVICES}%0A%0A"
fi

# Top processes by memory
TOP_PROCS=$(ps aux --sort=-%mem | head -n 4 | tail -n 3 | awk '{print $11}' | tr '\n' ',' | sed 's/,$//')
REPORT+="*📊 TOP MEMORY USERS*%0A"
REPORT+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━%0A"
REPORT+="${TOP_PROCS}%0A%0A"

# Network info
IP_ADDR=$(hostname -I | awk '{print $1}')
REPORT+="*🌐 NETWORK*%0A"
REPORT+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━%0A"
REPORT+="IP: \`${IP_ADDR}\`%0A%0A"

REPORT+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━%0A"
REPORT+="Use /help to see bot commands"

curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="${CHAT_ID}" \
  -d text="$REPORT" \
  -d parse_mode="Markdown" > /dev/null
EOFSCRIPT
  
  chmod +x /etc/bdrman/telegram_weekly_report.sh
}

telegram_send(){
  echo "=== SEND TELEGRAM MESSAGE ==="
  
  if [ ! -f /etc/bdrman/telegram.conf ]; then
    echo "Telegram not configured. Run setup first."
    return
  fi
  
  read -rp "Message to send: " message
  
  if [ -n "$message" ]; then
    /usr/local/bin/bdrman-telegram "$message"
    echo "✅ Message sent"
  fi
}

telegram_test_report(){
  echo "=== SEND TEST WEEKLY REPORT ==="
  
  if [ ! -f /etc/bdrman/telegram_weekly_report.sh ]; then
    echo "Weekly report script not found. Run setup first."
    return
  fi
  
  echo "Sending test weekly report..."
  /etc/bdrman/telegram_weekly_report.sh
  echo "✅ Report sent! Check your Telegram"
}

telegram_bot_webhook(){
  echo "=== TELEGRAM BOT WEBHOOK SERVER ==="
  echo ""
  echo "This will start a webhook server to receive Telegram commands."
  echo "The bot will respond to:"
  echo "  /status - System status report"
  echo "  /vpn - Create VPN user"
  echo "  /restart - Restart services"
  echo "  /backup - Create backup"
  echo "  /snapshot - Create system snapshot"
  echo "  /health - Health check"
  echo "  /emergency - Emergency mode"
  echo "  /update - System update"
  echo "  /logs - View recent logs"
  echo "  /docker - Docker status"
  echo "  /firewall - Firewall status"
  echo "  /block - Block IP"
  echo "  /ssl - Get SSL certificate"
  echo "  /exec - Execute command"
  echo "  And more... Use /help to see all"
  echo ""
  
  if [ ! -f /etc/bdrman/telegram.conf ]; then
    echo "Telegram not configured. Run setup first."
    return
  fi
  
  source /etc/bdrman/telegram.conf
  
  # Install dependencies
  if ! command_exists python3; then
    echo "Installing Python3..."
    apt update && apt install -y python3 python3-pip
  fi
  
  pip3 install python-telegram-bot --upgrade 2>/dev/null || pip3 install python-telegram-bot
  
  # Create webhook server
  cat > /etc/bdrman/telegram_bot.py << 'EOFPYTHON'
#!/usr/bin/env python3
import os
import subprocess
import shlex
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

# Load config
config = {}
with open('/etc/bdrman/telegram.conf', 'r') as f:
    for line in f:
        if '=' in line and not line.startswith('#'):
            key, value = line.strip().split('=', 1)
            config[key] = value.strip('"')

BOT_TOKEN = config.get('BOT_TOKEN')
ALLOWED_CHAT_ID = config.get('CHAT_ID')

def run_command(cmd):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        return result.stdout if result.stdout else result.stderr
    except Exception as e:
        return f"Error: {str(e)}"

async def is_authorized(update: Update) -> bool:
    if str(update.effective_chat.id) != ALLOWED_CHAT_ID:
        await update.message.reply_text("⛔ Unauthorized")
        return False
    return True

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    await update.message.reply_text(
        "🤖 *BDRman Bot Active*\n\n"
        "Use /help to see available commands",
        parse_mode='Markdown'
    )

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    help_text = """
🤖 *BDRman Bot - Complete Command List*

📊 *MONITORING:*
/status - Full system status report
/health - System health check
/docker - Docker containers status
/containers - Detailed container list
/services - All system services
/logs - Recent system errors
/disk - Disk usage details
/memory - Memory usage
/uptime - System uptime
/network - Network information
/top - Top resource-consuming processes

🔧 *MANAGEMENT:*
/restart [service] - Restart service
  Examples: /restart docker
           /restart nginx
           /restart wireguard
           /restart all

/vpn <username> - Create VPN user
  Example: /vpn john

/backup - Create system backup
/snapshot - Create full system snapshot
/update - System update (apt)

🔥 *FIREWALL & SECURITY:*
/firewall - Firewall status
/block <ip> - Block IP address
  Example: /block 192.168.1.100

/ssl <domain> - Get SSL certificate
  Example: /ssl example.com

🚨 *EMERGENCY:*
/emergency - Activate emergency mode

⚡ *ADVANCED:*
/exec <command> - Execute shell command
  Example: /exec df -h
  ⚠️ Use with caution!

ℹ️ *INFO:*
/help - This help message
/about - About this bot
    """
    await update.message.reply_text(help_text, parse_mode='Markdown')

async def about(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    about_text = """
🤖 *BDRman Telegram Bot*

Version: 2.0
Author: Burak Darende

A complete server management system 
accessible via Telegram.

Features:
✅ Real-time monitoring
✅ Service management
✅ Automated alerts
✅ Backup & snapshots
✅ Security tools
✅ VPN management

GitHub: burakdarende/bdrman
    """
    await update.message.reply_text(about_text, parse_mode='Markdown')

async def status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    await update.message.reply_text("📊 Collecting system status...")
    
    hostname = run_command("hostname").strip()
    uptime = run_command("uptime -p").strip()
    disk = run_command("df -h / | tail -1 | awk '{print $5}'").strip()
    mem = run_command("free -h | grep Mem | awk '{print $3\"/\"$2}'").strip()
    load = run_command("uptime | awk -F'load average:' '{print $2}'").strip()
    
    docker_running = run_command("docker ps --format '{{.Names}}' 2>/dev/null | wc -l").strip()
    docker_total = run_command("docker ps -a --format '{{.Names}}' 2>/dev/null | wc -l").strip()
    
    # Check services
    services_status = ""
    for svc in ['docker', 'nginx', 'wg-quick@wg0']:
        status_cmd = f"systemctl is-active {svc} 2>/dev/null"
        if run_command(status_cmd).strip() == 'active':
            services_status += f"✅ {svc}\n"
        else:
            services_status += f"❌ {svc}\n"
    
    report = f"""
📊 *SYSTEM STATUS*

🖥️ *Server:* {hostname}
⏱️ *Uptime:* {uptime}

*Resources:*
💾 Disk: {disk}
🧠 Memory: {mem}
📈 Load: {load}

*Docker:*
🐳 Running: {docker_running}/{docker_total}

*Services:*
{services_status}
    """
    
    await update.message.reply_text(report, parse_mode='Markdown')

async def health_check(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    await update.message.reply_text("🏥 Running health check...")
    
    issues = 0
    report = "🏥 *HEALTH CHECK REPORT*\n\n"
    
    # Check SSH
    ssh_status = run_command("systemctl is-active sshd || systemctl is-active ssh").strip()
    if ssh_status == 'active':
        report += "✅ SSH is running\n"
    else:
        report += "❌ SSH is DOWN!\n"
        issues += 1
    
    # Check disk
    disk_usage = run_command("df / | tail -1 | awk '{print $5}' | sed 's/%//'").strip()
    if disk_usage and int(disk_usage) < 90:
        report += f"✅ Disk usage: {disk_usage}%\n"
    else:
        report += f"⚠️ Disk usage critical: {disk_usage}%\n"
        issues += 1
    
    # Check memory
    mem_usage = run_command("free | grep Mem | awk '{printf(\"%.0f\", $3/$2 * 100.0)}'").strip()
    if mem_usage and int(mem_usage) < 90:
        report += f"✅ Memory usage: {mem_usage}%\n"
    else:
        report += f"⚠️ High memory usage: {mem_usage}%\n"
    
    # Check failed services
    failed = run_command("systemctl --failed --no-pager --no-legend | wc -l").strip()
    if failed == '0':
        report += "✅ No failed services\n"
    else:
        report += f"❌ Failed services: {failed}\n"
        issues += 1
    
    report += f"\n*Summary:* "
    if issues == 0:
        report += "🟢 All systems healthy"
    else:
        report += f"🔴 {issues} critical issue(s) found"
    
    await update.message.reply_text(report, parse_mode='Markdown')

async def vpn_create(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    if len(context.args) == 0:
        await update.message.reply_text("Usage: /vpn <username>\nExample: /vpn john")
        return
    
    username = context.args[0]
    await update.message.reply_text(f"🔐 Creating VPN user: {username}...")
    
    # Check if wireguard-install.sh exists
    if os.path.exists("/usr/local/bin/wireguard-install.sh"):
        result = run_command(f"echo '{username}' | /usr/local/bin/wireguard-install.sh")
        await update.message.reply_text(f"✅ VPN user '{username}' created!\n\nCheck your server for the config file in /root/")
    else:
        await update.message.reply_text("❌ WireGuard installation script not found at /usr/local/bin/wireguard-install.sh")

async def restart_service(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    if len(context.args) == 0:
        await update.message.reply_text("Usage: /restart <service>\n\nOptions: docker, nginx, wireguard, all\n\nExample: /restart docker")
        return
    
    service = context.args[0].lower()
    
    await update.message.reply_text(f"🔄 Restarting {service}...")
    
    if service == "docker":
        run_command("systemctl restart docker")
    elif service == "nginx":
        run_command("systemctl restart nginx")
    elif service == "wireguard":
        run_command("systemctl restart wg-quick@wg0")
    elif service == "all":
        run_command("systemctl restart docker nginx wg-quick@wg0 2>/dev/null")
    else:
        await update.message.reply_text("❌ Invalid service. Use: docker, nginx, wireguard, or all")
        return
    
    await update.message.reply_text(f"✅ {service} restarted!")

async def docker_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    containers = run_command("docker ps --format '{{.Names}} - {{.Status}}'")
    
    if containers:
        await update.message.reply_text(f"🐳 *Docker Containers:*\n\n```\n{containers}\n```", parse_mode='Markdown')
    else:
        await update.message.reply_text("No containers running")

async def containers_detailed(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    containers = run_command("docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'")
    
    if len(containers) > 4000:
        containers = containers[:4000] + "\n... (truncated)"
    
    await update.message.reply_text(f"🐳 *All Containers:*\n\n```\n{containers}\n```", parse_mode='Markdown')

async def create_backup(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    await update.message.reply_text("💾 Creating backup...")
    
    timestamp = subprocess.run("date +%Y%m%d_%H%M%S", shell=True, capture_output=True, text=True).stdout.strip()
    backup_file = f"/var/backups/bdrman/backup_{timestamp}.tar.gz"
    
    run_command(f"mkdir -p /var/backups/bdrman && tar -czf {backup_file} /etc/wireguard /etc/ufw /etc/nginx /var/log/bdrman.log 2>/dev/null")
    
    size = run_command(f"du -h {backup_file} | cut -f1").strip()
    
    await update.message.reply_text(f"✅ Backup created!\n\n📦 File: `{backup_file}`\n💾 Size: {size}", parse_mode='Markdown')

async def create_snapshot(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    await update.message.reply_text("📸 Creating system snapshot...\n⏳ This may take several minutes.")
    
    timestamp = subprocess.run("date +%Y%m%d_%H%M%S", shell=True, capture_output=True, text=True).stdout.strip()
    snapshot_name = f"snapshot_{timestamp}"
    
    # Run snapshot creation in background
    cmd = f"mkdir -p /var/snapshots && rsync -aAX --delete --exclude=/dev --exclude=/proc --exclude=/sys --exclude=/tmp --exclude=/run --exclude=/mnt --exclude=/media --exclude=/lost+found --exclude=/var/snapshots / /var/snapshots/{snapshot_name}/ 2>&1"
    
    result = run_command(cmd)
    
    if "error" in result.lower():
        await update.message.reply_text(f"❌ Snapshot creation failed!\n\n```\n{result[:500]}\n```", parse_mode='Markdown')
    else:
        await update.message.reply_text(f"✅ System snapshot created!\n\n📸 Name: `{snapshot_name}`\n📁 Path: `/var/snapshots/{snapshot_name}/`", parse_mode='Markdown')

async def view_logs(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    logs = run_command("journalctl -p err -n 20 --no-pager")
    
    if len(logs) > 4000:
        logs = logs[:4000] + "\n... (truncated)"
    
    if logs.strip():
        await update.message.reply_text(f"📋 *Recent Errors:*\n\n```\n{logs}\n```", parse_mode='Markdown')
    else:
        await update.message.reply_text("✅ No recent errors found!")

async def firewall_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    status = run_command("ufw status numbered")
    
    if len(status) > 4000:
        status = status[:4000] + "\n... (truncated)"
    
    await update.message.reply_text(f"🔥 *Firewall Status:*\n\n```\n{status}\n```", parse_mode='Markdown')

async def block_ip(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    if len(context.args) == 0:
        await update.message.reply_text("Usage: /block <ip>\nExample: /block 192.168.1.100")
        return
    
    ip = context.args[0]
    
    # Basic IP validation
    parts = ip.split('.')
    if len(parts) != 4 or not all(p.isdigit() and 0 <= int(p) <= 255 for p in parts):
        await update.message.reply_text("❌ Invalid IP address")
        return
    
    await update.message.reply_text(f"🔒 Blocking IP: {ip}...")
    
    run_command(f"ufw deny from {ip}")
    
    await update.message.reply_text(f"✅ IP {ip} has been blocked!")

async def get_ssl(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    if len(context.args) == 0:
        await update.message.reply_text("Usage: /ssl <domain>\nExample: /ssl example.com")
        return
    
    domain = context.args[0]
    
    if not run_command("command -v certbot").strip():
        await update.message.reply_text("❌ Certbot not installed. Install it first via the main menu.")
        return
    
    await update.message.reply_text(f"🔐 Obtaining SSL certificate for: {domain}\n⏳ This may take a minute...")
    
    result = run_command(f"certbot certonly --nginx -d {domain} --non-interactive --agree-tos --email admin@{domain}")
    
    if "Successfully received certificate" in result:
        await update.message.reply_text(f"✅ SSL certificate obtained for {domain}!")
    else:
        await update.message.reply_text(f"❌ SSL certificate request failed!\n\n```\n{result[:500]}\n```", parse_mode='Markdown')

async def disk_usage(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    disk = run_command("df -h | grep -vE '^Filesystem|tmpfs|cdrom'")
    await update.message.reply_text(f"💾 *Disk Usage:*\n\n```\n{disk}\n```", parse_mode='Markdown')

async def memory_usage(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    mem = run_command("free -h")
    await update.message.reply_text(f"🧠 *Memory Usage:*\n\n```\n{mem}\n```", parse_mode='Markdown')

async def uptime_info(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    uptime = run_command("uptime -p").strip()
    since = run_command("uptime -s").strip()
    
    await update.message.reply_text(f"⏱️ *System Uptime*\n\n🕐 {uptime}\n📅 Since: {since}")

async def network_info(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    interfaces = run_command("ip -br addr show")
    
    await update.message.reply_text(f"🌐 *Network Interfaces:*\n\n```\n{interfaces}\n```", parse_mode='Markdown')

async def top_processes(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    processes = run_command("ps aux --sort=-%mem | head -n 11")
    
    await update.message.reply_text(f"📊 *Top Processes (by memory):*\n\n```\n{processes}\n```", parse_mode='Markdown')

async def services_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    services = run_command("systemctl list-units --type=service --state=running --no-pager | head -n 20")
    
    if len(services) > 4000:
        services = services[:4000] + "\n... (truncated)"
    
    await update.message.reply_text(f"⚙️ *Running Services:*\n\n```\n{services}\n```", parse_mode='Markdown')

async def system_update(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    await update.message.reply_text("🔄 Starting system update...\n⏳ This may take several minutes.")
    
    result = run_command("apt update && apt upgrade -y 2>&1 | tail -n 20")
    
    await update.message.reply_text(f"✅ System update completed!\n\n```\n{result}\n```", parse_mode='Markdown')

async def emergency_mode(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    await update.message.reply_text("🚨 *EMERGENCY MODE*\n\n⚠️ This will:\n• Stop non-critical services\n• Enable strict firewall\n• Create emergency backup\n\nType /confirm_emergency to proceed")

async def exec_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    if len(context.args) == 0:
        await update.message.reply_text("Usage: /exec <command>\n\nExample: /exec df -h\n\n⚠️ Use carefully!")
        return
    
    command = ' '.join(context.args)
    
    # Blacklist dangerous commands
    dangerous = ['rm -rf', 'mkfs', 'dd if=', ':(){', 'fork', '> /dev/sda']
    if any(danger in command.lower() for danger in dangerous):
        await update.message.reply_text("❌ Dangerous command blocked!")
        return
    
    await update.message.reply_text(f"⚡ Executing: `{command}`", parse_mode='Markdown')
    
    result = run_command(command)
    
    if len(result) > 4000:
        result = result[:4000] + "\n... (truncated)"
    
    await update.message.reply_text(f"```\n{result}\n```", parse_mode='Markdown')

def main():
    application = Application.builder().token(BOT_TOKEN).build()
    
    # Basic commands
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("help", help_command))
    application.add_handler(CommandHandler("about", about))
    
    # Monitoring
    application.add_handler(CommandHandler("status", status))
    application.add_handler(CommandHandler("health", health_check))
    application.add_handler(CommandHandler("docker", docker_status))
    application.add_handler(CommandHandler("containers", containers_detailed))
    application.add_handler(CommandHandler("services", services_status))
    application.add_handler(CommandHandler("logs", view_logs))
    application.add_handler(CommandHandler("disk", disk_usage))
    application.add_handler(CommandHandler("memory", memory_usage))
    application.add_handler(CommandHandler("uptime", uptime_info))
    application.add_handler(CommandHandler("network", network_info))
    application.add_handler(CommandHandler("top", top_processes))
    
    # Management
    application.add_handler(CommandHandler("vpn", vpn_create))
    application.add_handler(CommandHandler("restart", restart_service))
    application.add_handler(CommandHandler("backup", create_backup))
    application.add_handler(CommandHandler("snapshot", create_snapshot))
    application.add_handler(CommandHandler("update", system_update))
    
    # Firewall & Security
    application.add_handler(CommandHandler("firewall", firewall_status))
    application.add_handler(CommandHandler("block", block_ip))
    application.add_handler(CommandHandler("ssl", get_ssl))
    
    # Emergency
    application.add_handler(CommandHandler("emergency", emergency_mode))
    
    # Advanced
    application.add_handler(CommandHandler("exec", exec_command))
    
    print(f"🤖 Bot started! Waiting for commands...")
    print(f"📱 Chat ID: {ALLOWED_CHAT_ID}")
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == '__main__':
    main()
EOFPYTHON
  
  chmod +x /etc/bdrman/telegram_bot.py
  
  # Create systemd service
  cat > /etc/systemd/system/bdrman-telegram.service << EOF
[Unit]
Description=BDRman Telegram Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/bdrman
ExecStart=/usr/bin/python3 /etc/bdrman/telegram_bot.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  
  systemctl daemon-reload
  systemctl enable bdrman-telegram.service
  systemctl start bdrman-telegram.service
  
  echo "✅ Telegram bot webhook server installed"
  echo "✅ Service started: bdrman-telegram"
  echo ""
  echo "Bot is now running and listening for commands!"
  echo "Try sending /help to your bot on Telegram"
  echo ""
  echo "To check status: systemctl status bdrman-telegram"
  echo "To view logs: journalctl -u bdrman-telegram -f"
  
  log_success "Telegram bot webhook server started"
}

telegram_send(){
  echo "=== SEND TELEGRAM MESSAGE ==="
  
  if [ ! -f /etc/bdrman/telegram.conf ]; then
    echo "Telegram not configured. Run setup first."
    return
  fi
  
  read -rp "Message to send: " message
  
  if [ -n "$message" ]; then
    /usr/local/bin/bdrman-telegram "$message"
    echo "✅ Message sent"
  fi
}

telegram_test_report(){
  echo "=== SEND TEST REPORT ==="
  
  if [ ! -f /etc/bdrman/telegram_daily_report.sh ]; then
    echo "Reports not configured. Configure alerts first."
    return
  fi
  
  echo "Sending test daily report..."
  /etc/bdrman/telegram_daily_report.sh
  echo "✅ Report sent! Check your Telegram"
}

# ============= MENUS =============
vpn_menu(){
  while true; do
    clear_and_banner
    echo "=== VPN SETTINGS ==="
    echo "0) Back"
    echo "1) WireGuard Status"
    echo "2) Add New Client (wireguard-install.sh)"
    echo "3) Restart WireGuard"
    echo "4) List Config Files (/etc/wireguard)"
    echo "5) Show wg show"
    read -rp "Select (0-5): " c
    case "$c" in
      0) break ;;
      1) vpn_status; pause ;;
      2) vpn_add_client; pause ;;
      3) vpn_restart; pause ;;
      4) ls -la /etc/wireguard 2>/dev/null || echo "Directory not found."; pause ;;
      5) wg show || echo "WireGuard not installed."; pause ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}

caprover_menu(){
  while true; do
    clear_and_banner
    echo "=== CAPROVER SETTINGS ==="
    echo "0) Back"
    echo "1) Check CapRover Container"
    echo "2) View Logs (last 200 lines)"
    echo "3) Restart CapRover"
    echo "4) Deploy App (custom hook)"
    read -rp "Select (0-4): " c
    case "$c" in
      0) break ;;
      1) caprover_check; pause ;;
      2) caprover_logs; pause ;;
      3) caprover_restart; pause ;;
      4) echo "Custom deploy logic here."; pause ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}

firewall_menu(){
  while true; do
    clear_and_banner
    echo "=== FIREWALL SETTINGS (UFW) ==="
    echo "0) Back"
    echo "1) Status"
    echo "2) Enable"
    echo "3) Disable"
    echo "4) Allow Port"
    echo "5) Block IP"
    echo "6) Reset Rules"
    read -rp "Select (0-6): " c
    case "$c" in
      0) break ;;
      1) fw_status; pause ;;
      2) fw_enable; pause ;;
      3) fw_disable; pause ;;
      4) fw_allow_port; pause ;;
      5) fw_deny_ip; pause ;;
      6) fw_reset; pause ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}

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

backup_menu(){
  while true; do
    clear_and_banner
    echo "=== BACKUP & RESTORE ==="
    echo "0) Back"
    echo "1) Create Backup Now"
    echo "2) List Backups"
    echo "3) Restore from Backup"
    echo "4) Setup Auto Backup (Cron)"
    echo "5) Send Backup to Remote Server"
    read -rp "Select (0-5): " c
    case "$c" in
      0) break ;;
      1) backup_create; pause ;;
      2) backup_list; pause ;;
      3) backup_restore; pause ;;
      4) backup_auto_setup; pause ;;
      5) backup_remote; pause ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}

security_menu(){
  while true; do
    clear_and_banner
    echo "=== SECURITY & HARDENING ==="
    echo "0) Back"
    echo "1) SSH Hardening"
    echo "2) Fail2Ban Management"
    echo "3) SSL Certificate (Let's Encrypt)"
    echo "4) Automatic Security Updates"
    read -rp "Select (0-4): " c
    case "$c" in
      0) break ;;
      1) security_ssh_harden; pause ;;
      2) security_fail2ban; pause ;;
      3) security_ssl; pause ;;
      4) security_updates; pause ;;
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

advanced_menu(){
  while true; do
    clear_and_banner
    echo "=== ADVANCED TOOLS ==="
    echo "0) Back"
    echo "1) Database Management"
    echo "2) Nginx Management"
    echo "3) User Management"
    echo "4) Network Diagnostics"
    echo "5) Performance & Cleanup"
    echo "6) System Snapshot & Restore"
    echo "7) Configuration as Code"
    echo "8) Advanced Firewall"
    read -rp "Select (0-8): " c
    case "$c" in
      0) break ;;
      1) db_menu_main; pause ;;
      2) nginx_manage; pause ;;
      3) user_manage; pause ;;
      4) network_diag; pause ;;
      5) perf_optimize; pause ;;
      6) snapshot_menu; pause ;;
      7) config_menu; pause ;;
      8) firewall_advanced; pause ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}

snapshot_menu(){
  while true; do
    clear_and_banner
    echo "=== SYSTEM SNAPSHOT & RESTORE ==="
    echo "0) Back"
    echo "1) Create Snapshot"
    echo "2) List Snapshots"
    echo "3) Restore from Snapshot"
    echo "4) Delete Snapshot"
    read -rp "Select (0-4): " c
    case "$c" in
      0) break ;;
      1) snapshot_create; pause ;;
      2) snapshot_list; pause ;;
      3) snapshot_restore; pause ;;
      4) snapshot_delete; pause ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}

incident_menu(){
  while true; do
    clear_and_banner
    echo "=== 🚨 INCIDENT RESPONSE & RECOVERY ==="
    echo "0) Back"
    echo "1) System Health Check"
    echo "2) Emergency Mode (Safe Mode)"
    echo "3) Quick Rollback"
    echo "4) Setup Auto-Recovery"
    read -rp "Select (0-4): " c
    case "$c" in
      0) break ;;
      1) incident_health_check; pause ;;
      2) incident_emergency_mode; pause ;;
      3) incident_rollback; pause ;;
      4) incident_auto_recovery; pause ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}

config_menu(){
  while true; do
    clear_and_banner
    echo "=== CONFIGURATION AS CODE ==="
    echo "0) Back"
    echo "1) Export Configuration"
    echo "2) Import Configuration"
    echo "3) Apply Template"
    read -rp "Select (0-3): " c
    case "$c" in
      0) break ;;
      1) config_export; pause ;;
      2) config_import; pause ;;
      3) config_template; pause ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}

telegram_menu(){
  while true; do
    clear_and_banner
    echo "=== TELEGRAM BOT ==="
    echo ""
    
    # Check bot status
    if systemctl is-active --quiet bdrman-telegram 2>/dev/null; then
      echo "🟢 Bot Status: RUNNING"
    else
      echo "🔴 Bot Status: STOPPED"
    fi
    
    if [ -f /etc/bdrman/telegram.conf ]; then
      echo "✅ Configuration: Found"
    else
      echo "⚠️  Configuration: Not found"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "0) Back"
    echo "1) Initial Setup (Bot Token & Chat ID)"
    echo "2) Start Interactive Bot Server (Commands)"
    echo "3) Send Manual Message"
    echo "4) Send Test Weekly Report"
    echo "5) View Bot Logs"
    echo "6) Stop Bot Server"
    echo "7) Restart Bot Server"
    echo "8) Check Bot Status (Detailed)"
    read -rp "Select (0-8): " c
    case "$c" in
      0) break ;;
      1) telegram_setup; pause ;;
      2) telegram_bot_webhook; pause ;;
      3) telegram_send; pause ;;
      4) telegram_test_report; pause ;;
      5) 
        if systemctl is-active --quiet bdrman-telegram; then
          echo "Last 50 lines of bot logs:"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          journalctl -u bdrman-telegram -n 50 --no-pager
        else
          echo "⚠️  Bot server not running"
        fi
        pause 
        ;;
      6)
        systemctl stop bdrman-telegram
        echo "✅ Bot server stopped"
        pause
        ;;
      7)
        systemctl restart bdrman-telegram
        sleep 2
        if systemctl is-active --quiet bdrman-telegram; then
          echo "✅ Bot server restarted successfully"
        else
          echo "❌ Failed to restart. Check logs with option 5"
        fi
        pause
        ;;
      8)
        telegram_bot_status
        pause
        ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}

telegram_bot_status(){
  echo "=== DETAILED BOT STATUS ==="
  echo ""
  
  # Check config file
  if [ -f /etc/bdrman/telegram.conf ]; then
    echo "✅ Config file exists: /etc/bdrman/telegram.conf"
    source /etc/bdrman/telegram.conf
    echo "   Bot Token: ${BOT_TOKEN:0:20}..."
    echo "   Chat ID: $CHAT_ID"
  else
    echo "❌ Config file NOT found!"
    echo "   Run 'Initial Setup' first (option 1)"
    return
  fi
  
  echo ""
  
  # Check Python
  if command_exists python3; then
    PYTHON_VERSION=$(python3 --version 2>&1)
    echo "✅ Python3: $PYTHON_VERSION"
  else
    echo "❌ Python3 not installed"
  fi
  
  echo ""
  
  # Check python-telegram-bot
  if python3 -c "import telegram" 2>/dev/null; then
    echo "✅ python-telegram-bot library installed"
  else
    echo "❌ python-telegram-bot library NOT installed"
    echo "   Installing now..."
    pip3 install python-telegram-bot --upgrade
  fi
  
  echo ""
  
  # Check bot script
  if [ -f /etc/bdrman/telegram_bot.py ]; then
    echo "✅ Bot script exists: /etc/bdrman/telegram_bot.py"
  else
    echo "❌ Bot script NOT found!"
    echo "   Run 'Start Interactive Bot Server' (option 3)"
    return
  fi
  
  echo ""
  
  # Check systemd service
  if [ -f /etc/systemd/system/bdrman-telegram.service ]; then
    echo "✅ Systemd service exists"
    echo ""
    systemctl status bdrman-telegram --no-pager -l
  else
    echo "❌ Systemd service NOT found!"
    echo "   Run 'Start Interactive Bot Server' (option 3)"
    return
  fi
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  # Test bot connection
  echo "🔍 Testing bot connection..."
  TEST_RESULT=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe")
  
  if echo "$TEST_RESULT" | grep -q '"ok":true'; then
    echo "✅ Bot is reachable and token is valid!"
    BOT_USERNAME=$(echo "$TEST_RESULT" | grep -o '"username":"[^"]*' | cut -d'"' -f4)
    echo "   Bot Username: @$BOT_USERNAME"
  else
    echo "❌ Cannot reach bot or token is invalid!"
    echo "   Response: $TEST_RESULT"
  fi
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "💡 TROUBLESHOOTING:"
  echo ""
  echo "If bot is not responding to commands:"
  echo "1. Make sure bot is running: systemctl status bdrman-telegram"
  echo "2. Check logs: journalctl -u bdrman-telegram -f"
  echo "3. Restart bot: systemctl restart bdrman-telegram"
  echo "4. Test from Telegram: /start"
  echo ""
  echo "If you see 'Unauthorized' error:"
  echo "- Your Chat ID might be wrong"
  echo "- Get your Chat ID from @userinfobot"
  echo "- Re-run Initial Setup (option 1)"
}

main_menu(){
  while true; do
    clear_and_banner
    echo "1) System Status"
    echo "2) VPN Settings"
    echo "3) CapRover Settings"
    echo "4) Firewall Settings"
    echo "5) Logs & Monitoring"
    echo "6) Backup & Restore"
    echo "7) Security & Hardening"
    echo "8) Monitoring & Alerts"
    echo "9) Advanced Tools"
    echo "10) Incident Response 🚨"
    echo "11) Telegram Bot 📱"
    echo "12) Quick Commands"
    echo "13) Exit"
    read -rp "Select (1-13): " s
    case "$s" in
      1)
        echo "=== SYSTEM STATUS ==="
        uname -a; echo; uptime; echo; df -h; echo; free -h; pause ;;
      2) vpn_menu ;;
      3) caprover_menu ;;
      4) firewall_menu ;;
      5) logs_menu ;;
      6) backup_menu ;;
      7) security_menu ;;
      8) monitoring_menu ;;
      9) advanced_menu ;;
      10) incident_menu ;;
      11) telegram_menu ;;
      12)
        echo "=== QUICK COMMANDS ==="
        echo "1) List Docker Containers"
        echo "2) System Update"
        echo "3) Restart All Services"
        read -rp "Choice (Enter = Back): " k
        case "$k" in
          1) docker ps -a; pause ;;
          2) apt update && apt upgrade -y; pause ;;
          3)
            systemctl restart docker
            systemctl restart nginx
            systemctl restart wg-quick@wg0
            echo "✅ Services restarted"
            pause
            ;;
          *) echo "Returning..."; pause ;;
        esac
        ;;
      13) echo "Exiting..."; log "bdrman exited."; break ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}

mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true
mkdir -p "$BACKUP_DIR" 2>/dev/null || true
touch "$LOGFILE" 2>/dev/null || true

# Check for auto-backup flag
if [ "$1" = "--auto-backup" ]; then
  backup_create
  exit 0
fi

log "bdrman started."
main_menu
