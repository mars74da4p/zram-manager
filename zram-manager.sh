#!/usr/bin/env bash
# zram-manager - CLI & Interactive tool for managing zRAM and swappiness on Linux

set -euo pipefail

# Color palette for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check for root privileges
check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] Error: Please run this script with sudo!${NC}"
    exit 1
  fi
}

show_status() {
  echo -e "\n${CYAN}=== Current Memory and zRAM Status ===${NC}"
  echo "RAM Status:"
  free -h | grep "Mem:" | awk '{print "  Total: " $2 " | Used: " $3 " | Free: " $4}'
  
  echo -e "\nvm.swappiness parameter:"
  echo "  Current value: $(sysctl -n vm.swappiness)"
  
  echo -e "\nzRAM Status:"
  if command -v zramctl >/dev/null 2>&1; then
    zramctl
  else
    echo "  zramctl utility is not found or zRAM is not initialized."
  fi
  echo -e "${CYAN}=======================================${NC}\n"
}

set_swappiness() {
  local val="$1"
  if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -ge 0 ] && [ "$val" -le 100 ]; then
    sysctl vm.swappiness="$val" > /dev/null
    echo "vm.swappiness=$val" > /etc/sysctl.d/99-zram-swappiness.conf
    echo -e "${GREEN}[✓] Swappiness changed to $val and saved to /etc/sysctl.d/99-zram-swappiness.conf${NC}"
  else
    echo -e "${RED}[!] Error: Value must be an integer between 0 and 100.${NC}"
  fi
}

check_safe_reload() {
  # Safety check before restarting zRAM on the fly
  local free_ram_mb
  free_ram_mb=$(free -m | awk '/Mem:/ {print $4}')
  
  local used_zram_bytes=0
  if command -v zramctl >/dev/null 2>&1; then
    used_zram_bytes=$(zramctl --noheadings --output DATA 2>/dev/null | head -n1 | numfmt --from=iec 2>/dev/null || echo 0)
  fi
  
  local used_zram_mb=$((used_zram_bytes / 1024 / 1024))

  if [ "$used_zram_mb" -gt "$free_ram_mb" ]; then
    echo -e "${RED}[!] SYSTEM FREEZE RISK WARNING!${NC}"
    echo -e "${YELLOW}[!] zRAM holds ${used_zram_mb} MB of data, but free RAM is only ${free_ram_mb} MB.${NC}"
    echo -e "${YELLOW}[!] Disabling swap for reconfiguration may cause the system to freeze.${NC}\n"
    echo "Solution: Close heavy applications (e.g. web browser) or reboot after saving config."
    read -p "Apply configuration file without reloading service on the fly? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo -e "${RED}[*] Operation canceled by user.${NC}"
      exit 1
    fi
    return 1 # Flag: update config file only, skip live service reload
  fi
  return 0
}

resize_zram() {
  local zsize="$1"
  local algo="${2:-zstd}"

  echo -e "${YELLOW}[*] Performing safety check before modifying zRAM...${NC}"
  
  local safe_to_reload=0
  if check_safe_reload; then
    safe_to_reload=1
  fi

  echo -e "${YELLOW}[*] Configuring zRAM ($zsize, algorithm: $algo)...${NC}"

  # Systemd zram-generator handling (Fedora, Arch, etc.)
  if [ -d "/etc/systemd/zram-generator.conf.d" ] || [ -f "/etc/systemd/zram-generator.conf" ]; then
    mkdir -p /etc/systemd/zram-generator.conf.d
    cat <<EOF > /etc/systemd/zram-generator.conf.d/override.conf
[zram0]
zram-size = $zsize
compression-algorithm = $algo
EOF
    echo -e "${GREEN}[✓] Configuration /etc/systemd/zram-generator.conf.d/override.conf updated.${NC}"
    
    if [ "$safe_to_reload" -eq 1 ]; then
      echo -e "${YELLOW}[*] Restarting systemd-zram-setup@zram0 service...${NC}"
      systemctl restart systemd-zram-setup@zram0.service || true
      echo -e "${GREEN}[✓] zRAM successfully reconfigured to size $zsize!${NC}"
    else
      echo -e "${GREEN}[✓] Configuration saved! New zRAM settings will take effect after reboot.${NC}"
    fi
  else
    if [ "$safe_to_reload" -eq 0 ]; then
      echo -e "${RED}[!] On-the-fly zRAM change canceled due to OOM risk. Free up RAM and retry.${NC}"
      exit 1
    fi

    # Manual zRAM reload
    if swapoff /dev/zram0 2>/dev/null; then
      echo "  Swap /dev/zram0 disabled."
    fi

    if [ -f /sys/block/zram0/reset ]; then
      echo 1 > /sys/block/zram0/reset 2>/dev/null || true
    fi

    modprobe zram num_devices=1 2>/dev/null || true
    echo "$algo" > /sys/block/zram0/comp_algorithm
    echo "$zsize" > /sys/block/zram0/disksize

    mkswap /dev/zram0 >/dev/null
    swapon -p 100 /dev/zram0
    echo -e "${GREEN}[✓] zRAM successfully reconfigured!${NC}"
  fi
}

