#!/bin/bash
# ==============================================================================
# BDRman - Server Management Panel
# Version: 4.9.6
# Author: Burak Darende
# License: MIT
# Description: Comprehensive server management tool for CapRover, Docker, and more.
# ==============================================================================

VERSION="4.9.6"

# ============= LIBRARY LOADING =============

# Determine library directory
# If running from source (e.g. ./bdrman.sh), libs are in ./lib
# If installed (e.g. /usr/local/bin/bdrman), libs are in /usr/local/bin/lib or /opt/bdrman/lib
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

if [ -d "$SCRIPT_DIR/lib" ]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [ -d "/usr/local/lib/bdrman" ]; then
  LIB_DIR="/usr/local/lib/bdrman"
elif [ -d "/usr/local/bin/lib" ]; then
  # Legacy path support
  LIB_DIR="/usr/local/bin/lib"
elif [ -d "/opt/bdrman/lib" ]; then
  LIB_DIR="/opt/bdrman/lib"
else
  echo "❌ Critical Error: Library directory not found!"
  echo "   Expected 'lib' folder in $SCRIPT_DIR, /usr/local/lib/bdrman, or /opt/bdrman"
  exit 1
fi

# Source Core first (defines colors, logging, helpers)
if [ -f "$LIB_DIR/core.sh" ]; then
  source "$LIB_DIR/core.sh"
else
  echo "❌ Critical Error: lib/core.sh not found in $LIB_DIR"
  exit 1
fi

# Source all other modules
MODULES=("vpn" "caprover" "security" "backup" "system" "docker" "telegram")

for module in "${MODULES[@]}"; do
  if [ -f "$LIB_DIR/$module.sh" ]; then
    source "$LIB_DIR/$module.sh"
  else
    error "Module not found: $module.sh"
    # Don't exit, try to continue with other modules
  fi
done

# ============= INITIALIZATION =============

# Create required directories
mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true
mkdir -p "$BACKUP_DIR" 2>/dev/null || true
touch "$LOGFILE" 2>/dev/null || true

# ============= MAIN MENU =============

main_menu(){
  while true; do
    clear_and_banner
    echo "=== MAIN MENU ==="
    echo "1) System Status"
    echo "2) VPN Settings"
    echo "3) CapRover Management"
    echo "4) Firewall Settings"
    echo "5) Logs & Monitoring"
    echo "6) Backup & Restore"
    echo "7) Security & Hardening"
    echo "8) Docker Management"
    echo "9) Telegram Bot Management"
    echo "10) Settings"
    echo "11) About"
    echo "12) Quick Commands"
    echo "13) Exit"
    read -rp "Select (1-13): " s
    case "$s" in
      1) system_status; pause ;;
      2) vpn_menu ;;
      3) caprover_menu ;;
      4) firewall_menu ;;
      5) logs_menu ;;
      6) backup_menu ;;
      7) security_menu ;;
      8) docker_menu ;;
      9) telegram_menu ;;
      10) settings_menu ;;
      11) show_version; pause ;;
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
            [ -f /etc/wireguard/wg0.conf ] && systemctl restart wg-quick@wg0
            echo "✅ Services restarted"
            pause
            ;;
          *) ;;
        esac
        ;;
      13) echo "Exiting..."; exit 0 ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}

# ============= CLI ARGUMENT PARSING =============

# Parse command line arguments
if [ $# -gt 0 ]; then
  case "$1" in
    # Quick commands
    status)
      info "System Status"
      echo ""
      table_header "Metric" "Value"
      table_row "Hostname" "$(hostname)"
      table_row "Uptime" "$(uptime -p)"
      table_row "CPU Load" "$(uptime | awk -F'load average:' '{print $2}')"
      table_row "Memory" "$(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
      table_row "Disk" "$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
      echo ""
      success "Status check complete"
      exit 0
      ;;
    
    backup)
      shift
      case "$1" in
        create)
          info "Creating backup..."
          backup_create
          exit $?
          ;;
        list)
          backup_list
          exit 0
          ;;
        restore)
          backup_restore
          exit $?
          ;;
        --help|-h)
          cat << 'EOF'
Usage: bdrman backup <command>

Commands:
  create              Create a new backup
  list                List all available backups
  restore             Restore from a backup

Examples:
  bdrman backup create
  bdrman backup list
  bdrman backup restore
EOF
          exit 0
          ;;
        *) show_help ;;
      esac
      ;;

    caprover)
      shift
      case "$1" in
        install) caprover_install ;;
        uninstall) caprover_uninstall ;;
        *) show_help ;;
      esac
      ;;

    config)
      shift
      case "$1" in
        export) config_export ;;
        import) config_import ;;
        *) show_help ;;
      esac
      ;;
    
    telegram)
      shift
      case "$1" in
        send)
          shift
          if [ -z "$1" ]; then
            error "Message required"
            echo "Usage: bdrman telegram send \"message\""
            exit 1
          fi
          /usr/local/bin/bdrman-telegram "$*"
          exit $?
          ;;
        --help|-h)
          cat << 'EOF'
Usage: bdrman telegram <command>

Commands:
  send "message"      Send a message via Telegram bot

Examples:
  bdrman telegram send "Server is up"
  bdrman telegram send "Backup completed successfully"

