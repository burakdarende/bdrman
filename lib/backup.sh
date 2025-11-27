# ============= BACKUP & RESTORE =============

backup_create(){
  local type="${1:-config}" # config, data, full
  echo "=== CREATE BACKUP ($type) ==="
  
  acquire_lock "backup_create" || return 1
  
  if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
  fi
  
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  BACKUP_FILE="$BACKUP_DIR/backup_${type}_$TIMESTAMP.tar.gz"
  ERROR_LOG="/tmp/bdrman_backup_error.log"
  
  BACKUP_LIST=()
  
  case "$type" in
    config)
      [ -f "$LOGFILE" ] && BACKUP_LIST+=("$LOGFILE")
      [ -d "/etc/bdrman" ] && BACKUP_LIST+=("/etc/bdrman")
      [ -d "/etc/wireguard" ] && BACKUP_LIST+=("/etc/wireguard")
      [ -d "/etc/ufw" ] && BACKUP_LIST+=("/etc/ufw")
      [ -d "/etc/nginx" ] && BACKUP_LIST+=("/etc/nginx")
      [ -f "/etc/ssh/sshd_config" ] && BACKUP_LIST+=("/etc/ssh/sshd_config")
      ;;
    data)
      # Backup common data directories
      BACKUP_LIST+=("/var/www")
      [ -d "/var/lib/docker/volumes" ] && BACKUP_LIST+=("/var/lib/docker/volumes")
      ;;
    full)
      # Full system backup (careful exclusions)
      BACKUP_LIST+=("/")
      EXCLUDE_PARAMS="--exclude=/proc --exclude=/sys --exclude=/dev --exclude=/tmp --exclude=/run --exclude=/mnt --exclude=/media --exclude=/lost+found --exclude=$BACKUP_DIR"
      ;;
  esac
  
  if [ ${#BACKUP_LIST[@]} -eq 0 ]; then
    error "No files found to backup for type: $type"
    return 1
  fi
  
  echo "   Backing up ($type): ${BACKUP_LIST[*]}"
  
  # Progress indicator (simple spinner as pv might not be installed)
  echo "   ⏳ Processing... Please wait."
  
  if [ "$type" == "full" ]; then
    tar czf "$BACKUP_FILE" $EXCLUDE_PARAMS "${BACKUP_LIST[@]}" 2>"$ERROR_LOG"
  else
    tar czf "$BACKUP_FILE" "${BACKUP_LIST[@]}" 2>"$ERROR_LOG"
  fi
  
  if [ $? -eq 0 ]; then
    success "Backup created: $BACKUP_FILE"
    log_success "Backup ($type) created: $BACKUP_FILE"
  else
    error "Backup failed!"
    cat "$ERROR_LOG"
    log_error "Backup failed. See $ERROR_LOG"
    rm -f "$BACKUP_FILE"
    return 1
  fi
  rm -f "$ERROR_LOG"
}

# Incremental backup with manifest
backup_create_incremental(){
  info "Creating incremental backup..."
  
  MANIFEST_FILE="$BACKUP_DIR/backup_manifest.txt"
  LAST_BACKUP=$(tail -n1 "$MANIFEST_FILE" 2>/dev/null | awk '{print $1}')
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  
  if [ -z "$LAST_BACKUP" ]; then
    info "No previous backup found. Creating full backup..."
    BACKUP_FILE="$BACKUP_DIR/full_$TIMESTAMP.tar.gz"
    BACKUP_TYPE="full"
  else
    info "Last backup: $LAST_BACKUP"
    BACKUP_FILE="$BACKUP_DIR/incr_$TIMESTAMP.tar.gz"
    BACKUP_TYPE="incremental"
  fi
  
  # Build file list
  BACKUP_LIST=()
  [ -f "$LOGFILE" ] && BACKUP_LIST+=("$LOGFILE")
  [ -d "/etc/bdrman" ] && BACKUP_LIST+=("/etc/bdrman")
  [ -d "/etc/wireguard" ] && BACKUP_LIST+=("/etc/wireguard")
  [ -d "/etc/nginx" ] && BACKUP_LIST+=("/etc/nginx")
  
  if [ "$BACKUP_TYPE" = "incremental" ] && [ -f "$LAST_BACKUP" ]; then
    tar -czf "$BACKUP_FILE" --newer="$LAST_BACKUP" "${BACKUP_LIST[@]}" 2>/dev/null
  else
    tar -czf "$BACKUP_FILE" "${BACKUP_LIST[@]}" 2>/dev/null
  fi
  
  if [ $? -eq 0 ]; then
    echo "$BACKUP_FILE $BACKUP_TYPE $TIMESTAMP" >> "$MANIFEST_FILE"
    success "Backup created: $BACKUP_FILE ($BACKUP_TYPE)"
    log_success "Incremental backup: $BACKUP_FILE"
  else
    error "Backup failed"
    return 1
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

backup_list(){
  echo "=== AVAILABLE BACKUPS ==="
  if [ -d "$BACKUP_DIR" ]; then
    ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "No backups found."
  else
    echo "Backup directory not found."
  fi
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

# Backup rotation strategy
backup_rotate(){
  info "Applying backup rotation strategy..."
  
  # Keep: 7 daily, 4 weekly, 12 monthly
  DAILY_KEEP=7
  WEEKLY_KEEP=4
  MONTHLY_KEEP=12
  
  # Daily: Delete backups older than 7 days
  find "$BACKUP_DIR" -name "backup_*.tar.gz" -mtime +$DAILY_KEEP -delete
  
  # Weekly: Keep first backup of each week
  # Monthly: Keep first backup of each month
  # (Simplified - full implementation would track by week/month)
  
  success "Backup rotation complete"
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

# ============= MENUS =============
backup_menu(){
  while true; do
    clear_and_banner
    echo "=== BACKUP & RESTORE ==="
    echo "0) Back"
    echo "1) Create Config Backup"
    echo "2) Create Data Backup"
    echo "3) Create Full System Snapshot"
    echo "4) List Local Backups"
    echo "5) Restore from Local"
    echo "6) Setup Google Drive"
    echo "7) Upload to Drive"
    echo "8) List Drive Backups"
    echo "9) Restore from Drive"
    echo "10) Export Config (Config-as-Code)"
    echo "11) Import Config"
    read -rp "Select (0-11): " c
    case "$c" in
      0) break ;;
      1) backup_create "config"; pause ;;
      2) backup_create "data"; pause ;;
      3) backup_create "full"; pause ;;
      4) backup_list; pause ;;
      5) backup_restore; pause ;;
      6) backup_setup_drive; pause ;;
      7) backup_upload_drive; pause ;;
      8) backup_list_drive; pause ;;
      9) backup_restore_drive; pause ;;
      10) config_export; pause ;;
      11) config_import; pause ;;
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
