# Linux GTK graphical interface

`feature/linux-gtk-gui` contains a native GTK3 graphical interface for the existing Linux CLI tool.

## Requirements

- Linux
- Python 3
- PyGObject (`gi.repository.Gtk`)
- `pkexec`, `free`, `sysctl`, `systemctl`, and optionally `zramctl`

### Distribution packages

```bash
# Fedora
sudo dnf install python3-gobject gtk3 polkit

# Debian / Ubuntu
sudo apt install python3-gi gir1.2-gtk-3.0 policykit-1

# Arch Linux
sudo pacman -S python-gobject gtk3 polkit
```

## Run directly

```bash
chmod +x zram-gui.py
./zram-gui.py
```

## Install

```bash
sudo ./install-gui.sh
zram-manager-gui
```

The application uses `pkexec` for privileged writes to `/etc/sysctl.d`, `/etc/systemd/zram-generator.conf.d`, and for service restart requests. It does not bypass the existing OOM safety policy; prefer reviewing active zRAM usage before resizing.
