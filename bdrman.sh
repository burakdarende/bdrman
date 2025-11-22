#!/usr/bin/env bash
# bdrman - Server Management Panel (English version)
# Author: Burak Darende
# Version: 3.2
GITHUB_REPO="https://github.com/burakdarende/bdrman"

# Root check
if [ "$EUID" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    echo "Root privileges required, relaunching with sudo..."
    exec sudo bash "$0" "$@"
  else
    echo "This script requires root access."
    exit 1
  fi
fi

# ============= UPDATE CHECKER =============
check_updates(){
  if [ "$CHECK_UPDATES" = false ]; then
    return
  fi
  
  # Get latest version from GitHub (tags)
  # Timeout set to 3 seconds to avoid hanging
  LATEST_VERSION=$(curl -s --max-time 3 "https://api.github.com/repos/burakdarende/bdrman/tags" | grep '"name":' | head -n 1 | cut -d '"' -f 4 | sed 's/v//')
  
  if [ -n "$LATEST_VERSION" ] && [ "$VERSION" != "$LATEST_VERSION" ]; then
    echo ""
    echo "🚨 NEW VERSION AVAILABLE: v$LATEST_VERSION"
    echo "   Current version: v$VERSION"
    echo "   Update command: bdrman --update"
    echo ""
    sleep 2
  fi
}


# Default configuration (can be overridden by config file)
LOGFILE="/var/log/bdrman.log"
BACKUP_DIR="/var/backups/bdrman"
CONFIG_FILE="/etc/bdrman/config.conf"
VOLUMES_DIR="/var/lib/docker/volumes"
LOCK_FILE="/var/lock/bdrman.lock"

# Monitoring defaults
MONITORING_INTERVAL=30
ALERT_COOLDOWN=300
DDOS_THRESHOLD=50
CPU_ALERT_THRESHOLD=90
MEMORY_ALERT_THRESHOLD=90
DISK_ALERT_THRESHOLD=90
FAILED_LOGIN_THRESHOLD=10

# Telegram defaults
TELEGRAM_CONFIG="/etc/bdrman/telegram.conf"
TELEGRAM_SCRIPT="/usr/local/bin/bdrman-telegram"
TELEGRAM_TIMEOUT=10
TELEGRAM_RETRIES=2

# Backup defaults
BACKUP_RETENTION_DAYS=7

# Operational defaults
DRY_RUN=false
NON_INTERACTIVE=false
DEBUG=false
ENABLE_LOCKING=true
COMMAND_TIMEOUT=60
DOCKER_TIMEOUT=120
BACKUP_TIMEOUT=600

# Load configuration file if exists
load_config(){
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    [ "$DEBUG" = true ] && echo "✅ Loaded config from $CONFIG_FILE"
  fi
}

# Call load_config early
load_config

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

# Dependency checker - runs at startup
check_dependencies(){
  local missing_required=()
  local missing_optional=()
  
  # Required commands
  local required=(docker tar rsync curl systemctl)
  for cmd in "${required[@]}"; do
    if ! command_exists "$cmd"; then
      missing_required+=("$cmd")
    fi
  done
  
  # Optional commands
  local optional=(jq certbot wg-quick fail2ban)
  for cmd in "${optional[@]}"; do
    if ! command_exists "$cmd"; then
      missing_optional+=("$cmd")
    fi
  done
  
  # Report missing required
  if [ ${#missing_required[@]} -gt 0 ]; then
    echo "❌ MISSING REQUIRED TOOLS:"
    for cmd in "${missing_required[@]}"; do
      echo "   • $cmd"
      case "$cmd" in
        docker) echo "     Install: curl -fsSL https://get.docker.com | sh" ;;
        tar) echo "     Install: apt-get install tar" ;;
        rsync) echo "     Install: apt-get install rsync" ;;
        curl) echo "     Install: apt-get install curl" ;;
        systemctl) echo "     ERROR: systemd required - not available on this system" ;;
      esac
    done
    echo ""
    read -rp "Continue anyway? (yes/no): " continue_anyway
    [ "$continue_anyway" != "yes" ] && exit 1
  fi
  
  # Report missing optional
  if [ ${#missing_optional[@]} -gt 0 ] && [ "$DEBUG" = true ]; then
    echo "⚠️  MISSING OPTIONAL TOOLS (some features disabled):"
    for cmd in "${missing_optional[@]}"; do
      echo "   • $cmd"
    done
    echo ""
  fi
}

# Acquire lock for critical operations
# Usage: acquire_lock "operation_name" || return 1
acquire_lock(){
  local operation="${1:-general}"
  
  if [ "$ENABLE_LOCKING" != true ]; then
    return 0
  fi
  
  # Try to acquire lock (non-blocking)
  exec 9>"${LOCK_FILE}"
  if ! flock -n 9; then
    echo "❌ Another bdrman operation is running."
    echo "   If you're sure no other instance is running, remove: ${LOCK_FILE}"
    log_error "Failed to acquire lock for: $operation (another instance running)"
    return 1
  fi
  
  # Write PID and operation to lock file
  echo "$$:$operation:$(date +%s)" >&9
  log "Lock acquired for: $operation (PID: $$)"
  return 0
}

# Release lock (automatic on script exit, but can be called manually)
release_lock(){
  if [ "$ENABLE_LOCKING" = true ]; then
    exec 9>&-
    log "Lock released"
  fi
}

# Trap to ensure lock is released on exit
trap release_lock EXIT

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

caprover_backup(){
  echo "=== CAPROVER BACKUP SYSTEM ==="
  echo ""
  
  # Acquire lock to prevent concurrent backups
  acquire_lock "caprover_backup" || return 1
  
  VOLUMES_DIR="/var/lib/docker/volumes"
  BACKUP_BASE_DIR="/root/capBackup"
  
  # Check if volumes directory exists
  if [ ! -d "$VOLUMES_DIR" ]; then
    echo "❌ Docker volumes directory not found: $VOLUMES_DIR"
    echo "   Make sure Docker is installed and CapRover is running."
    return 1
  fi
  
  # Create backup base directory
  mkdir -p "$BACKUP_BASE_DIR"
  log "Created backup directory: $BACKUP_BASE_DIR"
  
  # Create today's backup folder with Turkey timezone (UTC+3)
  # Format: dd-mm-yyyy for folder, hh-mm for time
  export TZ='Europe/Istanbul'
  DATE_FOLDER=$(date +%d-%m-%Y)
  TIME_STAMP=$(date +%H-%M)
  BACKUP_DIR_TODAY="$BACKUP_BASE_DIR/$DATE_FOLDER"
  mkdir -p "$BACKUP_DIR_TODAY"
  
  echo "📁 Listing available CapRover volumes..."
  echo ""
  
  # List all volumes
  VOLUMES=($(ls -1 "$VOLUMES_DIR" 2>/dev/null | grep -E "(captain-|cap-)" | sort))
  
  if [ ${#VOLUMES[@]} -eq 0 ]; then
    echo "⚠️  No CapRover volumes found in $VOLUMES_DIR"
    echo "   Looking for volumes with 'captain-' or 'cap-' prefix"
    echo ""
    echo "All volumes in the directory:"
    ls -la "$VOLUMES_DIR" 2>/dev/null || echo "Cannot list directory"
    return
  fi
  
  echo "Found ${#VOLUMES[@]} CapRover volume(s):"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Display volumes with sizes
  for i in "${!VOLUMES[@]}"; do
    VOLUME="${VOLUMES[$i]}"
    VOLUME_PATH="$VOLUMES_DIR/$VOLUME/_data"
    
    if [ -d "$VOLUME_PATH" ]; then
      SIZE=$(du -sh "$VOLUME_PATH" 2>/dev/null | cut -f1 || echo "N/A")
      echo "$(($i + 1)). $VOLUME (Size: $SIZE)"
    else
      echo "$(($i + 1)). $VOLUME (⚠️  _data folder not found)"
    fi
  done
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Options:"
  echo "a) Backup ALL volumes"
  echo "0) Cancel"
  echo ""
  read -rp "Select volume(s) to backup (number, 'a' for all, or '0' to cancel): " choice
  
  case "$choice" in
    0)
      echo "Backup cancelled."
      return
      ;;
    a|A)
      echo "🔄 Backing up ALL volumes..."
      SELECTED_VOLUMES=("${VOLUMES[@]}")
      ;;
    *)
      if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#VOLUMES[@]}" ]; then
        SELECTED_VOLUME="${VOLUMES[$((choice - 1))]}"
        echo "🔄 Backing up: $SELECTED_VOLUME"
        SELECTED_VOLUMES=("$SELECTED_VOLUME")
      else
        echo "❌ Invalid selection."
        return
      fi
      ;;
  esac
  
  echo ""
  echo "Starting backup process..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  TOTAL_BACKED_UP=0
  TOTAL_SIZE=0
  
  for VOLUME in "${SELECTED_VOLUMES[@]}"; do
    echo ""
    echo "📦 Processing: $VOLUME"
    
    VOLUME_PATH="$VOLUMES_DIR/$VOLUME/_data"
    
    if [ ! -d "$VOLUME_PATH" ]; then
      echo "   ⚠️  Skipping - _data directory not found"
      continue
    fi
    
    # Create backup filename with timestamp
    BACKUP_FILE="$BACKUP_DIR_TODAY/${VOLUME}_${TIME_STAMP}.tar.gz"
    
    echo "   Source: $VOLUME_PATH"
    echo "   Target: $BACKUP_FILE"
    
    # Get volume size before compression
    VOLUME_SIZE=$(du -sb "$VOLUME_PATH" 2>/dev/null | cut -f1 || echo "0")
    VOLUME_SIZE_HUMAN=$(du -sh "$VOLUME_PATH" 2>/dev/null | cut -f1 || echo "N/A")
    
    echo "   Size: $VOLUME_SIZE_HUMAN"
    echo "   Compressing..."
    
    # Create atomic backup with .partial file
    BACKUP_PARTIAL="${BACKUP_FILE}.partial"
    
    if timeout "${BACKUP_TIMEOUT:-600}" tar -czf "$BACKUP_PARTIAL" -C "$VOLUMES_DIR/$VOLUME" _data 2>/dev/null; then
      # Move partial to final only on success
      mv "$BACKUP_PARTIAL" "$BACKUP_FILE"
      
      # Get compressed size
      COMPRESSED_SIZE=$(du -sh "$BACKUP_FILE" 2>/dev/null | cut -f1 || echo "N/A")
      
      echo "   ✅ Success! Compressed to: $COMPRESSED_SIZE"
      
      # Add to totals
      TOTAL_BACKED_UP=$((TOTAL_BACKED_UP + 1))
      TOTAL_SIZE=$((TOTAL_SIZE + VOLUME_SIZE))
      
      log_success "CapRover backup created: $BACKUP_FILE (Original: $VOLUME_SIZE_HUMAN, Compressed: $COMPRESSED_SIZE)"
      
    else
      # Cleanup partial file on failure
      rm -f "$BACKUP_PARTIAL"
      echo "   ❌ Failed to create backup!"
      log_error "CapRover backup failed: $VOLUME"
    fi
  done
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🎯 BACKUP SUMMARY"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "✅ Volumes backed up: $TOTAL_BACKED_UP/${#SELECTED_VOLUMES[@]}"
  
  if [ $TOTAL_SIZE -gt 0 ]; then
    TOTAL_SIZE_HUMAN=$(echo $TOTAL_SIZE | awk '{
      if ($1 >= 1024^3) printf "%.1f GB", $1/(1024^3)
      else if ($1 >= 1024^2) printf "%.1f MB", $1/(1024^2)  
      else if ($1 >= 1024) printf "%.1f KB", $1/1024
      else printf "%d bytes", $1
    }')
    echo "📊 Total original size: $TOTAL_SIZE_HUMAN"
  fi
  
  echo "📁 Backup location: $BACKUP_DIR_TODAY"
  echo "📅 Date: $(TZ='Europe/Istanbul' date '+%d/%m/%Y %H:%M')"
  echo "🕒 Timestamp: $TIME_STAMP"
  
  # Show backup folder contents
  echo ""
  echo "📋 Created backup files:"
  ls -lh "$BACKUP_DIR_TODAY"/*.tar.gz 2>/dev/null | while read -r line; do
    echo "   $line"
  done
  
  log_success "CapRover backup session completed: $TOTAL_BACKED_UP volumes backed up"
}

caprover_list_backups(){
  echo "=== CAPROVER BACKUP HISTORY ==="
  echo ""
  
  BACKUP_BASE_DIR="/root/capBackup"
  
  if [ ! -d "$BACKUP_BASE_DIR" ]; then
    echo "📁 No backups found. Backup directory doesn't exist yet."
    echo "   Create your first backup using the backup option."
    return
  fi
  
  echo "📁 Backup directory: $BACKUP_BASE_DIR"
  echo ""
  
  # List date folders (dd-mm-yyyy format)
  DATE_FOLDERS=($(ls -1 "$BACKUP_BASE_DIR" 2>/dev/null | grep -E "^[0-9]{2}-[0-9]{2}-[0-9]{4}$" | sort -r))
  
  if [ ${#DATE_FOLDERS[@]} -eq 0 ]; then
    echo "📅 No backup dates found."
    return
  fi
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📅 BACKUP HISTORY (${#DATE_FOLDERS[@]} days)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  TOTAL_BACKUPS=0
  TOTAL_SIZE=0
  
  for DATE_FOLDER in "${DATE_FOLDERS[@]}"; do
    FOLDER_PATH="$BACKUP_BASE_DIR/$DATE_FOLDER"
    
    if [ -d "$FOLDER_PATH" ]; then
      # Count backup files
      BACKUP_COUNT=$(ls -1 "$FOLDER_PATH"/*.tar.gz 2>/dev/null | wc -l)
      
      if [ "$BACKUP_COUNT" -gt 0 ]; then
        # Calculate folder size
        FOLDER_SIZE=$(du -sh "$FOLDER_PATH" 2>/dev/null | cut -f1)
        FOLDER_SIZE_BYTES=$(du -sb "$FOLDER_PATH" 2>/dev/null | cut -f1 || echo "0")
        
        echo "📅 $DATE_FOLDER"
        echo "   📦 Backups: $BACKUP_COUNT files"
        echo "   💾 Size: $FOLDER_SIZE"
        
        # List individual backups
        ls -lh "$FOLDER_PATH"/*.tar.gz 2>/dev/null | while read -r line; do
          filename=$(echo "$line" | awk '{print $9}' | xargs basename)
          size=$(echo "$line" | awk '{print $5}')
          echo "      └─ $filename ($size)"
        done
        
        echo ""
        
        TOTAL_BACKUPS=$((TOTAL_BACKUPS + BACKUP_COUNT))
        TOTAL_SIZE=$((TOTAL_SIZE + FOLDER_SIZE_BYTES))
      fi
    fi
  done
  
  if [ $TOTAL_BACKUPS -gt 0 ]; then
    TOTAL_SIZE_HUMAN=$(echo $TOTAL_SIZE | awk '{
      if ($1 >= 1024^3) printf "%.1f GB", $1/(1024^3)
      else if ($1 >= 1024^2) printf "%.1f MB", $1/(1024^2)  
      else if ($1 >= 1024) printf "%.1f KB", $1/1024
      else printf "%d bytes", $1
    }')
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 TOTAL SUMMARY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Total backup files: $TOTAL_BACKUPS"
    echo "💾 Total size: $TOTAL_SIZE_HUMAN"
    echo "📅 Backup days: ${#DATE_FOLDERS[@]}"
    echo "📁 Backup path: $BACKUP_BASE_DIR"
  fi
}

caprover_restore_backup(){
  echo "=== CAPROVER RESTORE FROM BACKUP ==="
  echo ""
  
  BACKUP_BASE_DIR="/root/capBackup"
  VOLUMES_DIR="/var/lib/docker/volumes"
  
  if [ ! -d "$BACKUP_BASE_DIR" ]; then
    echo "❌ No backups found. Backup directory doesn't exist."
    return
  fi
  
  if [ ! -d "$VOLUMES_DIR" ]; then
    echo "❌ Docker volumes directory not found: $VOLUMES_DIR"
    return
  fi
  
  echo "🔍 Searching for available backups..."
  
  # Find all backup files
  BACKUP_FILES=()
  while IFS= read -r -d '' file; do
    BACKUP_FILES+=("$file")
  done < <(find "$BACKUP_BASE_DIR" -name "*.tar.gz" -type f -print0 2>/dev/null)
  
  if [ ${#BACKUP_FILES[@]} -eq 0 ]; then
    echo "📦 No backup files found."
    return
  fi
  
  echo "Found ${#BACKUP_FILES[@]} backup file(s):"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Display backup files with details
  for i in "${!BACKUP_FILES[@]}"; do
    FILE="${BACKUP_FILES[$i]}"
    FILENAME=$(basename "$FILE")
    DATE_PART=$(dirname "$FILE" | xargs basename)
    SIZE=$(du -sh "$FILE" 2>/dev/null | cut -f1)
    MODIFIED=$(stat -c "%y" "$FILE" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
    
    echo "$(($i + 1)). $FILENAME"
    echo "    📅 Date: $DATE_PART"
    echo "    💾 Size: $SIZE"
    echo "    🕒 Modified: $MODIFIED"
    echo ""
  done
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "0) Cancel"
  echo ""
  read -rp "Select backup file to restore (1-${#BACKUP_FILES[@]}): " choice
  
  if [[ "$choice" == "0" ]]; then
    echo "Restore cancelled."
    return
  fi
  
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#BACKUP_FILES[@]}" ]; then
    echo "❌ Invalid selection."
    return
  fi
  
  SELECTED_FILE="${BACKUP_FILES[$((choice - 1))]}"
  FILENAME=$(basename "$SELECTED_FILE")
  
  # Extract volume name from filename (remove timestamp HH-MM and extension)
  VOLUME_NAME=$(echo "$FILENAME" | sed 's/_[0-9][0-9]-[0-9][0-9]\.tar\.gz$//')
  
  echo ""
  echo "📦 Selected backup: $FILENAME"
  echo "🔄 Target volume: $VOLUME_NAME"
  echo "📁 Volume path: $VOLUMES_DIR/$VOLUME_NAME"
  echo ""
  
  # Check if volume exists
  if [ -d "$VOLUMES_DIR/$VOLUME_NAME" ]; then
    echo "⚠️  WARNING: Volume '$VOLUME_NAME' already exists!"
    echo "   This will OVERWRITE the existing volume data."
    echo ""
    read -rp "Do you want to continue? Type 'YES' to confirm: " confirm
    
    if [ "$confirm" != "YES" ]; then
      echo "Restore cancelled."
      return
    fi
    
    # Create backup of existing volume with Turkey time
    echo "🔄 Creating safety backup of existing volume..."
    export TZ='Europe/Istanbul'
    SAFETY_BACKUP="$BACKUP_BASE_DIR/safety_backup_${VOLUME_NAME}_$(date +%d%m%Y_%H%M).tar.gz"
    tar -czf "$SAFETY_BACKUP" -C "$VOLUMES_DIR/$VOLUME_NAME" _data 2>/dev/null
    echo "   ✅ Safety backup created: $SAFETY_BACKUP"
    
    # Remove existing data
    echo "🗑️  Removing existing volume data..."
    rm -rf "$VOLUMES_DIR/$VOLUME_NAME/_data"/*
  else
    echo "📁 Volume doesn't exist. Creating new volume structure..."
    mkdir -p "$VOLUMES_DIR/$VOLUME_NAME"
  fi
  
  echo ""
  echo "🔄 Restoring from backup..."
  echo "   Source: $SELECTED_FILE"
  echo "   Target: $VOLUMES_DIR/$VOLUME_NAME/"
  
  # Extract backup
  if tar -xzf "$SELECTED_FILE" -C "$VOLUMES_DIR/$VOLUME_NAME/" 2>/dev/null; then
    echo "   ✅ Extraction successful!"
    
    # Set proper permissions
    echo "🔐 Setting permissions..."
    chown -R root:root "$VOLUMES_DIR/$VOLUME_NAME"
    
    # Verify restoration
    if [ -d "$VOLUMES_DIR/$VOLUME_NAME/_data" ]; then
      RESTORED_SIZE=$(du -sh "$VOLUMES_DIR/$VOLUME_NAME/_data" 2>/dev/null | cut -f1)
      echo "   📊 Restored size: $RESTORED_SIZE"
      
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "✅ RESTORE COMPLETED SUCCESSFULLY!"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "📦 Volume: $VOLUME_NAME"
      echo "📁 Location: $VOLUMES_DIR/$VOLUME_NAME/_data"
      echo "💾 Size: $RESTORED_SIZE"
      echo "🕒 Restored: $(date '+%Y-%m-%d %H:%M:%S')"
      echo ""
      echo "⚠️  NOTE: You may need to restart the related Docker container"
      echo "          for the changes to take effect."
      
      log_success "CapRover volume restored: $VOLUME_NAME from $FILENAME"
      
    else
      echo "   ❌ Verification failed - _data directory not found after extraction"
      log_error "CapRover restore verification failed: $VOLUME_NAME"
    fi
    
  else
    echo "   ❌ Extraction failed!"
    log_error "CapRover restore failed: $SELECTED_FILE"
  fi
}

caprover_cleanup_backups(){
  echo "=== CAPROVER BACKUP CLEANUP ==="
  echo ""
  
  BACKUP_BASE_DIR="/root/capBackup"
  
  if [ ! -d "$BACKUP_BASE_DIR" ]; then
    echo "📁 No backup directory found."
    return
  fi
  
  echo "🔍 Analyzing backup storage..."
  
  # Get total backup size
  TOTAL_SIZE=$(du -sh "$BACKUP_BASE_DIR" 2>/dev/null | cut -f1)
  TOTAL_FILES=$(find "$BACKUP_BASE_DIR" -name "*.tar.gz" -type f 2>/dev/null | wc -l)
  
  echo "📊 Current backup usage:"
  echo "   💾 Total size: $TOTAL_SIZE"
  echo "   📦 Total files: $TOTAL_FILES"
  echo "   📁 Location: $BACKUP_BASE_DIR"
  echo ""
  
  if [ "$TOTAL_FILES" -eq 0 ]; then
    echo "No backup files to clean up."
    return
  fi
  
  echo "🧹 Cleanup options:"
  echo "1) Delete backups older than 30 days"
  echo "2) Delete backups older than 7 days"
  echo "3) Keep only last 5 days of backups"
  echo "4) Delete specific date folder"
  echo "5) Cancel"
  echo ""
  read -rp "Select cleanup option (1-5): " choice
  
  case "$choice" in
    1)
      echo "🗑️  Deleting backups older than 30 days..."
      DELETED=$(find "$BACKUP_BASE_DIR" -name "*.tar.gz" -type f -mtime +30 -delete -print 2>/dev/null | wc -l)
      echo "   ✅ Deleted $DELETED files"
      ;;
    2)
      echo "🗑️  Deleting backups older than 7 days..."
      DELETED=$(find "$BACKUP_BASE_DIR" -name "*.tar.gz" -type f -mtime +7 -delete -print 2>/dev/null | wc -l)
      echo "   ✅ Deleted $DELETED files"
      ;;
    3)
      echo "🗑️  Keeping only last 5 days of backups..."
      # Get date folders, sort them, keep last 5 (dd-mm-yyyy format)
      DATE_FOLDERS=($(ls -1 "$BACKUP_BASE_DIR" 2>/dev/null | grep -E "^[0-9]{2}-[0-9]{2}-[0-9]{4}$" | sort -r))
      
      if [ ${#DATE_FOLDERS[@]} -gt 5 ]; then
        for ((i=5; i<${#DATE_FOLDERS[@]}; i++)); do
          FOLDER_TO_DELETE="$BACKUP_BASE_DIR/${DATE_FOLDERS[$i]}"
          if [ -d "$FOLDER_TO_DELETE" ]; then
            rm -rf "$FOLDER_TO_DELETE"
            echo "   🗑️  Deleted folder: ${DATE_FOLDERS[$i]}"
          fi
        done
      else
        echo "   ℹ️  Less than 5 days of backups found, nothing to delete."
      fi
      ;;
    4)
      echo "Available backup dates (dd-mm-yyyy):"
      ls -1 "$BACKUP_BASE_DIR" 2>/dev/null | grep -E "^[0-9]{2}-[0-9]{2}-[0-9]{4}$" | sort -r
      echo ""
      read -rp "Enter date to delete (DD-MM-YYYY): " date_to_delete
      
      if [[ "$date_to_delete" =~ ^[0-9]{2}-[0-9]{2}-[0-9]{4}$ ]]; then
        FOLDER_TO_DELETE="$BACKUP_BASE_DIR/$date_to_delete"
        if [ -d "$FOLDER_TO_DELETE" ]; then
          read -rp "⚠️  Delete all backups from $date_to_delete? (yes/no): " confirm
          if [ "$confirm" = "yes" ]; then
            rm -rf "$FOLDER_TO_DELETE"
            echo "   ✅ Deleted backup folder: $date_to_delete"
            log "Deleted CapRover backup folder: $date_to_delete"
          else
            echo "Deletion cancelled."
          fi
        else
          echo "❌ Backup folder for $date_to_delete not found."
        fi
      else
        echo "❌ Invalid date format. Use DD-MM-YYYY"
      fi
      ;;
    5)
      echo "Cleanup cancelled."
      return
      ;;
    *)
      echo "❌ Invalid choice."
      return
      ;;
  esac
  
  # Show updated statistics
  echo ""
  echo "📊 Updated backup usage:"
  NEW_TOTAL_SIZE=$(du -sh "$BACKUP_BASE_DIR" 2>/dev/null | cut -f1)
  NEW_TOTAL_FILES=$(find "$BACKUP_BASE_DIR" -name "*.tar.gz" -type f 2>/dev/null | wc -l)
  echo "   💾 Total size: $NEW_TOTAL_SIZE (was: $TOTAL_SIZE)"
  echo "   📦 Total files: $NEW_TOTAL_FILES (was: $TOTAL_FILES)"
  
  # Clean up empty date folders
  find "$BACKUP_BASE_DIR" -type d -empty -delete 2>/dev/null
  
  log_success "CapRover backup cleanup completed"
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
  
  # Acquire lock to prevent concurrent backups
  acquire_lock "backup_create" || return 1
  
  mkdir -p "$BACKUP_DIR"
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"
  BACKUP_PARTIAL="${BACKUP_FILE}.partial"
  
  echo "Creating backup at: $BACKUP_FILE"
  echo "(Using atomic write - .partial → final)"
  
  # Create backup with timeout and atomic write
  if timeout "${BACKUP_TIMEOUT:-600}" tar -czf "$BACKUP_PARTIAL" \
    /etc/wireguard 2>/dev/null \
    /etc/ufw 2>/dev/null \
    /etc/nginx 2>/dev/null \
    /etc/ssh/sshd_config 2>/dev/null \
    "$LOGFILE" 2>/dev/null; then
    
    # Move to final location only on success
    mv "$BACKUP_PARTIAL" "$BACKUP_FILE"
    echo "✅ Backup created: $BACKUP_FILE"
    log_success "Backup created: $BACKUP_FILE"
  else
    # Cleanup partial file
    rm -f "$BACKUP_PARTIAL"
    echo "❌ Backup failed!"
    log_error "Backup creation failed"
    return 1
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
    echo "❌ Missing information."
    return 1
  fi
  
  # Validate remote format (should be user@host or just host)
  if [[ ! "$remote" =~ ^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+$|^[a-zA-Z0-9.-]+$ ]]; then
    echo "❌ Invalid remote format. Use: user@hostname or hostname"
    log_error "Invalid remote format: $remote"
    return 1
  fi
  
  # Sanitize remote_path (prevent directory traversal)
  if [[ "$remote_path" =~ \.\. ]] || [[ "$remote_path" =~ [^a-zA-Z0-9/_.-] ]]; then
    echo "❌ Invalid path. Avoid special characters and .."
    log_error "Rejected unsafe remote path: $remote_path"
    return 1
  fi
  
  backup_list
  read -rp "Backup file to send: " backup_file
  
  # Sanitize backup_file input (prevent path traversal)
  backup_file=$(basename "$backup_file")  # Strip any path components
  LOCAL_FILE="$BACKUP_DIR/$backup_file"
  
  if [ ! -f "$LOCAL_FILE" ]; then
    echo "❌ File not found: $LOCAL_FILE"
    return 1
  fi
  
  # Use safe scp with escaped arguments
  echo "Sending $LOCAL_FILE to $remote:$remote_path"
  echo "Command: scp -- $(printf '%q' "$LOCAL_FILE") $(printf '%q' "$remote"):$(printf '%q' "$remote_path")"
  
  # Execute with timeout and proper escaping
  if timeout "${COMMAND_TIMEOUT:-60}" scp -- "$(printf '%q' "$LOCAL_FILE")" "$(printf '%q' "$remote"):$(printf '%q' "$remote_path")"; then
    echo "✅ Sent successfully!"
    log_success "Backup sent to $remote:$remote_path"
  else
    echo "❌ Transfer failed!"
    log_error "Backup transfer failed to $remote:$remote_path"
    return 1
  fi
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

# ============= SECURITY TOOLS AUTO INSTALL =============
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
  echo ""
  echo "Installed tools:"
  echo "✅ Fail2Ban - Active and monitoring"
  echo "✅ ClamAV - Virus definitions updated"
  echo "✅ RKHunter - Database initialized"
  echo "✅ Lynis - Ready for audits"
  echo "✅ AppArmor - Profiles loaded"
  echo "✅ Aide - File integrity database created"
  echo "✅ Auditd - System auditing active"
  echo "✅ Psad - Port scan detection active"
  echo ""
  echo "Next steps:"
  echo "1. Run initial scans: security_tools_scan"
  echo "2. Configure automated scans in cron"
  echo "3. Review Fail2Ban status: fail2ban-client status"
  echo "4. Run Lynis audit: lynis audit system"
  echo ""
  
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
    echo "Configuration:"
    echo "  • Check interval: ${MONITORING_INTERVAL}s"
    echo "  • Alert cooldown: ${ALERT_COOLDOWN}s (per alert type)"
    echo "  • DDoS threshold: ${DDOS_THRESHOLD} connections/IP"
    echo "  • CPU threshold: ${CPU_ALERT_THRESHOLD}%"
    echo "  • Memory threshold: ${MEMORY_ALERT_THRESHOLD}%"
    echo "  • Disk threshold: ${DISK_ALERT_THRESHOLD}%"
    echo ""
    echo "Monitoring for: DDoS, High CPU, High Memory, Disk Space, Failed Logins, Service Status"
    echo "Logs: $ALERT_LOG"
    echo ""
    
    while true; do
        check_ddos
        check_cpu
        check_memory
        check_disk
        check_failed_logins
        check_services
        
        # Configurable sleep interval (default 30s, was 2s)
        sleep "$MONITORING_INTERVAL"
        
        sleep 2  # Check every 2 seconds
    done
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main
fi
EOFMONITOR
  
  chmod +x /etc/bdrman/security_monitor.sh
  
  echo "📝 Creating systemd service..."
  
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
  echo ""
  echo "📊 Monitoring for:"
  echo "   • DDoS attacks (connection floods)"
  echo "   • High CPU usage (>90%)"
  echo "   • High Memory usage (>90%)"
  echo "   • Disk space critical (>90%)"
  echo "   • Brute force attempts"
  echo "   • Service failures"
  echo ""
  echo "🔔 Telegram alerts: Every 2 seconds when threats detected"
  echo "📝 Logs: /var/log/bdrman_security_alerts.log"
  echo ""
  echo "To check status: systemctl status bdrman-security-monitor"
  echo "To view logs: journalctl -u bdrman-security-monitor -f"
  
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

# ============= DATABASE MANAGEMENT =============


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
  
  # Idempotent service start (only if not already running)
  if ! systemctl is-active --quiet nginx; then
    systemctl start nginx 2>/dev/null && echo "  ✅ Nginx started" || echo "  ⚠️  Nginx start failed"
  else
    echo "  ℹ️  Nginx already running"
  fi
  
  if ! systemctl is-active --quiet apache2; then
    systemctl start apache2 2>/dev/null && echo "  ✅ Apache started" || echo "  ⚠️  Apache start failed (or not installed)"
  fi
  
  # Start stopped Docker containers (NOT rebuild!)
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
    echo "❌ Both token and chat ID are required."
    return 1
  fi
  
  # Validate token format (should look like: 123456789:ABCdefGHI...)
  if [[ ! "$bot_token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
    echo "⚠️  Warning: Token format looks invalid"
    read -rp "Continue anyway? (yes/no): " continue_setup
    [ "$continue_setup" != "yes" ] && return 1
  fi
  
  # Validate chat ID format (should be numeric or start with -)
  if [[ ! "$chat_id" =~ ^-?[0-9]+$ ]]; then
    echo "⚠️  Warning: Chat ID should be numeric"
    read -rp "Continue anyway? (yes/no): " continue_setup
    [ "$continue_setup" != "yes" ] && return 1
  fi
  
  # Test token before saving
  echo "Testing bot token..."
  if ! curl --fail --max-time 10 -s "https://api.telegram.org/bot${bot_token}/getMe" > /dev/null 2>&1; then
    echo "❌ Failed to verify bot token. Please check and try again."
    log_error "Telegram setup failed: invalid bot token"
    return 1
  fi
  
  echo "✅ Token verified!"
  
  # Save config securely
  mkdir -p /etc/bdrman
  cat > /etc/bdrman/telegram.conf << EOF
BOT_TOKEN="$bot_token"
CHAT_ID="$chat_id"
EOF
  
  # Secure permissions (only root can read)
  chmod 600 /etc/bdrman/telegram.conf
  chown root:root /etc/bdrman/telegram.conf
  
  echo "✅ Config saved securely (chmod 600)"
  
  # Create notification function with safe curl
  cat > /usr/local/bin/bdrman-telegram << 'EOF'
#!/bin/bash
if [ ! -f /etc/bdrman/telegram.conf ]; then
  echo "Telegram not configured"
  exit 1
fi

# Check permissions
if [ "$(stat -c %a /etc/bdrman/telegram.conf)" != "600" ]; then
  echo "⚠️  Warning: telegram.conf has insecure permissions!"
  chmod 600 /etc/bdrman/telegram.conf
fi

source /etc/bdrman/telegram.conf

MESSAGE="$1"
HOSTNAME=$(hostname)

# Use safe curl with timeout and retries
curl --fail --max-time 10 --retry 2 -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="${CHAT_ID}" \
  -d text="🖥️ *${HOSTNAME}*%0A%0A${MESSAGE}" \
  -d parse_mode="Markdown" > /dev/null

if [ $? -ne 0 ]; then
  echo "Failed to send Telegram message"
  exit 1
fi

EOF
  
  chmod +x /usr/local/bin/bdrman-telegram
  
  # Create weekly report script
  telegram_create_weekly_report
  
  # Setup cron for weekly report (Monday at 12:00)
  (crontab -l 2>/dev/null | grep -v "telegram_weekly_report.sh"; echo "0 12 * * 1 /etc/bdrman/telegram_weekly_report.sh") | crontab -
  
  # Test notification
  if /usr/local/bin/bdrman-telegram "✅ Telegram bot configured!%0A%0A📅 Weekly reports: Monday at 12:00%0A💬 Commands: Send /help to see all available commands"; then
    echo "✅ Telegram bot configured successfully"
    echo "✅ Weekly reports enabled (Monday at 12:00)"
    echo "✅ Test message sent!"
  else
    echo "⚠️  Configuration saved but test message failed"
    echo "   Check your chat ID and try: bdrman-telegram \"test\""
  fi
  
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
  echo "Checking Python dependencies..."
  if ! command_exists python3; then
    echo "Installing Python3..."
    apt update && apt install -y python3 python3-pip
  fi
  
  # Make sure pip3 is available
  if ! command_exists pip3; then
    echo "Installing pip3..."
    apt update && apt install -y python3-pip
  fi
  
  # Verify pip3 is working
  if command_exists pip3; then
    echo "Installing python-telegram-bot..."
    pip3 install python-telegram-bot --upgrade 2>/dev/null || pip3 install python-telegram-bot
    echo "✅ Python dependencies installed"
  else
    echo "❌ pip3 installation failed. Please install manually: apt install python3-pip"
    return
  fi
  
  # Create webhook server
  cat > /etc/bdrman/telegram_bot.py << 'EOFPYTHON'
#!/usr/bin/env python3
import os
import subprocess
import shlex
import socket
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes, ConversationHandler, MessageHandler, filters

# Load config
config = {}
with open('/etc/bdrman/telegram.conf', 'r') as f:
    for line in f:
        if '=' in line and not line.startswith('#'):
            key, value = line.strip().split('=', 1)
            config[key] = value.strip('"')

BOT_TOKEN = config.get('BOT_TOKEN')
ALLOWED_CHAT_ID = config.get('CHAT_ID')
PIN_CODE = config.get('PIN_CODE', '1234') # Default PIN if not set
SERVER_NAME = config.get('SERVER_NAME', socket.gethostname())

# States for ConversationHandler
PIN_CHECK = 1

def run_command(cmd_list):
    """Run command securely using list format (shell=False)"""
    try:
        # If cmd_list is string, split it safely, but prefer list input
        if isinstance(cmd_list, str):
            cmd_list = shlex.split(cmd_list)
            
        result = subprocess.run(cmd_list, capture_output=True, text=True, timeout=30)
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
        f"🤖 *BDRman Bot Active*\n"
        f"🖥️ *Server:* `{SERVER_NAME}`\n\n"
        "Use /help to see available commands",
        parse_mode='Markdown'
    )

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    help_text = f"""
🤖 *BDRman Bot - Command List*
🖥️ *Server:* `{SERVER_NAME}`

📊 *MONITORING:*
/status - Detailed system status report
/health - System health check
/docker - Docker containers status
/services - All system services
/logs - Recent system errors
/disk - Disk usage details
/memory - Memory usage
/uptime - System uptime

🔧 *MANAGEMENT:*
/restart [service] - Restart service
/vpn <username> - Create VPN user
/backup - Create system backup
/snapshot - Create full system snapshot (PIN Required)
/update - System update (apt)

🛡️ *SECURITY:*
/ddos_enable - Enable DDoS protection
/ddos_disable - Disable DDoS protection
/firewall - Firewall status
/block <ip> - Block IP address
/ssl <domain> - Get SSL certificate

🚨 *EMERGENCY:*
/emergency_exit - Exit emergency mode (PIN Required)

ℹ️ *INFO:*
/help - This help message
/about - About this bot
    """
    await update.message.reply_text(help_text, parse_mode='Markdown')

async def status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    await update.message.reply_text(f"📊 Collecting status for *{SERVER_NAME}*...", parse_mode='Markdown')
    
    # Safe commands without shell=True
    uptime = run_command(["uptime", "-p"]).strip()
    kernel = run_command(["uname", "-r"]).strip()
    
    # For complex pipes, we still need shell=True or python logic. 
    # For safety, we'll use python logic where possible or fixed commands.
    
    # Disk
    disk_res = run_command("df -h /")
    disk_lines = disk_res.splitlines()
    disk_info = disk_lines[1].split() if len(disk_lines) > 1 else ["?"]*6
    disk_usage = disk_info[4]
    
    # Memory
    mem_res = run_command("free -h")
    
    report = f"""
📊 *SYSTEM STATUS - {SERVER_NAME}*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🖥️ *System*
• Kernel: `{kernel}`
• Uptime: {uptime}

💾 *Disk (/)*
• Usage: {disk_usage}
• Free: {disk_info[3]}

🧠 *Memory*
```
{mem_res}
```
    """
    await update.message.reply_text(report, parse_mode='Markdown')

async def vpn_create(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    if len(context.args) == 0:
        await update.message.reply_text("Usage: /vpn <username>")
        return
    
    username = context.args[0]
    # Sanitize username (alphanumeric only)
    if not username.isalnum():
        await update.message.reply_text("❌ Invalid username. Alphanumeric only.")
        return

    await update.message.reply_text(f"🔐 Creating VPN user: {username}...")
    
    if os.path.exists("/usr/local/bin/wireguard-install.sh"):
        # Secure execution
        p = subprocess.Popen(["/usr/local/bin/wireguard-install.sh"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        stdout, stderr = p.communicate(input=f"{username}\n")
        
        if p.returncode == 0:
            await update.message.reply_text(f"✅ VPN user '{username}' created!\nCheck /root/ for config.")
        else:
            await update.message.reply_text(f"❌ Error:\n{stderr}")
    else:
        await update.message.reply_text("❌ WireGuard script not found.")

async def get_ssl(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    if len(context.args) == 0:
        await update.message.reply_text("Usage: /ssl <domain>")
        return
    
    domain = context.args[0]
    # Basic domain validation
    if not all(c.isalnum() or c in '.-' for c in domain):
        await update.message.reply_text("❌ Invalid domain format.")
        return
        
    await update.message.reply_text(f"🔐 Requesting SSL for: {domain}...")
    
    cmd = ["certbot", "certonly", "--nginx", "-d", domain, "--non-interactive", "--agree-tos", "--email", f"admin@{domain}"]
    result = run_command(cmd)
    
    if "Successfully received certificate" in result:
        await update.message.reply_text(f"✅ SSL obtained for {domain}!")
    else:
        await update.message.reply_text(f"❌ Failed:\n{result[:200]}")

async def block_ip(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await is_authorized(update):
        return
    
    if len(context.args) == 0:
        await update.message.reply_text("Usage: /block <ip>")
        return
    
    ip = context.args[0]
    # Validate IP
    try:
        socket.inet_aton(ip)
    except socket.error:
        await update.message.reply_text("❌ Invalid IP address.")
        return
        
    run_command(["ufw", "deny", "from", ip])
    await update.message.reply_text(f"✅ IP {ip} blocked.")

# --- PIN Protected Commands ---

async def pin_request(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Start PIN verification flow"""
    if not await is_authorized(update):
        return ConversationHandler.END
        
    context.user_data['pending_command'] = context.args
    context.user_data['command_name'] = update.message.text.split()[0]
    
    await update.message.reply_text(f"🔒 *PIN REQUIRED*\n\nPlease enter the 4-digit PIN to execute `{context.user_data['command_name']}`:", parse_mode='Markdown')
    return PIN_CHECK

async def pin_verify(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_pin = update.message.text.strip()
    
    if user_pin == PIN_CODE:
        cmd_name = context.user_data.get('command_name')
        await update.message.reply_text("✅ PIN Accepted. Executing...")
        
        if cmd_name == '/emergency_exit':
            await emergency_exit_exec(update, context)
        elif cmd_name == '/snapshot':
            await create_snapshot_exec(update, context)
            
        return ConversationHandler.END
    else:
        await update.message.reply_text("❌ Incorrect PIN. Action cancelled.")
        return ConversationHandler.END

async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("🚫 Cancelled.")
    return ConversationHandler.END

async def emergency_exit_exec(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("🟢 Exiting Emergency Mode...")
    # Execute bash commands safely
    run_command(["systemctl", "start", "nginx"])
    run_command(["systemctl", "start", "docker"])
    run_command(["ufw", "allow", "22/tcp"])
    run_command(["ufw", "allow", "80/tcp"])
    run_command(["ufw", "allow", "443/tcp"])
    await update.message.reply_text("✅ Services started & Ports opened.")

async def create_snapshot_exec(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("📸 Creating snapshot...")
    # Trigger the bash function via a wrapper or direct command
    # Since this is python, we'll call rsync directly
    ts = run_command(["date", "+%Y%m%d_%H%M%S"]).strip()
    name = f"snapshot_{ts}"
    path = f"/var/snapshots/{name}"
    
    os.makedirs(path, exist_ok=True)
    cmd = ["rsync", "-aAX", "--delete", "--exclude=/dev", "--exclude=/proc", "--exclude=/sys", "--exclude=/tmp", "--exclude=/run", "--exclude=/mnt", "--exclude=/var/snapshots", "/", f"{path}/"]
    
    # Run in background or wait? Snapshots take time.
    # For simplicity in this bot, we wait (timeout might occur)
    # Better: run in background
    subprocess.Popen(cmd)
    await update.message.reply_text(f"✅ Snapshot started: `{name}`\n(Running in background)", parse_mode='Markdown')

def main():
    application = Application.builder().token(BOT_TOKEN).build()
    
    # Basic
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("help", help_command))
    application.add_handler(CommandHandler("status", status))
    
    # Management
    application.add_handler(CommandHandler("vpn", vpn_create))
    application.add_handler(CommandHandler("ssl", get_ssl))
    application.add_handler(CommandHandler("block", block_ip))
    
    # PIN Protected Conversation
    pin_handler = ConversationHandler(
        entry_points=[
            CommandHandler("emergency_exit", pin_request),
            CommandHandler("snapshot", pin_request)
        ],
        states={
            PIN_CHECK: [MessageHandler(filters.TEXT & ~filters.COMMAND, pin_verify)]
        },
        fallbacks=[CommandHandler("cancel", cancel)]
    )
    application.add_handler(pin_handler)
    
    print(f"🤖 Bot started for {SERVER_NAME}...")
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
    echo "4) 🗂️  CapRover Backup System"
    echo "5) 📋 List Backup History"
    echo "6) 🔄 Restore from Backup"
    echo "7) 🧹 Cleanup Old Backups"
    read -rp "Select (0-7): " c
    case "$c" in
      0) break ;;
      1) caprover_check; pause ;;
      2) caprover_logs; pause ;;
      3) caprover_restart; pause ;;
      4) caprover_backup; pause ;;
      5) caprover_list_backups; pause ;;
      6) caprover_restore_backup; pause ;;
      7) caprover_cleanup_backups; pause ;;
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
    echo "1) Nginx Management"
    echo "2) Network Diagnostics"
    echo "3) Performance & Cleanup"
    echo "4) System Snapshot & Restore"
    echo "5) Configuration as Code"
    echo "6) Advanced Firewall"
    read -rp "Select (0-6): " c
    case "$c" in
      0) break ;;
      1) nginx_manage; pause ;;
      2) network_diag; pause ;;
      3) perf_optimize; pause ;;
      4) snapshot_menu; pause ;;
      5) config_menu; pause ;;
      6) firewall_advanced; pause ;;
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
    
    # Make sure pip3 is available
    if ! command_exists pip3; then
      echo "Installing pip3..."
      apt update && apt install -y python3-pip
    fi
    
    # Install telegram bot library
    if command_exists pip3; then
      pip3 install python-telegram-bot --upgrade
      echo "✅ python-telegram-bot installed"
    else
      echo "❌ pip3 not available. Install manually: apt install python3-pip"
      return
    fi
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

# ============= INITIALIZATION =============

# Create required directories
mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true
mkdir -p "$BACKUP_DIR" 2>/dev/null || true
touch "$LOGFILE" 2>/dev/null || true

# ============= CLI ARGUMENT PARSING =============

show_help(){
  cat << 'EOF'
BDRman - Server Management Panel v3.1

Usage: bdrman [OPTIONS]

OPTIONS:
  --help, -h              Show this help message
  --version, -v           Show version information
  --auto-backup           Run automatic backup and exit
  --dry-run               Enable dry-run mode (no actual changes)
  --non-interactive       Skip confirmations (use with caution!)
  --check-deps            Check dependencies and exit
  --debug                 Enable debug output
  --config FILE           Use custom config file

EXAMPLES:
  bdrman                  # Start interactive menu
  bdrman --auto-backup    # Create backup and exit
  bdrman --check-deps     # Verify all required tools are installed
  bdrman --debug          # Run with debug logging enabled

CONFIGURATION:
  Config file: /etc/bdrman/config.conf
  Example: /usr/local/bin/config.conf.example

For more information, visit: https://github.com/burakdarende/bdrman
EOF
}

show_version(){
  echo "BDRman v3.1"
  echo "Author: Burak Darende"
  echo "License: MIT"
}

# Parse command line arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      show_help
      exit 0
      ;;
    --version|-v)
      show_version
      exit 0
      ;;
    --auto-backup)
      log "Running auto-backup from CLI"
      backup_create
      exit $?
      ;;
    --dry-run)
      DRY_RUN=true
      echo "🔍 DRY-RUN MODE ENABLED (no changes will be made)"
      shift
      ;;
    --non-interactive)
      NON_INTERACTIVE=true
      echo "⚡ NON-INTERACTIVE MODE ENABLED"
      shift
      ;;
    --check-deps)
      check_dependencies
      exit $?
      ;;
    --debug)
      DEBUG=true
      echo "🐛 DEBUG MODE ENABLED"
      shift
      ;;
    --config)
      if [ -n "$2" ] && [ -f "$2" ]; then
        CONFIG_FILE="$2"
        load_config
        echo "📝 Loaded config from: $CONFIG_FILE"
        shift 2
      else
        echo "❌ Config file not found: $2"
        exit 1
      fi
      ;;
    *)
      echo "❌ Unknown option: $1"
      echo "Run 'bdrman --help' for usage information"
      exit 1
      ;;
  esac
done

# Check dependencies on startup (unless --help/--version)
if [ "$DEBUG" = true ]; then
  check_dependencies
fi

log "bdrman started."
main_menu
