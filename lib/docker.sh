# ============= DOCKER MANAGEMENT =============

docker_list(){
  docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

docker_logs(){
  read -rp "Container Name: " name
  if [ -n "$name" ]; then
    docker logs --tail 50 "$name" | less
  else
    echo "No name provided."
  fi
}

docker_restart(){
  read -rp "Container Name: " name
  if [ -n "$name" ]; then
    docker restart "$name" && success "Restarted $name" || error "Failed"
  else
    echo "No name provided."
  fi
}

docker_stop(){
  read -rp "Container Name: " name
  if [ -n "$name" ]; then
    docker stop "$name" && success "Stopped $name" || error "Failed"
  else
    echo "No name provided."
  fi
}

docker_start(){
  read -rp "Container Name: " name
  if [ -n "$name" ]; then
    docker start "$name" && success "Started $name" || error "Failed"
  else
    echo "No name provided."
  fi
}

docker_prune(){
  echo "⚠️  This will remove all stopped containers, unused networks and images."
  read -rp "Are you sure? (y/n): " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    docker system prune -a -f && success "System pruned"
  fi
}

docker_stats(){
  docker stats --no-stream
}

docker_menu(){
  while true; do
    clear_and_banner
    echo "=== DOCKER MANAGEMENT ==="
    echo "0) Back"
    echo "1) List Containers"
    echo "2) Container Logs"
    echo "3) Restart Container"
    echo "4) Stop Container"
    echo "5) Start Container"
    echo "6) Prune System (Clean unused)"
    echo "7) Docker Stats"
    read -rp "Select (0-7): " c
    case "$c" in
      0) break ;;
      1) docker_list; pause ;;
      2) docker_logs; pause ;;
      3) docker_restart; pause ;;
      4) docker_stop; pause ;;
      5) docker_start; pause ;;
      6) docker_prune; pause ;;
      7) docker_stats; pause ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}
