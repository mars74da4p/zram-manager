#!/usr/bin/env bash
# Installer script for zram-manager

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Error: Please run this installer with sudo!${NC}"
  exit 1
fi

echo -e "${CYAN}[*] Installing zram-manager to /usr/local/bin/zram-manager...${NC}"

cp zram-manager.sh /usr/local/bin/zram-manager
chmod +x /usr/local/bin/zram-manager

echo -e "${GREEN}[✓] Installation complete!${NC}"
echo -e "You can now run the tool from anywhere using: ${CYAN}sudo zram-manager${NC}"