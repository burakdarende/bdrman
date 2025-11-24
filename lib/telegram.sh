# ============= TELEGRAM BOT MODULE =============

# Function to send messages via CLI
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

# Function to setup Telegram Bot
telegram_setup(){
  echo "=== TELEGRAM BOT SETUP ==="
  echo "To use the Ultimate Telegram Bot, you need:"
  echo "1) Bot token from @BotFather"
  echo "2) Your chat ID (send /start to @userinfobot)"
  echo ""
  
  read -rp "Bot Token: " bot_token
  bot_token=$(echo "$bot_token" | tr -d '[:space:]')
  
  read -rp "Chat ID: " chat_id
  chat_id=$(echo "$chat_id" | tr -d '[:space:]')
  
  if [ -z "$bot_token" ] || [ -z "$chat_id" ]; then
    error "Both token and chat ID are required."
    return 1
  fi
  
  # Save config
  mkdir -p /etc/bdrman
  cat > /etc/bdrman/telegram.conf << EOF
BOT_TOKEN="$bot_token"
CHAT_ID="$chat_id"
EOF
  chmod 600 /etc/bdrman/telegram.conf
  
  success "Config saved to /etc/bdrman/telegram.conf"

  # Create CLI Helper Script (for manual sending via curl)
  cat > /usr/local/bin/bdrman-telegram << 'EOF'
#!/bin/bash
source /etc/bdrman/telegram.conf
MESSAGE="$1"
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="${CHAT_ID}" \
  -d text="${MESSAGE}" \
  -d parse_mode="Markdown" > /dev/null
EOF
  chmod +x /usr/local/bin/bdrman-telegram
  success "CLI helper script created at /usr/local/bin/bdrman-telegram"
  
  # Restart service
  echo "🔄 Restarting Bot Service..."
  systemctl restart bdrman-telegram
  
  if systemctl is-active --quiet bdrman-telegram; then
    success "Bot is RUNNING! Send /start to your bot."
  else
    error "Bot failed to start. Check logs."
  fi
}

# Function to manage Telegram Menu
telegram_menu(){
  while true; do
    clear_and_banner
    echo "=== TELEGRAM BOT MANAGEMENT ==="
    
    if systemctl is-active --quiet bdrman-telegram; then
      echo "🟢 Status: RUNNING"
    else
      echo "🔴 Status: STOPPED"
    fi
    
    echo "--------------------------------"
    echo "0) Back"
    echo "1) Setup / Configure Bot"
    echo "2) Start Bot"
    echo "3) Stop Bot"
    echo "4) Restart Bot"
    echo "5) View Bot Logs"
    echo "6) Install Python Dependencies (Fix)"
    echo "7) Send Manual Message"
    
    read -rp "Select (0-7): " c
    case "$c" in
      0) break ;;
      1) telegram_setup; pause ;;
      2) systemctl start bdrman-telegram && success "Started"; pause ;;
      3) systemctl stop bdrman-telegram && success "Stopped"; pause ;;
      4) systemctl restart bdrman-telegram && success "Restarted"; pause ;;
      5) journalctl -u bdrman-telegram -n 50 --no-pager; pause ;;
      6) 
        echo "Installing dependencies..."
        /opt/bdrman/venv/bin/pip install python-telegram-bot psutil requests
        pause 
        ;;
      7) telegram_send; pause ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}
