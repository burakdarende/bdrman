# ============= SECURITY & HARDENING =============

# ============= FIREWALL (UFW) =============
fw_status(){ ufw status verbose 2>/dev/null || echo "UFW not installed."; }

fw_enable(){
  echo "⚠️  Command may disrupt existing ssh connections. Proceed with operation (y|n)?"
  read -rp "Enable firewall? (y/n): " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    ufw --force enable && success "Firewall enabled." || error "Enable failed."
  else
    warning "Aborted"
  fi
}

fw_disable(){
  read -rp "Disable firewall? (y/n): " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    ufw disable && success "Firewall disabled." || error "Disable failed."
  else
    warning "Aborted"
  fi
}
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

# ============= PANIC MODE =============
panic_mode_on(){
  local trusted_ip="$1"
  if [ -z "$trusted_ip" ]; then
    read -rp "Enter Trusted IP for SSH access: " trusted_ip
  fi
  
  if [ -z "$trusted_ip" ]; then error "Trusted IP required!"; return; fi
  
  echo "🚨 ACTIVATING PANIC MODE 🚨"
  echo "⚠️  Blocking ALL incoming traffic except SSH from $trusted_ip"
  
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow from "$trusted_ip" to any port 22 proto tcp
  ufw --force enable
  
  success "PANIC MODE ACTIVATED. Only $trusted_ip can access SSH."
}

panic_mode_off(){
  echo "🟢 DEACTIVATING PANIC MODE..."
  echo "Restoring default firewall rules..."
  
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow ssh
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow 3000/tcp # CapRover
  ufw --force enable
  
  success "Panic Mode Deactivated. Default rules restored."
}

# ============= NETWORK STATS =============
network_stats(){
  echo "=== NETWORK STATISTICS ==="
  echo "Active Connections: $(netstat -an | grep ESTABLISHED | wc -l)"
  echo ""
  echo "Top 10 Connecting IPs:"
  echo "----------------------"
  netstat -ntu | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -n 10
  echo ""
  pause
}

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

# ============= SECURITY FEATURES =============

# 2FA Configuration (DISABLED by default)
TFA_ENABLED=${TFA_ENABLED:-false}
AUDIT_LOG_ENABLED=${AUDIT_LOG_ENABLED:-false}
AUDIT_LOG_FILE="/var/log/bdrman_audit.log"

# 2FA Setup (TOTP)
security_2fa_setup(){
  if [ "$TFA_ENABLED" != "true" ]; then
    warning "2FA is currently DISABLED (passive mode)"
    info "To enable: Set TFA_ENABLED=true in $CONFIG_FILE"
    read -rp "Enable 2FA now? (yes/no): " enable
    if [ "$enable" != "yes" ]; then
      return
    fi
  fi
  
  if ! command_exists oathtool; then
    warning "oathtool not installed. Install: apt install oathtool qrencode"
    return 1
  fi
  
  info "Setting up 2FA (TOTP)..."
  
  # Generate secret
  SECRET=$(head -c 16 /dev/urandom | base32)
  
  # Save to config
  mkdir -p /etc/bdrman
  echo "2FA_SECRET=$SECRET" > /etc/bdrman/2fa.conf
  chmod 600 /etc/bdrman/2fa.conf
  
  # Generate QR code
  ISSUER="BDRman"
  USER="$(hostname)"
  OTPAUTH="otpauth://totp/$ISSUER:$USER?secret=$SECRET&issuer=$ISSUER"
  
  echo ""
  info "Scan this QR code with Google Authenticator:"
  echo ""
  qrencode -t ANSIUTF8 "$OTPAUTH"
  echo ""
  echo "Or enter this secret manually: $SECRET"
  echo ""
  
  success "2FA setup complete"
  info "Update config: 2FA_ENABLED=true in $CONFIG_FILE"
}

# Verify 2FA token
security_2fa_verify(){
  if [ ! -f /etc/bdrman/2fa.conf ]; then
    error "2FA not configured"
    return 1
  fi
  
  source /etc/bdrman/2fa.conf
  
  read -rp "Enter 2FA code: " code
  
  EXPECTED=$(oathtool --totp -b "$2FA_SECRET")
  
  if [ "$code" = "$EXPECTED" ]; then
    success "2FA verified"
    return 0
  else
    error "Invalid 2FA code"
    return 1
  fi
}