auto_configure() {
  local total_ram_mb
  total_ram_mb=$(free -m | awk '/Mem:/ {print $2}')
  
  local rec_size=""
  local rec_algo="zstd"
  local rec_swappiness=100
  local reason=""

  if [ "$total_ram_mb" -le 4096 ]; then
    rec_size="ram" # 100% RAM
    rec_algo="zstd"
    rec_swappiness=100
    reason="For systems with <= 4 GB RAM, zRAM = 100% RAM and swappiness = 100 are recommended for maximum swap capacity."
  elif [ "$total_ram_mb" -le 8192 ]; then
    rec_size="ram / 2" # 50% RAM
    rec_algo="zstd"
    rec_swappiness=100
    reason="For systems with 8 GB RAM, zRAM = 50% RAM balances compression efficiency and CPU usage."
  else
    rec_size="ram / 2"
    rec_algo="zstd"
    rec_swappiness=100
    reason="For systems with > 8 GB RAM, zRAM = 50% RAM is recommended."
  fi

  echo -e "${CYAN}=== Auto-Detection Recommendations ===${NC}"
  echo "Total RAM: ${total_ram_mb} MB (~$(( (total_ram_mb + 512) / 1024 )) GB)"
  echo -e "Recommended settings:"
  echo -e "  • zRAM Size:             ${GREEN}${rec_size}${NC}"
  echo -e "  • Compression Algorithm: ${GREEN}${rec_algo}${NC}"
  echo -e "  • vm.swappiness:         ${GREEN}${rec_swappiness}${NC}"
  echo -e "Reason: ${YELLOW}${reason}${NC}\n"

  read -p "Apply these optimal settings right now? [Y/n]: " confirm
  confirm=${confirm:-Y}
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    set_swappiness "$rec_swappiness"
    resize_zram "$rec_size" "$rec_algo"
  else
    echo -e "${YELLOW}[*] Operation canceled by user.${NC}"
  fi
}

# Command-line flags processing
check_root

if [ $# -gt 0 ]; then
  case "$1" in
    --status|-s)
      show_status
      exit 0
      ;;
    --auto|-a)
      auto_configure
      exit 0
      ;;
    --swappiness|-w)
      if [ -n "${2:-}" ]; then
        set_swappiness "$2"
        exit 0
      else
        echo -e "${RED}[!] Please specify value: --swappiness 80${NC}"
        exit 1
      fi
      ;;
    --resize|-r)
      if [ -n "${2:-}" ]; then
        resize_zram "$2" "${3:-zstd}"
        exit 0
      else
        echo -e "${RED}[!] Please specify size: --resize 4G [algorithm]${NC}"
        exit 1
      fi
      ;;
    --help|-h)
      echo "Usage: sudo ./zram-manager.sh [FLAG]"
      echo "  --status, -s               Show current status"
      echo "  --auto, -a                 Auto-detect and apply optimal settings"
      echo "  --swappiness, -w VALUE     Set swappiness (0-100)"
      echo "  --resize, -r SIZE [ALGO]   Set zRAM size (e.g. 4G, ram/2) and algorithm (zstd, lzo-rle)"
      echo "  --help, -h                 Show this help menu"
      exit 0
      ;;
    *)
      echo -e "${RED}[!] Unknown flag: $1${NC}"
      exit 1
      ;;
  esac
fi

# Interactive menu
while true; do
  show_status
  echo "1) Auto-configure (Optimal size and swappiness)"
  echo "2) Change vm.swappiness"
  echo "3) Change zRAM size and algorithm"
  echo "4) Refresh status"
  echo "5) Exit"
  read -p "Select option [1-5]: " choice

  case $choice in
    1)
      auto_configure
      ;;
    2)
      read -p "Enter swappiness value (0-100): " s_val
      set_swappiness "$s_val"
      ;;
    3)
      read -p "Enter size (e.g. 4G, 2048M or ram/2): " r_size
      read -p "Enter algorithm [default: zstd]: " r_algo
      r_algo=${r_algo:-zstd}
      resize_zram "$r_size" "$r_algo"
      ;;
    4)
      clear
      ;;
    5)
      echo "Exiting."
      exit 0
      ;;
    *)
      echo -e "${RED}Invalid choice.${NC}"
      ;;
  esac
done