# zram-manager

A simple, lightweight CLI & interactive Bash tool to manage **zRAM** and **vm.swappiness** on Linux distributions (Fedora, Arch Linux, Ubuntu, Debian, etc.), with a separate PowerShell version for Windows.

It helps optimize system memory management, prevent Out-Of-Memory (OOM) freezes, and customize compressed RAM swap settings.

---

##  Features

- ** Automatic Hardware Detection (`--auto`):** Automatically calculates optimal zRAM size, compression algorithm, and swappiness based on your total RAM.
- ** OOM Freeze Protection:** Checks active zRAM usage before applying live changes to prevent severe system freezes.
- ** Systemd & Native Compatibility:** Native support for `systemd-zram-generator` (Fedora, Arch) and standalone zRAM kernel modules.
- ** RAM Dashboard:** Shows used, available, and total memory, swap activity, active zRAM devices, and a color-coded RAM usage bar.
- ** Kernel Memory Tuning:** Configure persistent `vm.swappiness` (0-200) and `vm.vfs_cache_pressure` (0-1000) values.
- ** Compression Discovery:** Lists algorithms supported by the running zRAM device and marks the active algorithm.
- ** Interactive & Non-Interactive (CLI) Modes:** Easy-to-use menu or terminal flags for scripting and fast access.

## Windows version

Windows does not provide Linux zRAM, `vm.swappiness`, or Linux zRAM compression algorithms. The Windows version manages the closest native equivalents:

- Windows **Memory Compression**;
- automatic Windows **page-file** management;
- RAM and page-file status reporting.

Open PowerShell **as Administrator** in the repository directory and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\zram-manager.ps1 -Status
.\zram-manager.ps1 -Auto
```

Other commands:

```powershell
.\zram-manager.ps1 -EnableCompression
.\zram-manager.ps1 -DisableCompression
.\zram-manager.ps1 -PageFileAutomatic
```

The Windows script does not modify Linux settings. To use actual zRAM on Windows, run the Bash version inside a Linux environment such as WSL; it will manage zRAM only when the WSL kernel exposes the required zRAM support.

---

##  Installation

Clone the repository and run the installer script:

```bash
git clone https://github.com/mars74da4p/zram-manager.git
cd zram-manager
sudo ./install.sh
```

## Usage

Run `sudo zram-manager` to open the interactive dashboard. CLI commands are also available:

```bash
sudo zram-manager --status
sudo zram-manager --algorithms
sudo zram-manager --swappiness 100
sudo zram-manager --cache-pressure 100
sudo zram-manager --resize 4G zstd
```

Swappiness and cache pressure are applied immediately and saved under `/etc/sysctl.d/` for future boots. The dashboard reports memory and swap use before zRAM configuration changes; follow its warning when a live reload could exhaust available RAM.
