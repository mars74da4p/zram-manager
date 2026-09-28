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
  local ram_total ram_used ram_available ram_percent swap_total swap_used
  read -r ram_total ram_used ram_available < <(free -m | awk '/^Mem:/ {print $2, $3, $7}')
  read -r swap_total swap_used < <(free -m | awk '/^Swap:/ {print $2, $3}')
  ram_percent=0
  if [ "${ram_total:-0}" -gt 0 ]; then
    ram_percent=$((ram_used * 100 / ram_total))
  fi

  printf '\n%b╭──────────────────── ZRAM MANAGER ────────────────────╮%b\n' "$CYAN" "$NC"
  printf '%b│%b  MEMORY                                               %b│%b\n' "$CYAN" "$NC" "$CYAN" "$NC"
  printf '  RAM       %s used / %s total (%s%%)\n' "$(numfmt --from-unit=1024 --to=iec --suffix=B "$((ram_used * 1024))")" "$(numfmt --from-unit=1024 --to=iec --suffix=B "$((ram_total * 1024))")" "$ram_percent"
  printf '  Available %s\n' "$(numfmt --from-unit=1024 --to=iec --suffix=B "$((ram_available * 1024))")"
  printf '  '
  draw_memory_bar "$ram_percent"
  printf '\n  Swap      %s used / %s total\n' "$(numfmt --from-unit=1024 --to=iec --suffix=B "$((swap_used * 1024))")" "$(numfmt --from-unit=1024 --to=iec --suffix=B "$((swap_total * 1024))")"
  printf '\n%b│%b  KERNEL TUNING                                        %b│%b\n' "$CYAN" "$NC" "$CYAN" "$NC"
  printf '  vm.swappiness         %s\n' "$(sysctl -n vm.swappiness)"
  printf '  vm.vfs_cache_pressure %s\n' "$(sysctl -n vm.vfs_cache_pressure)"

  printf '\n%b│%b  ZRAM                                                  %b│%b\n' "$CYAN" "$NC" "$CYAN" "$NC"
  if command -v zramctl >/dev/null 2>&1; then
    zramctl || true
  else
    printf '  zramctl utility is not installed.\n'
  fi
  if [ -r /sys/block/zram0/comp_algorithm ]; then
    printf '  Available algorithms: '
    cat /sys/block/zram0/comp_algorithm
    printf '\n'
  fi
  if command -v swapon >/dev/null 2>&1; then
    printf '\n%b│%b  ACTIVE SWAP                                          %b│%b\n' "$CYAN" "$NC" "$CYAN" "$NC"
    swapon --show --noheadings --output=NAME,SIZE,USED,PRIO 2>/dev/null || true
  fi
  printf '%b╰───────────────────────────────────────────────────────╯%b\n\n' "$CYAN" "$NC"
}

draw_memory_bar() {
  local percent="$1" filled index color="$GREEN"
  if [ "$percent" -gt 80 ]; then
    color="$RED"
  elif [ "$percent" -gt 60 ]; then
    color="$YELLOW"
  fi
  filled=$((percent / 5))
  printf '%b[' "$color"
  for ((index = 0; index < 20; index++)); do
    if [ "$index" -lt "$filled" ]; then
      printf '█'
    else
      printf '·'
    fi
  done
  printf ']%b %s%%' "$NC" "$percent"
}

set_swappiness() {
  local val="$1"
  set_sysctl_setting vm.swappiness "$val" 0 200 "Swappiness" /etc/sysctl.d/99-zram-swappiness.conf
}

set_cache_pressure() {
  local val="$1"
  set_sysctl_setting vm.vfs_cache_pressure "$val" 0 1000 "Cache pressure" /etc/sysctl.d/99-zram-cache-pressure.conf
}

set_sysctl_setting() {
  local key="$1" val="$2" min="$3" max="$4" label="$5" config="$6"
  if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -ge "$min" ] && [ "$val" -le "$max" ]; then
    if ! sysctl "$key=$val" > /dev/null; then
      echo -e "${RED}[!] Failed to apply ${key}.${NC}"
      return 1
    fi
    if ! printf '%s=%s\n' "$key" "$val" > "$config"; then
      echo -e "${RED}[!] Applied ${key}, but failed to save ${config}.${NC}"
      return 1
    fi
    echo -e "${GREEN}[✓] ${label} changed to ${val} and saved to ${config}${NC}"
  else
    echo -e "${RED}[!] Error: ${label} must be an integer between ${min} and ${max}.${NC}"
    return 1
  fi
}

list_algorithms() {
  printf '\n%bAvailable zRAM compression algorithms%b\n' "$CYAN" "$NC"
  if [ -r /sys/block/zram0/comp_algorithm ]; then
    printf '  '
    cat /sys/block/zram0/comp_algorithm
    printf '\n  The active algorithm is shown in [brackets].\n\n'
  else
    printf '  zRAM is not initialized; load the zram module to inspect kernel support.\n\n'
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
        if set_swappiness "$2"; then
          exit 0
        else
          exit 1
        fi
      else
        echo -e "${RED}[!] Please specify value: --swappiness 80${NC}"
        exit 1
      fi
      ;;
    --cache-pressure|-c)
      if [ -n "${2:-}" ]; then
        if set_cache_pressure "$2"; then
          exit 0
        else
          exit 1
        fi
      else
        echo -e "${RED}[!] Please specify value: --cache-pressure 100${NC}"
        exit 1
      fi
      ;;
    --algorithms|-l)
      list_algorithms
      exit 0
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
      echo "  --swappiness, -w VALUE     Set swappiness (0-200)"
      echo "  --cache-pressure, -c VALUE Set vm.vfs_cache_pressure (0-1000)"
      echo "  --algorithms, -l           List available zRAM algorithms"
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

# Interactive dashboard
while true; do
  show_status
  printf '%b  1%b  Auto configure       %b2%b  Swappiness\n' "$GREEN" "$NC" "$GREEN" "$NC"
  printf '%b  3%b  zRAM size/algorithm  %b4%b  Cache pressure\n' "$GREEN" "$NC" "$GREEN" "$NC"
  printf '%b  5%b  Algorithms          %b6%b  Refresh\n' "$GREEN" "$NC" "$GREEN" "$NC"
  printf '%b  7%b  Exit\n\n' "$GREEN" "$NC"
  read -r -p "  Select [1-7]: " choice

  case $choice in
    1)
      auto_configure
      ;;
    2)
      read -r -p "Enter swappiness value (0-200): " s_val
      set_swappiness "$s_val" || true
      ;;
    3)
      read -r -p "Enter size (e.g. 4G, 2048M or ram/2): " r_size
      read -r -p "Enter algorithm [default: zstd]: " r_algo
      r_algo=${r_algo:-zstd}
      resize_zram "$r_size" "$r_algo"
      ;;
    4)
      read -r -p "Enter vm.vfs_cache_pressure (0-1000): " c_val
      set_cache_pressure "$c_val" || true
      ;;
    5)
      list_algorithms
      read -r -p "Press Enter to return to the dashboard..." _
      ;;
    6)
      clear
      ;;
    7)
      echo "Exiting."
      exit 0
      ;;
    *)
      echo -e "${RED}  Invalid choice.${NC}"
      ;;
  esac
done