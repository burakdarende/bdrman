# ============= CAPROVER =============

get_caprover_container() {
  # Try to find container named 'caprover' or 'captain-captain' or just containing 'captain'
  local container=$(docker ps --filter "name=^/?caprover$" --format "{{.Names}}" | head -n1)
  if [ -z "$container" ]; then
    container=$(docker ps --filter "name=captain" --format "{{.Names}}" | head -n1)
  fi
  echo "$container"
}

get_docker_volumes_dir() {
  local docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)
  if [ -n "$docker_root" ]; then
    echo "$docker_root/volumes"
  else
    echo "/var/lib/docker/volumes"
  fi
}

caprover_check(){
  if command_exists docker; then
    echo "🔍 Checking for CapRover container..."
    CAP_CONTAINER=$(get_caprover_container)
    
    if [ -n "$CAP_CONTAINER" ]; then
      echo "✅ Found CapRover container: $CAP_CONTAINER"
      docker ps --filter "name=$CAP_CONTAINER" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
    else
      echo "❌ CapRover container not found."
      echo "   Checked for names: 'caprover', 'captain-captain', or containing 'captain'"
      echo ""
      echo "   Running containers:"
      docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | head -n 10
    fi
  else
    echo "Docker not installed."
  fi
}

caprover_logs(){
  if command_exists docker; then
    CAP_CONTAINER=$(get_caprover_container)
    if [ -n "$CAP_CONTAINER" ]; then
      echo "Logs for $CAP_CONTAINER:"
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
    CAP_CONTAINER=$(get_caprover_container)
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
  
  VOLUMES_DIR=$(get_docker_volumes_dir)
  BACKUP_BASE_DIR="/root/capBackup"
  
  echo "🔍 Docker Volumes Directory: $VOLUMES_DIR"
  
  # Check if volumes directory exists
  if [ ! -d "$VOLUMES_DIR" ]; then
    echo "❌ Docker volumes directory not found: $VOLUMES_DIR"
    echo "   Make sure Docker is installed and running."
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
    echo "   Debug Info:"
    echo "   Docker Root: $(docker info --format '{{.DockerRootDir}}' 2>/dev/null)"
    echo "   Volumes Dir contents:"
    ls -la "$VOLUMES_DIR" 2>/dev/null | head -n 10 || echo "Cannot list directory"
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
  VOLUMES_DIR=$(get_docker_volumes_dir)
  
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

caprover_install(){
  echo "=== CAPROVER INSTALLATION ==="
  echo "⚠️  This will install Docker (if missing) and run CapRover."
  echo "    CapRover requires ports 80, 443, 3000 to be open."
  read -rp "Are you sure you want to proceed? (y/n): " ans
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then return; fi
  
  # Check Docker
  if ! command_exists docker; then
    info "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
  fi
  
  info "Starting CapRover..."
  docker run -d --restart always \
    -p 80:80 -p 443:443 -p 3000:3000 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /captain:/captain \
    --name caprover \
    caprover/caprover
    
  if [ $? -eq 0 ]; then
    success "CapRover started! Access at http://$(curl -s ifconfig.me):3000"
    log_success "CapRover installed."
  else
    error "CapRover failed to start."
  fi
}

caprover_uninstall(){
  echo "=== CAPROVER UNINSTALL ==="
  echo "⚠️  WARNING: This will stop CapRover and DELETE all data in /captain!"
  read -rp "Are you REALLY sure? (type 'yes' to confirm): " ans
  if [ "$ans" != "yes" ]; then return; fi
  
  docker stop caprover && docker rm caprover
  rm -rf /captain
  success "CapRover uninstalled and data removed."
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
