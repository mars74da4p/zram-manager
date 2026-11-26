#!/usr/bin/env bash
set -e

INSTALL_DIR="/usr/local/lib/zram-manager"

install -Dm755 zram-gui.py "$INSTALL_DIR/zram-gui.py"
install -Dm755 zram-manager.sh /usr/local/bin/zram-manager
install -Dm755 zram-gui.py /usr/local/bin/zram-manager-gui
install -Dm644 zram-manager-gui.desktop /usr/share/applications/zram-manager-gui.desktop

chmod 755 /usr/local/bin/zram-manager-gui
update-desktop-database /usr/share/applications >/dev/null 2>&1 || true

echo "Installed zram-manager-gui. Launch it from the application menu or run zram-manager-gui."