# Security Scan
security_scan(){
  info "Running security scan..."
  echo ""
  
  SCORE=100
  ISSUES=()
  
  # Port scan
  info "[1/5] Scanning open ports..."
  OPEN_PORTS=$(ss -tuln | grep LISTEN | wc -l)
  echo "   Open ports: $OPEN_PORTS"
  if [ "$OPEN_PORTS" -gt 10 ]; then
    ISSUES+=("Too many open ports ($OPEN_PORTS)")
    SCORE=$((SCORE - 10))
  fi
  
  # SSH config check
  info "[2/5] Checking SSH configuration..."
  if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
    ISSUES+=("Root login enabled in SSH")
    SCORE=$((SCORE - 15))
  fi
  if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
    ISSUES+=("Password authentication enabled")
    SCORE=$((SCORE - 10))
  fi
  
  # Firewall check
  info "[3/5] Checking firewall status..."
  if ! systemctl is-active ufw >/dev/null 2>&1; then
    ISSUES+=("Firewall (UFW) not active")
    SCORE=$((SCORE - 20))
  fi
  
  # Updates check
  info "[4/5] Checking for updates..."
  UPDATES=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo 0)
  echo "   Available updates: $UPDATES"
  if [ "$UPDATES" -gt 20 ]; then
    ISSUES+=("Many pending updates ($UPDATES)")
    SCORE=$((SCORE - 10))
  fi
  
  # Fail2Ban check
  info "[5/5] Checking Fail2Ban..."
  if ! systemctl is-active fail2ban >/dev/null 2>&1; then
    ISSUES+=("Fail2Ban not active")
    SCORE=$((SCORE - 15))
  fi
  
  echo ""
  echo "==========================================="
  echo "Security Score: $SCORE/100"
  echo "==========================================="
  
  if [ ${#ISSUES[@]} -gt 0 ]; then
    echo ""
    warning "Issues found:"
    for issue in "${ISSUES[@]}"; do
      echo "  • $issue"
    done
  else
    success "No security issues found!"
  fi
  
  echo ""
  if [ "$SCORE" -lt 70 ]; then
    error "Security score is LOW. Immediate action recommended."
  elif [ "$SCORE" -lt 85 ]; then
    warning "Security score is MEDIUM. Improvements recommended."
  else
    success "Security score is GOOD."
  fi
}

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

security_tools_install(){
  echo "=== 🛡️ SECURITY TOOLS AUTO-INSTALLER ==="
  echo ""
  echo "This will install comprehensive security tools:"
  echo ""
  echo "1️⃣  Fail2Ban - Brute force protection"
  echo "2️⃣  ClamAV - Antivirus scanner"
  echo "3️⃣  RKHunter - Rootkit detector"
  echo "4️⃣  Lynis - Security auditing tool"
  echo "5️⃣  OSSEC - Host-based intrusion detection"
  echo "6️⃣  ModSecurity - Web application firewall"
  echo "7️⃣  AppArmor - Mandatory access control"
  echo "8️⃣  Aide - File integrity checker"
  echo "9️⃣  Auditd - Linux audit framework"
  echo "🔟 Psad - Port scan attack detector"
  echo ""
  
  read -rp "Install ALL security tools? (yes/no): " confirm
  [ "$confirm" != "yes" ] && return
  
  echo ""
  echo "🔄 Starting installation..."
  echo ""
  
  # Update package list
  apt update
  
  # 1. Fail2Ban
  echo "📦 Installing Fail2Ban..."
  apt install -y fail2ban
  systemctl enable fail2ban
  systemctl start fail2ban
  
  # Configure Fail2Ban
  cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
EOF
  
  systemctl restart fail2ban
  echo "✅ Fail2Ban installed and configured"
  
  # 2. ClamAV
  echo "📦 Installing ClamAV..."
  apt install -y clamav clamav-daemon
  systemctl stop clamav-freshclam
  freshclam
  systemctl start clamav-freshclam
  systemctl enable clamav-freshclam
  echo "✅ ClamAV installed"
  
  # 3. RKHunter
  echo "📦 Installing RKHunter..."
  apt install -y rkhunter
  rkhunter --update
  rkhunter --propupd
  echo "✅ RKHunter installed"
  
  # 4. Lynis
  echo "📦 Installing Lynis..."
  apt install -y lynis
  echo "✅ Lynis installed"
  
  # 5. AppArmor
  echo "📦 Installing AppArmor..."
  apt install -y apparmor apparmor-utils
  systemctl enable apparmor
  systemctl start apparmor
  echo "✅ AppArmor installed"
  
  # 6. Aide
  echo "📦 Installing Aide..."
  apt install -y aide aide-common
  aideinit
  mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
  echo "✅ Aide installed"
  
  # 7. Auditd
  echo "📦 Installing Auditd..."
  apt install -y auditd audispd-plugins
  systemctl enable auditd
  systemctl start auditd
  echo "✅ Auditd installed"
  
  # 8. Psad
  echo "📦 Installing Psad..."
  apt install -y psad
  
  # Configure psad
  sed -i 's/EMAIL_ADDRESSES.*/EMAIL_ADDRESSES     root@localhost;/' /etc/psad/psad.conf
  sed -i 's/HOSTNAME.*/HOSTNAME                '"$(hostname)"';/' /etc/psad/psad.conf
  
  psad -R
  psad --sig-update
  systemctl restart psad
  echo "✅ Psad installed"
  
  # 9. Additional security packages
  echo "📦 Installing additional security tools..."
  apt install -y \
    ufw \
    iptables-persistent \
    logwatch \
    chkrootkit \
    libpam-cracklib \
    libpam-tmpdir
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "✅ ALL SECURITY TOOLS INSTALLED!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  log_success "All security tools installed"
}

security_tools_scan(){
  echo "=== 🔍 SECURITY SCAN ==="
  echo ""
  echo "Running comprehensive security scans..."
  echo ""
  
  # ClamAV scan
  echo "1️⃣  Running ClamAV virus scan (quick scan)..."
  clamscan -r --bell -i /home /root 2>&1 | tail -20
  echo ""
  
  # RKHunter scan
  echo "2️⃣  Running RKHunter rootkit scan..."
  rkhunter --check --skip-keypress --report-warnings-only
  echo ""
  
  # Lynis audit
  echo "3️⃣  Running Lynis security audit..."
  lynis audit system --quick --quiet
  echo ""
  
  # Check Fail2Ban status
  echo "4️⃣  Fail2Ban status..."
  fail2ban-client status
  echo ""
  
  # Check for suspicious ports
  echo "5️⃣  Checking for suspicious ports..."
  ss -tulpn | grep LISTEN
  echo ""
  
  echo "✅ Security scan completed!"
  echo "Review /var/log/lynis.log for detailed audit results"
}

security_tools_status(){
  echo "=== 🛡️ SECURITY TOOLS STATUS ==="
  echo ""
  
  # Check each tool
  echo "Fail2Ban:"
  systemctl is-active fail2ban && echo "  ✅ Running" || echo "  ❌ Not running"
  echo ""
  
  echo "ClamAV:"
  systemctl is-active clamav-freshclam && echo "  ✅ Running" || echo "  ❌ Not running"
  echo ""
  
  echo "AppArmor:"
  systemctl is-active apparmor && echo "  ✅ Running" || echo "  ❌ Not running"
  echo ""
  
  echo "Auditd:"
  systemctl is-active auditd && echo "  ✅ Running" || echo "  ❌ Not running"
  echo ""
  
  echo "Psad:"
  systemctl is-active psad && echo "  ✅ Running" || echo "  ❌ Not running"
  echo ""
  
  # Fail2Ban banned IPs
  echo "Fail2Ban - Banned IPs:"
  fail2ban-client status sshd 2>/dev/null | grep "Banned IP" || echo "  No bans"
  echo ""
  
  # Recent alerts
  echo "Recent security alerts (last 10):"
  tail -10 /var/log/fail2ban.log 2>/dev/null || echo "  No recent alerts"
}

# ============= ADVANCED SECURITY MONITORING =============

security_monitoring_setup(){
  echo "=== 🛡️ ADVANCED SECURITY MONITORING SETUP ==="
  echo ""
  echo "This will set up:"
  echo "1) Real-time DDoS detection"
  echo "2) Anomaly detection (unusual traffic, CPU, memory)"
  echo "3) Automatic Telegram alerts (every 2 seconds when threat detected)"
  echo "4) Auto-response to attacks"
  echo ""
  
  if [ ! -f /etc/bdrman/telegram.conf ]; then
    echo "⚠️  Telegram bot not configured!"
    echo "   Please run Telegram setup first (Menu → 11 → 1)"
    return
  fi
  
  read -rp "Enable advanced security monitoring? (yes/no): " confirm
  [ "$confirm" != "yes" ] && return
  
  echo "📝 Creating security monitor script..."
  
  cat > /etc/bdrman/security_monitor.sh << 'EOFMONITOR'
#!/bin/bash

# Load Telegram config
source /etc/bdrman/telegram.conf

# Load main config if exists
[ -f /etc/bdrman/config.conf ] && source /etc/bdrman/config.conf

# Defaults (overridden by config.conf)
ALERT_COOLDOWN=${ALERT_COOLDOWN:-300}  # 5 minutes default
MONITORING_INTERVAL=${MONITORING_INTERVAL:-30}  # 30 seconds default
DDOS_THRESHOLD=${DDOS_THRESHOLD:-50}
CPU_ALERT_THRESHOLD=${CPU_ALERT_THRESHOLD:-90}
MEMORY_ALERT_THRESHOLD=${MEMORY_ALERT_THRESHOLD:-90}
DISK_ALERT_THRESHOLD=${DISK_ALERT_THRESHOLD:-90}
FAILED_LOGIN_THRESHOLD=${FAILED_LOGIN_THRESHOLD:-10}
TELEGRAM_TIMEOUT=${TELEGRAM_TIMEOUT:-10}
TELEGRAM_RETRIES=${TELEGRAM_RETRIES:-2}

ALERT_LOG="/var/log/bdrman_security_alerts.log"

# Per-alert type cooldown tracking
can_send_alert() {
    local alert_type="$1"
    local cooldown_file="/tmp/bdrman_last_alert_${alert_type}"
    
    if [ ! -f "$cooldown_file" ]; then
        return 0
    fi
    
    local last_alert=$(cat "$cooldown_file" 2>/dev/null || echo 0)
    local current_time=$(date +%s)
    local diff=$((current_time - last_alert))
    
    [ $diff -ge $ALERT_COOLDOWN ]
}

# Send alert with per-type cooldown
send_alert() {
    local alert_type="$1"
    local message="$2"
    local cooldown_file="/tmp/bdrman_last_alert_${alert_type}"
    
    if can_send_alert "$alert_type"; then
        if send_telegram_alert "$message"; then
            date +%s > "$cooldown_file"
            echo "$(date): [$alert_type] ALERT SENT" >> "$ALERT_LOG"
            return 0
        else
            echo "$(date): [$alert_type] ALERT FAILED" >> "$ALERT_LOG"
            return 1
        fi
    else
        echo "$(date): [$alert_type] ALERT SKIPPED (cooldown)" >> "$ALERT_LOG"
        return 2
    fi
}

# Safe curl wrapper for Telegram API
telegram_curl() {
    local url="$1"
    shift
    
    if ! curl --fail --max-time "$TELEGRAM_TIMEOUT" --retry "$TELEGRAM_RETRIES" -s -X POST "$url" "$@" > /dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Telegram notification function
send_telegram_alert() {
    local message="$1"
    
    if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
        return 1
    fi
    
    telegram_curl "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="$message" \
        -d parse_mode="Markdown"
    
    return $?
}

# DDoS Detection
check_ddos() {
    # Check connection count per IP (using configurable threshold)
    local suspicious_ips=$(ss -tunap 2>/dev/null | grep ESTAB | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | awk -v threshold="$DDOS_THRESHOLD" '$1 > threshold {print $2":"$1}')
    
    if [ -n "$suspicious_ips" ]; then
        local count=$(echo "$suspicious_ips" | wc -l)
        local top_ip=$(echo "$suspicious_ips" | head -1 | cut -d: -f1)
        local connections=$(echo "$suspicious_ips" | head -1 | cut -d: -f2)
        
        local alert="🚨 *DDOS ALERT DETECTED*%0A%0A"
        alert+="⚠️ *Threat Level:* HIGH%0A"
        alert+="📊 *Type:* Connection Flood%0A"
        alert+="🔍 *Details:*%0A"
        alert+="   • Suspicious IPs: ${count}%0A"
        alert+="   • Top Offender: \`${top_ip}\`%0A"
        alert+="   • Connections: ${connections}%0A"
        alert+="   • Threshold: ${DDOS_THRESHOLD}%0A%0A"
        alert+="💡 *Recommended Actions:*%0A"
        alert+="   1. /ddos_enable - Enable DDoS protection%0A"
        alert+="   2. /caprover_protect - Protect CapRover%0A"
        alert+="   3. /block ${top_ip} - Block this IP%0A%0A"
        alert+="📅 Time: $(date '+%Y-%m-%d %H:%M:%S')"
        
        send_alert "ddos" "$alert"
        return 1
    fi
    return 0
}

# High CPU Detection
check_cpu() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d'.' -f1)
    
    if [ -n "$cpu_usage" ] && [ "$cpu_usage" -gt "$CPU_ALERT_THRESHOLD" ]; then
        local top_process=$(ps aux --sort=-%cpu | head -2 | tail -1 | awk '{print $11}')
        
        local alert="⚠️ *HIGH CPU ALERT*%0A%0A"
        alert+="📊 *CPU Usage:* ${cpu_usage}%% (threshold: ${CPU_ALERT_THRESHOLD}%%)%0A"
        alert+="🔝 *Top Process:* \`${top_process}\`%0A%0A"
        alert+="💡 *Possible Causes:*%0A"
        alert+="   • DDoS attack%0A"
        alert+="   • Resource-heavy process%0A"
        alert+="   • Infinite loop/bug%0A%0A"
        alert+="🔧 *Actions:*%0A"
        alert+="   /top - View all processes%0A"
        alert+="   /docker - Check containers%0A"
        alert+="   /ddos_status - Check for attacks"
        
        send_alert "cpu" "$alert"
        return 1
    fi
    return 0
}

# High Memory Detection  
check_memory() {
    local mem_usage=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')
    
    if [ -n "$mem_usage" ] && [ "$mem_usage" -gt "$MEMORY_ALERT_THRESHOLD" ]; then
        local top_process=$(ps aux --sort=-%mem | head -2 | tail -1 | awk '{print $11}')
        local mem_used=$(free -h | grep Mem | awk '{print $3}')
        local mem_total=$(free -h | grep Mem | awk '{print $2}')
        
        local alert="🧠 *HIGH MEMORY ALERT*%0A%0A"
        alert+="📊 *Memory Usage:* ${mem_usage}%% (${mem_used}/${mem_total})%0A"
        alert+="🔝 *Top Process:* \`${top_process}\`%0A%0A"
        alert+="💡 *Actions:*%0A"
        alert+="   /memory - View details%0A"
        alert+="   /docker - Check containers%0A"
        alert+="   /restart docker - Restart if needed"
        
        send_alert "memory" "$alert"
        return 1
    fi
    return 0
}

# Disk Space Detection
check_disk() {
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    
    if [ -n "$disk_usage" ] && [ "$disk_usage" -gt "$DISK_ALERT_THRESHOLD" ]; then
        local disk_used=$(df -h / | tail -1 | awk '{print $3}')
        local disk_free=$(df -h / | tail -1 | awk '{print $4}')
        
        local alert="💾 *CRITICAL DISK ALERT*%0A%0A"
        alert+="📊 *Disk Usage:* ${disk_usage}%% (threshold: ${DISK_ALERT_THRESHOLD}%%)%0A"
        alert+="📁 *Used:* ${disk_used}%0A"
        alert+="📂 *Free:* ${disk_free}%0A%0A"
        alert+="⚠️ *WARNING:* System may crash if disk fills!%0A%0A"
        alert+="💡 *Urgent Actions:*%0A"
        alert+="   /disk - View details%0A"
        alert+="   /capclean - Clean old backups"
        
        send_alert "disk" "$alert"
        return 1
    fi
    return 0
}

# Failed Login Attempts
check_failed_logins() {
    local failed_count=$(grep "Failed password" /var/log/auth.log 2>/dev/null | tail -100 | wc -l)
    local recent_failed=$(grep "Failed password" /var/log/auth.log 2>/dev/null | tail -5 | grep -oP '(?<=from )[0-9.]+' | sort | uniq -c | sort -rn | head -1)
    
    if [ -n "$failed_count" ] && [ "$failed_count" -gt "$FAILED_LOGIN_THRESHOLD" ]; then
        local alert="🔐 *BRUTE FORCE ALERT*%0A%0A"
        alert+="📊 *Failed Logins:* ${failed_count} (last 100 attempts)%0A"
        alert+="⚠️ *Threshold:* ${FAILED_LOGIN_THRESHOLD}%0A%0A"
        
        if [ -n "$recent_failed" ]; then
            local ip=$(echo "$recent_failed" | awk '{print $2}')
            local count=$(echo "$recent_failed" | awk '{print $1}')
            alert+="🔍 *Top Offender:*%0A"
            alert+="   IP: \`${ip}\`%0A"
            alert+="   Attempts: ${count}%0A%0A"
            alert+="💡 *Actions:*%0A"
            alert+="   /block ${ip} - Block this IP%0A"
            alert+="   /firewall - Check firewall status"
        fi
        
        send_alert "bruteforce" "$alert"
        return 1
    fi
    return 0
}

# Service Down Detection
check_services() {
    local down_services=""
    
    for service in docker nginx ssh; do
        if ! systemctl is-active --quiet $service 2>/dev/null && ! systemctl is-active --quiet sshd 2>/dev/null; then
            down_services+="   ❌ ${service}%0A"
        fi
    done
    
    if [ -n "$down_services" ]; then
        local alert="🚨 *SERVICE DOWN ALERT*%0A%0A"
        alert+="⚠️ *Critical services are down:*%0A"
        alert+="${down_services}%0A"
        alert+="💡 *Actions:*%0A"
        alert+="   /services - View all services%0A"
        alert+="   /restart all - Restart services%0A"
        alert+="   /health - Full health check"
        
        send_alert "services" "$alert"
        return 1
    fi
    return 0
}

# Main monitoring loop
main() {
    echo "🛡️ Security monitoring started at $(date)"
    
    while true; do
        check_ddos
        check_cpu
        check_memory
        check_disk
        check_failed_logins
        check_services
        
        sleep "$MONITORING_INTERVAL"
        sleep 2
    done
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main
fi
EOFMONITOR
  
  chmod +x /etc/bdrman/security_monitor.sh
  
  cat > /etc/systemd/system/bdrman-security-monitor.service << EOF
[Unit]
Description=BDRman Advanced Security Monitoring
After=network.target

[Service]
Type=simple
User=root
ExecStart=/etc/bdrman/security_monitor.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  
  systemctl daemon-reload
  systemctl enable bdrman-security-monitor.service
  systemctl start bdrman-security-monitor.service
  
  echo ""
  echo "✅ Advanced security monitoring installed!"
  echo "✅ Service started: bdrman-security-monitor"
  
  log_success "Advanced security monitoring enabled"
}

security_monitoring_stop(){
  systemctl stop bdrman-security-monitor
  systemctl disable bdrman-security-monitor
  echo "✅ Security monitoring stopped"
}

security_monitoring_status(){
  echo "=== SECURITY MONITORING STATUS ==="
  echo ""
  systemctl status bdrman-security-monitor --no-pager
  echo ""
  echo "Recent alerts:"
  tail -20 /var/log/bdrman_security_alerts.log 2>/dev/null || echo "No alerts yet"
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
      ;;
      
    2)
      echo "=== RATE LIMITING ==="
      echo "Limiting SSH connections to prevent brute force..."
      
      ufw limit 22/tcp comment 'Rate limit SSH'
      
      iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set
      iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP
      
      echo "✅ Rate limiting applied (max 4 connections per minute)"
      ;;
      
    3)
      echo "GeoIP blocking - Coming soon"
      ;;
      
    4)
      echo "=== DDoS PROTECTION ==="
      echo "Applying DDoS mitigation rules..."
      
      iptables -A INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT
      iptables -A INPUT -p tcp --syn -j DROP
      
      iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT
      iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
      
      iptables -N port-scanning
      iptables -A port-scanning -p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit 1/s --limit-burst 2 -j RETURN
      iptables -A port-scanning -j DROP
      
      echo "✅ DDoS protection rules applied"
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
  echo ""
  echo "To exit emergency mode, use: incident_emergency_exit or Telegram command /emergency_exit"
  log_success "Emergency mode activated"
}

