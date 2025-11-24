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
  log "wireguard-install.sh executed"
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
    read -rp "Select (0-6): " c
    case "$c" in
      0) break ;;
      1) vpn_install_wireguard; pause ;;
      2) vpn_status; pause ;;
      3) vpn_add_client; pause ;;
      4) vpn_restart; pause ;;
      5) ls -la /etc/wireguard 2>/dev/null || echo "Directory not found."; pause ;;
      6) wg show || echo "WireGuard not installed."; pause ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}
