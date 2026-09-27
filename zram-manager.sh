#!/usr/bin/env bash
# zram-manager - CLI & Interactive tool for managing zRAM and swappiness on Linux

set -euo pipefail

# Цветовая палитра для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Проверка root-прав
check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] Ошибка: запустите скрипт с sudo!${NC}"
    exit 1
  fi
}

show_status() {
  echo -e "\n${CYAN}=== Текущее состояние памяти и zRAM ===${NC}"
  echo "Оперативная память (RAM):"
  free -h | grep "Mem:" | awk '{print "  Всего: " $2 " | Занято: " $3 " | Свободно: " $4}'
  
  echo -e "\nПараметр vm.swappiness:"
  echo "  Текущее значение: $(sysctl -n vm.swappiness)"
  
  echo -e "\nСтатус zRAM:"
  if command -v zramctl >/dev/null 2>&1; then
    zramctl
  else
    echo "  Утилита zramctl не найдена или zRAM не инициализирован."
  fi
  echo -e "${CYAN}=======================================${NC}\n"
}

set_swappiness() {
  local val="$1"
  if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -ge 0 ] && [ "$val" -le 100 ]; then
    sysctl vm.swappiness="$val" > /dev/null
    echo "vm.swappiness=$val" > /etc/sysctl.d/99-zram-swappiness.conf
    echo -e "${GREEN}[✓] Swappiness изменён на $val и сохранён в /etc/sysctl.d/99-zram-swappiness.conf${NC}"
  else
    echo -e "${RED}[!] Ошибка: значение должно быть числом от 0 до 100.${NC}"
  fi
}

check_safe_reload() {
  # Проверка безопасности перезапуска zRAM на лету
  local free_ram_mb
  free_ram_mb=$(free -m | awk '/Mem:/ {print $4}')
  
  local used_zram_bytes=0
  if command -v zramctl >/dev/null 2>&1; then
    used_zram_bytes=$(zramctl --noheadings --output DATA 2>/dev/null | head -n1 | numfmt --from=iec 2>/dev/null || echo 0)
  fi
  
  local used_zram_mb=$((used_zram_bytes / 1024 / 1024))

  if [ "$used_zram_mb" -gt "$free_ram_mb" ]; then
    echo -e "${RED}[!] ОПАНОСТЬ ЗАВИСАНИЯ СИСТЕМЫ!${NC}"
    echo -e "${YELLOW}[!] В zRAM находится ${used_zram_mb} MB данных, а свободной ОЗУ всего ${free_ram_mb} MB.${NC}"
    echo -e "${YELLOW}[!] При отключении swap для перенастройки система зависнет от нехватки памяти.${NC}\n"
    echo "Решение: закройте тяжёлые программы (например, браузер) или перезагрузите ПК после изменения конфига."
    read -p "Всё равно применить конфиг без перезапуска службы на лету? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo -e "${RED}[*] Операция отменена пользователем.${NC}"
      exit 1
    fi
    return 1 # Флаг: только изменить файл конфигурации, не перезапускать службу
  fi
  return 0
}

resize_zram() {
  local zsize="$1"
  local algo="${2:-zstd}"

  echo -e "${YELLOW}[*] Проверка безопасности перед изменением zRAM...${NC}"
  
  local safe_to_reload=0
  if check_safe_reload; then
    safe_to_reload=1
  fi

  echo -e "${YELLOW}[*] Настройка zRAM ($zsize, алгоритм: $algo)...${NC}"

  # Обработка для дистрибутивов с systemd-zram-generator (Fedora, Arch)
  if [ -d "/etc/systemd/zram-generator.conf.d" ] || [ -f "/etc/systemd/zram-generator.conf" ]; then
    mkdir -p /etc/systemd/zram-generator.conf.d
    cat <<EOF > /etc/systemd/zram-generator.conf.d/override.conf
[zram0]
zram-size = $zsize
compression-algorithm = $algo
EOF
    echo -e "${GREEN}[✓] Конфигурация /etc/systemd/zram-generator.conf.d/override.conf обновлена.${NC}"
    
    if [ "$safe_to_reload" -eq 1 ]; then
      echo -e "${YELLOW}[*] Перезапуск службы systemd-zram-setup@zram0...${NC}"
      systemctl restart systemd-zram-setup@zram0.service || true
      echo -e "${GREEN}[✓] zRAM успешно перенастроен на размер $zsize!${NC}"
    else
      echo -e "${GREEN}[✓] Конфиг сохранен! Новые настройки zRAM применятся после перезагрузки ПК.${NC}"
    fi
  else
    if [ "$safe_to_reload" -eq 0 ]; then
      echo -e "${RED}[!] Изменение zRAM на лету отменено из-за риска OOM. Освободите ОЗУ и повторите.${NC}"
      exit 1
    fi

    # Ручной перезапуск zRAM
    if swapoff /dev/zram0 2>/dev/null; then
      echo "  Подкачка /dev/zram0 отключена."
    fi

    if [ -f /sys/block/zram0/reset ]; then
      echo 1 > /sys/block/zram0/reset 2>/dev/null || true
    fi

    modprobe zram num_devices=1 2>/dev/null || true
    echo "$algo" > /sys/block/zram0/comp_algorithm
    echo "$zsize" > /sys/block/zram0/disksize

    mkswap /dev/zram0 >/dev/null
    swapon -p 100 /dev/zram0
    echo -e "${GREEN}[✓] zRAM успешно перенастроен!${NC}"
  fi
}

# Обработка флагов командной строки
check_root

if [ $# -gt 0 ]; then
  case "$1" in
    --status|-s)
      show_status
      exit 0
      ;;
    --swappiness|-w)
      if [ -n "${2:-}" ]; then
        set_swappiness "$2"
        exit 0
      else
        echo -e "${RED}[!] Укажите значение: --swappiness 80${NC}"
        exit 1
      fi
      ;;
    --resize|-r)
      if [ -n "${2:-}" ]; then
        resize_zram "$2" "${3:-zstd}"
        exit 0
      else
        echo -e "${RED}[!] Укажите размер: --resize 4G [алгоритм]${NC}"
        exit 1
      fi
      ;;
    --help|-h)
      echo "Использование: sudo ./zram-manager.sh [ФЛАГ]"
      echo "  --status, -s               Показать текущий статус"
      echo "  --swappiness, -w VALUE     Установить swappiness (0-100)"
      echo "  --resize, -r SIZE [ALGO]   Установить размер zRAM (например, 4G, ram/2) и алгоритм (zstd, lzo-rle)"
      echo "  --help, -h                 Показать эту справку"
      exit 0
      ;;
    *)
      echo -e "${RED}[!] Неизвестный флаг: $1${NC}"
      exit 1
      ;;
  esac
fi

# Интерактивное меню
while true; do
  show_status
  echo "1) Изменить vm.swappiness"
  echo "2) Изменить размер и алгоритм zRAM"
  echo "3) Обновить статус"
  echo "4) Выход"
  read -p "Выберите действие [1-4]: " choice

  case $choice in
    1)
      read -p "Введите значение swappiness (0-100): " s_val
      set_swappiness "$s_val"
      ;;
    2)
      read -p "Введите размер (например, 4G, 2048M или ram/2): " r_size
      read -p "Введите алгоритм [по умолчанию zstd]: " r_algo
      r_algo=${r_algo:-zstd}
      resize_zram "$r_size" "$r_algo"
      ;;
    3)
      clear
      ;;
    4)
      echo "Выход."
      exit 0
      ;;
    *)
      echo -e "${RED}Неверный выбор.${NC}"
      ;;
  esac
done
