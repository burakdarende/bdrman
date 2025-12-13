# ============= VPN (WireGuard) =============
vpn_status(){
  if command_exists wg-quick; then
    systemctl status wg-quick@wg0 --no-pager || wg show || echo "WireGuard service info not available."
  else
    echo "WireGuard not installed or not in PATH."
  fi
}

vpn_add_client(){
  WG_SCRIPT="/usr/local/bin/wireguard-install.sh"
  
  if [ ! -f "$WG_SCRIPT" ]; then
    echo "⚠️  wireguard-install.sh not found."
    echo "⬇️  Downloading from github.com/angristan/wireguard-install..."
    
    if curl -s -L "https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh" -o "$WG_SCRIPT"; then
      chmod +x "$WG_SCRIPT"
      echo "✅ Download complete."
    else
      echo "❌ Failed to download wireguard-install.sh"
      return 1
    fi
  fi
  
  # Run the script
  echo "🚀 Launching WireGuard installer..."
  bash "$WG_SCRIPT"
  
  # Post-install: Generate QR and Link
  # Find the most recently modified .conf file in current dir or HOME
  LATEST_CONF=$(ls -t *.conf "$HOME"/*.conf 2>/dev/null | head -n1)
  
  if [ -n "$LATEST_CONF" ]; then
    CLIENT_NAME="${LATEST_CONF%.conf}"
    PNG_FILE="${CLIENT_NAME}.png"
    
    echo "⚙️  Generating QR Code for $CLIENT_NAME..."
    qrencode -t PNG -o "$PNG_FILE" < "$LATEST_CONF"
    
    # Check for transfer.sh or similar for uploading
    # Try 0x0.st first
    echo "📤 Uploading QR code..."
    UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    QR_LINK=$(curl -s -H "User-Agent: $UA" -F "file=@$PNG_FILE" https://0x0.st 2>/dev/null)
    
    # Fallback to transfer.sh if 0x0.st fails or blocks
    if [ -z "$QR_LINK" ] || [[ "$QR_LINK" == *"User agent"* ]]; then
      echo "⚠️  0x0.st failed, trying transfer.sh..."
      QR_LINK=$(curl -s --upload-file "$PNG_FILE" "https://transfer.sh/$PNG_FILE")
    fi

    if [ -n "$QR_LINK" ]; then
      echo "✅ QR Code Link: $QR_LINK"
      echo "   (Open this link on your phone to scan)"
    fi
    
    # Also show ASCII for convenience
    echo "📱 Scanning QR in terminal:"
    qrencode -t ANSIutf8 < "$LATEST_CONF"
  fi
  
  log "wireguard-install.sh executed and QR processed"
}

vpn_list_conf(){
  echo "=== VPN CONFIGS ==="
  ls -1 *.conf 2>/dev/null | sed 's/\.conf$//'
}

vpn_show_qr(){
  echo "=== SHOW QR CODE ==="
  
  # Create array of config files
  mapfile -t CONFS < <(ls -1 *.conf 2>/dev/null | sed 's/\.conf$//')
  
  if [ ${#CONFS[@]} -eq 0 ]; then
    echo "❌ No VPN clients found."
    return
  fi
  
  # Display numbered list
  echo "Select a client:"
  for i in "${!CONFS[@]}"; do
    echo "$((i+1))) ${CONFS[$i]}"
  done
  
  read -rp "Select (1-${#CONFS[@]}): " num
  
  # Validate input
  if [[ ! "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "${#CONFS[@]}" ]; then
    echo "❌ Invalid selection."
    return
  fi
  
  # Get selected client name
  client_name="${CONFS[$((num-1))]}"
  echo "Selected: $client_name"
  
  CONF_FILE="${client_name}.conf"
  PNG_FILE="${client_name}.png"
  
  if [ -f "$CONF_FILE" ]; then
    echo "1) ASCII (Terminal)"
    echo "2) PNG Link (Upload)"
    read -rp "Select format (1/2): " fmt
    
    if [ "$fmt" == "1" ]; then
      qrencode -t ANSIutf8 < "$CONF_FILE"
    elif [ "$fmt" == "2" ]; then
      if [ ! -f "$PNG_FILE" ]; then
        qrencode -t PNG -o "$PNG_FILE" < "$CONF_FILE"
      fi
      echo "Uploading..."
      UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      LINK=$(curl -s -H "User-Agent: $UA" -F "file=@$PNG_FILE" https://0x0.st 2>/dev/null)
      
      # Fallback
      if [ -z "$LINK" ] || [[ "$LINK" == *"User agent"* ]]; then
        echo "⚠️  0x0.st failed, trying transfer.sh..."
        LINK=$(curl -s --upload-file "$PNG_FILE" "https://transfer.sh/$PNG_FILE")
      fi
      
      echo "✅ Link: $LINK"
    fi
  else
    echo "❌ Config file not found: $CONF_FILE"
  fi
}

vpn_restart(){
  systemctl restart wg-quick@wg0 && echo "WireGuard restarted." || echo "Restart failed."
}

vpn_install_wireguard(){
  echo "=== INSTALL WIREGUARD ==="
  
  if command_exists wg; then
    echo "✅ WireGuard is already installed."
    read -rp "Reinstall? (y/n): " ans
    if [[ ! "$ans" =~ [Yy] ]]; then
      return
    fi
  fi
  
  echo "Installing WireGuard and dependencies..."
  apt update
  apt install -y wireguard resolvconf qrencode
  
  echo "✅ Installation complete."
  log_success "WireGuard installed"
}

vpn_menu(){
  while true; do
    clear_and_banner
    echo "=== VPN SETTINGS ==="
    
    # Check installation status
    if command_exists wg; then
      echo "🟢 Status: INSTALLED"
    else
      echo "🔴 Status: NOT INSTALLED"
    fi
    echo ""
    
    echo "0) Back"
    echo "1) Install WireGuard (Auto)"
    echo "2) WireGuard Status"
    echo "3) Add New Client (wireguard-install.sh)"
    echo "4) Restart WireGuard"
    echo "5) List Config Files (/etc/wireguard)"
    echo "6) Show wg show"
    echo "7) Show QR Code (PNG/ASCII)"
    read -rp "Select (0-7): " c
    case "$c" in
      0) break ;;
      1) vpn_install_wireguard; pause ;;
      2) vpn_status; pause ;;
      3) vpn_add_client; pause ;;
      4) vpn_restart; pause ;;
      5) ls -la /etc/wireguard 2>/dev/null || echo "Directory not found."; pause ;;
      6) wg show || echo "WireGuard not installed."; pause ;;
      7) vpn_show_qr; pause ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}
