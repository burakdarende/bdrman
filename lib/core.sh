# ============= CORE FUNCTIONS =============

# Default configuration
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

# Terminal color codes
COLOR_RESET="\033[0m"
COLOR_RED="\033[0;31m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_BLUE="\033[0;34m"
COLOR_MAGENTA="\033[0;35m"
COLOR_CYAN="\033[0;36m"
COLOR_WHITE="\033[0;37m"
COLOR_BOLD="\033[1m"

# Color output functions
color_echo(){
  local color="$1"
  shift
  echo -e "${color}$*${COLOR_RESET}"
}

success(){
  color_echo "$COLOR_GREEN" "✓ $*"
}

error(){
  color_echo "$COLOR_RED" "✗ $*"
}

warning(){
  color_echo "$COLOR_YELLOW" "⚠ $*"
}

info(){
  color_echo "$COLOR_CYAN" "ℹ $*"
}

# Progress bar function
progress_bar(){
  local current="$1"
  local total="$2"
  local width=50
  local percentage=$((current * 100 / total))
  local filled=$((width * current / total))
  local empty=$((width - filled))
  
  printf "\r["
  printf "%${filled}s" | tr ' ' '█'
  printf "%${empty}s" | tr ' ' '░'
  printf "] %d%%" "$percentage"
}

# Table header function
table_header(){
  local cols=("$@")
  printf "${COLOR_BOLD}"
  printf "%-20s" "${cols[@]}"
  printf "${COLOR_RESET}\n"
  printf "%-20s" "${cols[@]}" | tr '[:print:]' '-'
  printf "\n"
}

# Table row function
table_row(){
  printf "%-20s" "$@"
  printf "\n"
}

# Original log functions (keep for compatibility)
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

  subtitle="BDR - SERVER MANAGEMENT PANEL - v${VERSION:-4.8.1}"
  padding=$(( (COLS - ${#subtitle}) / 2 ))
  printf "%*s" "$padding" ""
  echo -e "${YELLOW}${subtitle}${RESET}"
  echo
}