incident_emergency_exit(){
  echo "=== 🟢 EXITING EMERGENCY MODE ==="
  echo ""
  echo "This will:"
  echo "1) START stopped services (Docker, Nginx) - NOT reinstall!"
  echo "2) REOPEN firewall ports (80, 443, 3000) - NOT reset config!"
  echo "3) Resume normal operations"
  echo ""
  echo "⚠️  NO data will be deleted or reinstalled!"
  echo ""
  
  read -rp "Exit emergency mode? (yes/no): " confirm
  [ "$confirm" != "yes" ] && return
  
  log "EXITING EMERGENCY MODE"
  
  echo "🔄 Starting stopped services..."
  
  if ! systemctl is-active --quiet nginx; then
    systemctl start nginx 2>/dev/null && echo "  ✅ Nginx started" || echo "  ⚠️  Nginx start failed"
  else
    echo "  ℹ️  Nginx already running"
  fi
  
  if ! systemctl is-active --quiet apache2; then
    systemctl start apache2 2>/dev/null && echo "  ✅ Apache started" || echo "  ⚠️  Apache start failed (or not installed)"
  fi
  
  echo "  🐳 Starting stopped Docker containers..."
  local stopped_containers=$(docker ps -aq --filter "status=exited" 2>/dev/null)
  if [ -n "$stopped_containers" ]; then
    docker start $stopped_containers 2>/dev/null && echo "  ✅ Containers started" || echo "  ⚠️  Some containers failed to start"
  else
    echo "  ℹ️  No stopped containers found"
  fi
  
  sleep 2
  
  echo "🔥 Reopening firewall ports..."
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow 3000/tcp  # CapRover
  ufw --force enable
  
  echo ""
  echo "✅ NORMAL MODE ACTIVE"
  echo "Services checked and started where needed (nothing reinstalled)."
  echo "Firewall ports reopened."
  log_success "Emergency mode exited - normal operations resumed"
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

# ============= MENUS =============
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

security_menu(){
  while true; do
    clear_and_banner
    echo "=== SECURITY & HARDENING ==="
    echo "0) Back"
    echo "1) SSH Hardening"
    echo "2) Fail2Ban Management"
    echo "3) SSL Certificate (Let's Encrypt)"
    echo "4) Automatic Security Updates"
    echo "5) 🛡️  Install ALL Security Tools (NEW)"
    echo "6) 🔍 Run Security Scan (NEW)"
    echo "7) 📊 Security Tools Status (NEW)"
    echo "8) 🎯 Setup Advanced Monitoring (NEW)"
    echo "9) 📈 View Security Monitor Status"
    read -rp "Select (0-9): " c
    case "$c" in
      0) break ;;
      1) security_ssh_harden; pause ;;
      2) security_fail2ban; pause ;;
      3) security_ssl; pause ;;
      4) security_updates; pause ;;
      5) security_tools_install; pause ;;
      6) security_tools_scan; pause ;;
      7) security_tools_status; pause ;;
      8) security_monitoring_setup; pause ;;
      9) security_monitoring_status; pause ;;
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
    echo "3) 🟢 Exit Emergency Mode (NEW)"
    echo "4) Quick Rollback"
    echo "5) Setup Auto-Recovery"
    read -rp "Select (0-5): " c
    case "$c" in
      0) break ;;
      1) incident_health_check; pause ;;
      2) incident_emergency_mode; pause ;;
      3) incident_emergency_exit; pause ;;
      4) incident_rollback; pause ;;
      5) incident_auto_recovery; pause ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}
