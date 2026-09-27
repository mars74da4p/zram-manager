#!/usr/bin/env bash
# install.sh - Скрипт установки zram-manager в систему

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Ошибка: запустите install.sh с правами sudo!${NC}"
  exit 1
fi

INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="zram-manager"

echo "[*] Установка $SCRIPT_NAME в $INSTALL_DIR..."

if [ -f "$SCRIPT_NAME.sh" ]; then
  cp "$SCRIPT_NAME.sh" "$INSTALL_DIR/$SCRIPT_NAME"
  chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
  echo -e "${GREEN}[✓] Установка завершена! Теперь можно запускать: sudo $SCRIPT_NAME${NC}"
else
  echo -e "${RED}[!] Файл $SCRIPT_NAME.sh не найден в текущей директории.${NC}"
  exit 1
fi
