# ⚡ zram-manager

> Простой и быстрый CLI-инструмент для управления zRAM и `vm.swappiness` в Linux.

Поддерживает как дистрибутивы с `systemd-zram-generator` (Fedora, Arch Linux), так и классический ручной перезапуск zRAM.

---

## 🚀 Возможности

- 📊 **Мониторинг:** Быстрый просмотр ОЗУ, текущего размера zRAM, алгоритма сжатия и `swappiness`.
- ⚙️ **Настройка Swappiness:** Изменение `vm.swappiness` на лету с сохранением в `/etc/sysctl.d/99-zram-swappiness.conf`.
- 🗜️ **Управление zRAM:** Изменение размера (например, `4G`, `50%`, `ram/2`) и алгоритма сжатия (`zstd`, `lzo-rle`, `lz4`).
- 🤖 **Интерактивный и CLI-режимы:** Работает через удобное меню или прямые флаги командной строки.

---

## 🛠 Установка

```bash
git clone [https://github.com/mars74da4p/zram-manager.git](https://github.com/mars74da4p/zram-manager.git)
cd zram-manager
sudo chmod +x install.sh zram-manager.sh
sudo ./install.sh