Note: Telegram bot must be configured first.
EOF
          exit 0
          ;;
        *)
          error "Unknown telegram command: $1"
          echo "Usage: bdrman telegram send \"message\""
          echo "Run 'bdrman telegram --help' for more information"
          exit 1
          ;;
      esac
      ;;
    
    docker)
      shift
      case "$1" in
        ps)
          info "Docker Containers"
          docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
          exit 0
          ;;
        logs)
          if [ -z "$2" ]; then
            error "Container name required"
            echo "Usage: bdrman docker logs <container>"
            exit 1
          fi
          docker logs --tail 50 "$2"
          exit $?
          ;;
        restart)
          if [ -z "$2" ]; then
            error "Container name required"
            echo "Usage: bdrman docker restart <container>"
            exit 1
          fi
          info "Restarting container: $2"
          docker restart "$2"
          success "Container restarted"
          exit $?
          ;;
        --help|-h)
          cat << 'EOF'
Usage: bdrman docker <command> [options]

Commands:
  ps                  List all Docker containers
  logs <container>    Show logs for a container (last 50 lines)
  restart <container> Restart a container

Examples:
  bdrman docker ps
  bdrman docker logs nginx-proxy
  bdrman docker restart captain-captain
EOF
          exit 0
          ;;
        *)
          error "Unknown docker command: $1"
          echo "Usage: bdrman docker {ps|logs|restart} [container]"
          echo "Run 'bdrman docker --help' for more information"
          exit 1
          ;;
      esac
      ;;
    
    vpn)
      shift
      case "$1" in
        add)
          if [ -z "$2" ]; then
            error "Username required"
            echo "Usage: bdrman vpn add <username>"
            exit 1
          fi
          info "Adding VPN user: $2"
          vpn_add_client
          exit $?
          ;;
        list)
          info "VPN Users"
          if [ -d /etc/wireguard ]; then
            ls -1 /etc/wireguard/*.conf 2>/dev/null | xargs -n1 basename | sed 's/.conf$//'
          else
            warning "WireGuard not configured"
          fi
          exit 0
          ;;
        --help|-h)
          cat << 'EOF'
Usage: bdrman vpn <command> [options]

Commands:
  add <username>      Add a new VPN user
  list                List all VPN users

Examples:
  bdrman vpn add john
  bdrman vpn list

Note: WireGuard must be installed first.
EOF
          exit 0
          ;;
        *)
          error "Unknown vpn command: $1"
          echo "Usage: bdrman vpn {add|list}"
          echo "Run 'bdrman vpn --help' for more information"
          exit 1
          ;;
      esac
      ;;
    
    metrics)
      shift
      case "$1" in
        collect)
          metrics_collect
          success "Metrics collected"
          exit 0
          ;;
        report)
          metrics_report
          exit 0
          ;;
        graph)
          metrics_graph
          exit 0
          ;;
        daemon)
          metrics_start_daemon
          exit 0
          ;;
        --help|-h)
          cat << 'EOF'
Usage: bdrman metrics <command>

Commands:
  collect             Collect current system metrics
  report              Generate performance report
  graph               Show ASCII graph of metrics
  daemon              Start metrics collection daemon

Examples:
  bdrman metrics collect
  bdrman metrics report
  bdrman metrics graph
  bdrman metrics daemon

Note: Requires sqlite3 for metric storage.
EOF
          exit 0
          ;;
        *)
          error "Unknown metrics command: $1"
          echo "Usage: bdrman metrics {collect|report|graph|daemon}"
          echo "Run 'bdrman metrics --help' for more information"
          exit 1
          ;;
      esac
      ;;
    
    update)
      info "Checking for updates..."
      check_updates
      read -rp "Update now? (yes/no): " confirm
      if [ "$confirm" = "yes" ]; then
        info "Downloading latest version..."
        curl -s -L "https://raw.githubusercontent.com/burakdarende/bdrman/main/bdrman.sh" -o /tmp/bdrman_new.sh
        if [ $? -eq 0 ]; then
          chmod +x /tmp/bdrman_new.sh
          mv /tmp/bdrman_new.sh /usr/local/bin/bdrman
          success "Update complete! Please restart bdrman."
        else
          error "Update failed"
        fi
      fi
      exit 0
      ;;
    
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
      info "DRY-RUN MODE ENABLED (no changes will be made)"
      shift
      ;;
    --non-interactive)
      NON_INTERACTIVE=true
      info "NON-INTERACTIVE MODE ENABLED"
      shift
      ;;
    --check-deps)
      check_dependencies
      exit $?
      ;;
    --debug)
      DEBUG=true
      info "DEBUG MODE ENABLED"
      shift
      ;;
    --config)
      if [ -n "$2" ] && [ -f "$2" ]; then
        CONFIG_FILE="$2"
        load_config
        info "Loaded config from: $CONFIG_FILE"
        shift 2
      else
        error "Config file not found: $2"
        exit 1
      fi
      ;;
    *)
      error "Unknown command: $1"
      echo "Run 'bdrman --help' for usage information"
      exit 1
      ;;
  esac
fi

# Check dependencies on startup (unless --help/--version)
if [ "$DEBUG" = true ]; then
  check_dependencies
fi

log "bdrman started."
main_menu
