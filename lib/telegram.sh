# ============= TELEGRAM BOT INTEGRATION =============

telegram_setup(){
  echo "=== TELEGRAM BOT SETUP ==="
  echo ""
  echo "To use Telegram bot, you need:"
  echo "1) Bot token from @BotFather"
  echo "2) Your chat ID (send /start to @userinfobot to get it)"
  echo ""
  
  # Clear stdin buffer to prevent skipping inputs
  read -t 0.1 -n 10000 discard 2>/dev/null
  
  read -rp "Bot Token: " bot_token
  # Remove all whitespace/newlines
  bot_token=$(echo "$bot_token" | tr -d '[:space:]')
  
  read -rp "Chat ID: " chat_id
  # Remove all whitespace/newlines
  chat_id=$(echo "$chat_id" | tr -d '[:space:]')
  
  if [ -z "$bot_token" ] || [ -z "$chat_id" ]; then
    echo "❌ Both token and chat ID are required."
    return 1
  fi
  
  # Validate token format (should look like: 123456789:ABCdefGHI...)
  if [[ ! "$bot_token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
    echo "⚠️  Warning: Token format looks unusual (Expected format: 123456789:ABC...)"
    read -rp "Continue anyway? (yes/no): " continue_setup
    [ "$continue_setup" != "yes" ] && return 1
  fi
  
  # Test token before saving
  echo "Testing bot token..."
  # Use curl to check getMe, capture output
  RESPONSE=$(curl -s --max-time 10 "https://api.telegram.org/bot${bot_token}/getMe")
  
  if echo "$RESPONSE" | grep -q '"ok":true'; then
    echo "✅ Token verified!"
    # Extract bot username for confirmation
    BOT_NAME=$(echo "$RESPONSE" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
    echo "   Bot Name: @$BOT_NAME"
  else
    echo "❌ Failed to verify bot token."
    echo "   API Response: $RESPONSE"
    echo "   Please check your token and internet connection."
    log_error "Telegram setup failed: invalid bot token or connection error"
    return 1
  fi
  
  # Save config securely
  mkdir -p /etc/bdrman
  cat > /etc/bdrman/telegram.conf << EOF
BOT_TOKEN="$bot_token"
CHAT_ID="$chat_id"
PIN_CODE="1234"
SERVER_NAME="$(hostname)"
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
# Use SERVER_NAME from config if available, else hostname
SERVER_LABEL="${SERVER_NAME:-$(hostname)}"

# Use safe curl with timeout and retries
# Removed emoji to prevent encoding issues (???)
curl --fail --max-time 10 --retry 2 -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="${CHAT_ID}" \
  -d text="[${SERVER_LABEL}]%0A%0A${MESSAGE}" \
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

telegram_send_photo(){
  local file="$1"
  local caption="$2"
  
  if [ ! -f /etc/bdrman/telegram.conf ]; then
    echo "⚠️  Telegram not configured. Cannot send photo."
    return 1
  fi
  
  source /etc/bdrman/telegram.conf
  
  if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "⚠️  Telegram config missing token or chat_id."
    return 1
  fi
  
  echo "📤 Sending to Telegram..."
  curl -s -F chat_id="$CHAT_ID" -F photo="@$file" -F caption="$caption" "https://api.telegram.org/bot$BOT_TOKEN/sendPhoto" >/dev/null
  
  if [ $? -eq 0 ]; then
    echo "✅ Photo sent to Telegram!"
  else
    echo "❌ Failed to send photo to Telegram."
  fi
}

telegram_bot_webhook(){
  echo "=== TELEGRAM BOT WEBHOOK SERVER ==="
  echo ""
  echo "This will install/update the Telegram Bot service."
  echo "The bot supports dynamic commands."
  echo "Once started, send /help to the bot to see the full list of available commands."
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
  
  # Check for bot script
  if [ ! -f /etc/bdrman/telegram_bot.py ]; then
    echo "⚠️  Bot script not found at /etc/bdrman/telegram_bot.py"
    
    # Try to find it in other locations
    if [ -f /usr/local/bin/telegram_bot.py ]; then
      echo "Found at /usr/local/bin/telegram_bot.py, copying..."
      cp /usr/local/bin/telegram_bot.py /etc/bdrman/telegram_bot.py
    elif [ -f "$(dirname "$0")/../telegram_bot.py" ]; then
      # Local dev environment
      cp "$(dirname "$0")/../telegram_bot.py" /etc/bdrman/telegram_bot.py
    else
      echo "⬇️  Downloading telegram_bot.py..."
      curl -s -f -L "https://raw.githubusercontent.com/burakdarende/bdrman/main/telegram_bot.py" -o /etc/bdrman/telegram_bot.py
    fi
    
    if [ ! -f /etc/bdrman/telegram_bot.py ]; then
      echo "❌ Failed to install telegram_bot.py"
      return 1
    fi
    chmod +x /etc/bdrman/telegram_bot.py
  fi
  
  echo "✅ Bot script installed"
  
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

telegram_menu(){
  while true; do
    clear_and_banner
    echo "=== TELEGRAM BOT MANAGEMENT ==="
    echo "1) Initial Setup (Token & Chat ID)"
    echo "2) Send Test Message"
    echo "3) Start/Update Bot Server (Python)"
    echo "4) Detailed Bot Status"
    echo "5) Send Weekly Report Now"
    echo "6) Restart Bot Service"
    echo "7) View Bot Logs"
    echo "8) Back"
    read -rp "Select: " c
    case "$c" in
      1) telegram_setup; pause ;;
      2) telegram_send; pause ;;
      3) telegram_bot_webhook; pause ;;
      4) telegram_bot_status; pause ;;
      5) telegram_test_report; pause ;;
      6) systemctl restart bdrman-telegram && echo "✅ Restarted"; pause ;;
      7) journalctl -u bdrman-telegram -n 50 --no-pager; pause ;;
      8) break ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}
