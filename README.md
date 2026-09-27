# ⚡ zram-manager

A simple, lightweight CLI & interactive Bash tool to manage **zRAM** and **vm.swappiness** on Linux distributions (Fedora, Arch Linux, Ubuntu, Debian, etc.).

It helps optimize system memory management, prevent Out-Of-Memory (OOM) freezes, and customize compressed RAM swap settings.

---

## ✨ Features

- **🤖 Automatic Hardware Detection (`--auto`):** Automatically calculates optimal zRAM size, compression algorithm, and swappiness based on your total RAM.
- **🛡️ OOM Freeze Protection:** Checks active zRAM usage before applying live changes to prevent severe system freezes.
- **⚡ Systemd & Native Compatibility:** Native support for `systemd-zram-generator` (Fedora, Arch) and standalone zRAM kernel modules.
- **📊 Interactive & Non-Interactive (CLI) Modes:** Easy-to-use menu or terminal flags for scripting and fast access.

---

## 🚀 Installation

Clone the repository and run the installer script:

```bash
git clone [https://github.com/YOUR_USERNAME/zram-manager.git](https://github.com/YOUR_USERNAME/zram-manager.git)
cd zram-manager
sudo ./install.sh