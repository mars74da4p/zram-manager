#!/usr/bin/env python3

import os
import shlex
import subprocess
import threading
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk


APP_TITLE = "zram-manager"
ZRAM_SERVICE = "systemd-zram-setup@zram0.service"


def run_command(command, elevated=False, timeout=30):
    if elevated:
        command = ["pkexec", "--disable-internal-agent", *command]
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or f"Command exited with {result.returncode}")
    return result.stdout.strip()


def human_bytes(value):
    value = int(value)
    units = ("B", "KiB", "MiB", "GiB", "TiB")
    for unit in units:
        if abs(value) < 1024 or unit == units[-1]:
            if unit == "B":
                return f"{value} {unit}"
            return f"{value / 1024:.1f} {unit}"
        value /= 1024


def find_program(name):
    for directory in os.environ.get("PATH", "").split(":"):
        candidate = Path(directory) / name
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return name


class ZramWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(title=APP_TITLE, application=app)
        self.set_default_size(760, 620)
        self.set_border_width(12)
        self.worker_busy = False

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(root)

        header = Gtk.HeaderBar(title="zram-manager", subtitle="Linux memory manager")
        header.set_show_close_button(True)
        self.set_titlebar(header)

        refresh_button = Gtk.Button(label="Refresh")
        refresh_button.set_tooltip_text("Refresh system status")
        refresh_button.connect("clicked", lambda *_: self.refresh_status())
        header.pack_end(refresh_button)

        self.status_label = Gtk.Label(label="Status: loading…", xalign=0)
        self.status_label.get_style_context().add_class("dim-label")
        root.pack_start(self.status_label, False, False, 0)

        grid = Gtk.Grid(column_spacing=16, row_spacing=10)
        grid.set_margin_bottom(4)
        root.pack_start(grid, False, False, 0)

        self.ram_used_label = Gtk.Label(label="—", xalign=0)
        self.ram_total_label = Gtk.Label(label="—", xalign=0)
        self.swap_label = Gtk.Label(label="—", xalign=0)
        self.swappiness_label = Gtk.Label(label="—", xalign=0)
        self.cache_label = Gtk.Label(label="—", xalign=0)
        self.zram_label = Gtk.Label(label="—", xalign=0)

        labels = (
            ("RAM used", self.ram_used_label),
            ("RAM total", self.ram_total_label),
            ("Swap", self.swap_label),
            ("vm.swappiness", self.swappiness_label),
            ("vm.vfs_cache_pressure", self.cache_label),
            ("zRAM", self.zram_label),
        )
        for row, (name, value) in enumerate(labels):
            name_label = Gtk.Label(label=name, xalign=0)
            name_label.get_style_context().add_class("dim-label")
            grid.attach(name_label, 0, row, 1, 1)
            grid.attach(value, 1, row, 1, 1)

        self.ram_bar = Gtk.ProgressBar()
        self.ram_bar.set_hexpand(True)
        grid.attach(self.ram_bar, 2, 0, 2, 1)

        tuning = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        root.pack_start(tuning, False, False, 0)

        auto_button = Gtk.Button(label="Auto configure")
        auto_button.connect("clicked", self.on_auto)
        tuning.pack_start(auto_button, False, False, 0)

        refresh = Gtk.Button(label="Refresh status")
        refresh.connect("clicked", lambda *_: self.refresh_status())
        tuning.pack_start(refresh, False, False, 0)

        notebook = Gtk.Notebook()
        root.pack_start(notebook, True, True, 0)

        kernel_page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        kernel_page.set_border_width(12)
        notebook.append_page(kernel_page, Gtk.Label(label="Kernel tuning"))

        kernel_grid = Gtk.Grid(column_spacing=12, row_spacing=10)
        kernel_page.pack_start(kernel_grid, False, False, 0)

        kernel_grid.attach(Gtk.Label(label="Swappiness (0–200)", xalign=0), 0, 0, 1, 1)
        self.swappiness_spin = Gtk.SpinButton.new_with_range(0, 200, 1)
        kernel_grid.attach(self.swappiness_spin, 1, 0, 1, 1)
        apply_swappiness = Gtk.Button(label="Apply")
        apply_swappiness.connect("clicked", self.on_apply_swappiness)
        kernel_grid.attach(apply_swappiness, 2, 0, 1, 1)

        kernel_grid.attach(Gtk.Label(label="Cache pressure (0–1000)", xalign=0), 0, 1, 1, 1)
        self.cache_spin = Gtk.SpinButton.new_with_range(0, 1000, 1)
        kernel_grid.attach(self.cache_spin, 1, 1, 1, 1)
        apply_cache = Gtk.Button(label="Apply")
        apply_cache.connect("clicked", self.on_apply_cache)
        kernel_grid.attach(apply_cache, 2, 1, 1, 1)

        zram_page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        zram_page.set_border_width(12)
        notebook.append_page(zram_page, Gtk.Label(label="zRAM"))

        zram_grid = Gtk.Grid(column_spacing=12, row_spacing=10)
        zram_page.pack_start(zram_grid, False, False, 0)

        zram_grid.attach(Gtk.Label(label="Size", xalign=0), 0, 0, 1, 1)
        self.size_entry = Gtk.Entry()
        self.size_entry.set_hexpand(True)
        self.size_entry.set_text("ram / 2")
        zram_grid.attach(self.size_entry, 1, 0, 1, 1)

        zram_grid.attach(Gtk.Label(label="Algorithm", xalign=0), 0, 1, 1, 1)
        self.algorithm_combo = Gtk.ComboBoxText()
        zram_grid.attach(self.algorithm_combo, 1, 1, 1, 1)

        apply_zram = Gtk.Button(label="Apply zRAM configuration")
        apply_zram.get_style_context().add_class("suggested-action")
        apply_zram.connect("clicked", self.on_apply_zram)
        zram_page.pack_start(apply_zram, False, False, 0)

        log_frame = Gtk.Frame(label="Operation log")
        log_frame.set_vexpand(True)
        log_scroll = Gtk.ScrolledWindow()
        log_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        self.log_view = Gtk.TextView(editable=False, cursor_visible=False)
        self.log_view.set_monospace(True)
        self.log_view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        log_scroll.add(self.log_view)
        log_frame.add(log_scroll)
        root.pack_start(log_frame, True, True, 0)

        self.refresh_status()

    def append_log(self, message):
        GLib.idle_add(self._append_log, message)

    def _append_log(self, message):
        buffer = self.log_view.get_buffer()
        buffer.insert(buffer.get_end_iter(), message.rstrip() + "\n")
        mark = buffer.create_mark(None, buffer.get_end_iter(), False)
        self.log_view.scroll_mark_onscreen(mark)

    def set_busy(self, busy):
        self.worker_busy = busy
        GLib.idle_add(self.status_label.set_text, "Status: operation in progress…" if busy else "Status: ready")

    def refresh_status(self):
        if self.worker_busy:
            return

        def worker():
            try:
                mem = run_command(["free", "-b"])
                lines = mem.splitlines()
                mem_line = next(line.split() for line in lines if line.startswith("Mem:"))
                swap_line = next(line.split() for line in lines if line.startswith("Swap:"))
                ram_total = int(mem_line[1])
                ram_used = int(mem_line[2])
                ram_available = int(mem_line[6]) if len(mem_line) > 6 else ram_total - ram_used
                swap_total = int(swap_line[1])
                swap_used = int(swap_line[2])
                ram_percent = round(ram_used * 100 / ram_total) if ram_total else 0

                swappiness = run_command(["sysctl", "-n", "vm.swappiness"])
                cache = run_command(["sysctl", "-n", "vm.vfs_cache_pressure"])

                zram_text = "not initialized"
                try:
                    zram_text = run_command(["zramctl", "--noheadings", "--bytes", "--output", "NAME,SIZE,DATA,USED"]).strip()
                except (RuntimeError, FileNotFoundError, subprocess.TimeoutExpired):
                    zram_text = "zramctl unavailable or no zRAM device"

                algorithms = []
                algorithm_path = Path("/sys/block/zram0/comp_algorithm")
                if algorithm_path.exists():
                    raw = algorithm_path.read_text().strip()
                    for item in raw.split():
                        item = item.strip("[]")
                        if item:
                            algorithms.append(item)

                GLib.idle_add(
                    self.update_status,
                    ram_used,
                    ram_total,
                    ram_available,
                    ram_percent,
                    swap_used,
                    swap_total,
                    int(swappiness),
                    int(cache),
                    zram_text,
                    algorithms,
                )
            except Exception as exc:
                GLib.idle_add(self.show_error, str(exc))

        threading.Thread(target=worker, daemon=True).start()

    def update_status(self, ram_used, ram_total, ram_available, ram_percent, swap_used, swap_total, swappiness, cache, zram_text, algorithms):
        self.ram_used_label.set_text(f"{human_bytes(ram_used)} ({ram_percent}% used)")
        self.ram_total_label.set_text(human_bytes(ram_total))
        self.swap_label.set_text(f"{human_bytes(swap_used)} used / {human_bytes(swap_total)} total")
        self.swappiness_label.set_text(str(swappiness))
        self.cache_label.set_text(str(cache))
        self.zram_label.set_text(zram_text.replace("\n", " | "))
        self.ram_bar.set_fraction(ram_percent / 100)
        self.ram_bar.set_text(f"{ram_percent}%")
        self.status_label.set_text("Status: ready")
        self.swappiness_spin.set_value(swappiness)
        self.cache_spin.set_value(cache)

        current_algorithm = self.algorithm_combo.get_active_text()
        self.algorithm_combo.remove_all()
        for algorithm in algorithms:
            self.algorithm_combo.append_text(algorithm)
        if algorithms:
            active_index = 0
            if current_algorithm in algorithms:
                active_index = algorithms.index(current_algorithm)
            self.algorithm_combo.set_active(active_index)
        else:
            self.algorithm_combo.append_text("zstd")
            self.algorithm_combo.append_text("lzo-rle")
            self.algorithm_combo.append_text("lz4")
            self.algorithm_combo.set_active(0)

    def show_error(self, message):
        self.status_label.set_text("Status: error")
        dialog = Gtk.MessageDialog(
            transient_for=self,
            modal=True,
            buttons=Gtk.ButtonsType.OK,
            message_type=Gtk.MessageType.ERROR,
            text="Operation failed",
        )
        dialog.format_secondary_text(message)
        dialog.run()
        dialog.destroy()

    def confirm(self, title, text):
        dialog = Gtk.MessageDialog(
            transient_for=self,
            modal=True,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            message_type=Gtk.MessageType.WARNING,
            text=title,
        )
        dialog.format_secondary_text(text)
        response = dialog.run()
        dialog.destroy()
        return response == Gtk.ResponseType.OK

    def run_elevated(self, command, description):
        if self.worker_busy:
            return
        self.set_busy(True)

        def worker():
            try:
                output = run_command(command, elevated=True, timeout=120)
                if output:
                    self.append_log(output)
                self.append_log(f"✓ {description}")
            except Exception as exc:
                self.append_log(f"✗ {description}: {exc}")
                GLib.idle_add(self.show_error, str(exc))
            finally:
                GLib.idle_add(self.set_busy, False)
                GLib.idle_add(self.refresh_status)

        threading.Thread(target=worker, daemon=True).start()

    def on_apply_swappiness(self, *_args):
        value = int(self.swappiness_spin.get_value())
        script = (
            f"sysctl vm.swappiness={value} >/dev/null && "
            "mkdir -p /etc/sysctl.d && "
            f"printf 'vm.swappiness={value}\\n' > /etc/sysctl.d/99-zram-swappiness.conf"
        )
        if self.confirm("Apply swappiness", f"Set vm.swappiness to {value} and save it persistently?"):
            self.run_elevated(["bash", "-c", script], f"Swappiness set to {value}")

    def on_apply_cache(self, *_args):
        value = int(self.cache_spin.get_value())
        script = (
            f"sysctl vm.vfs_cache_pressure={value} >/dev/null && "
            "mkdir -p /etc/sysctl.d && "
            f"printf 'vm.vfs_cache_pressure={value}\\n' > /etc/sysctl.d/99-zram-cache-pressure.conf"
        )
        if self.confirm("Apply cache pressure", f"Set vm.vfs_cache_pressure to {value} and save it persistently?"):
            self.run_elevated(["bash", "-c", script], f"Cache pressure set to {value}")

    def on_auto(self, *_args):
        try:
            ram_kib = int(run_command(["awk", "/MemTotal:/ {print $2}", "/proc/meminfo"]))
        except Exception:
            ram_kib = 0
        ram_mb = ram_kib // 1024
        if ram_mb:
            zram_size = "ram" if ram_mb <= 4096 else "ram / 2"
            swappiness = 100
            text = f"Recommended for {ram_mb // 1024 + (1 if ram_mb % 1024 else 0)} GiB RAM:\n• zRAM: {zram_size}\n• Compression: zstd\n• Swappiness: {swappiness}"
        else:
            zram_size = "ram / 2"
            swappiness = 100
            text = "Automatic detection could not read RAM. Recommended fallback:\n• zRAM: ram / 2\n• Compression: zstd\n• Swappiness: 100"

        if not self.confirm("Auto configure", text + "\n\nApply these settings?"):
            return

        script = (
            f"sysctl vm.swappiness={swappiness} >/dev/null && "
            "mkdir -p /etc/sysctl.d && "
            f"printf 'vm.swappiness={swappiness}\\n' > /etc/sysctl.d/99-zram-swappiness.conf && "
            "mkdir -p /etc/systemd/zram-generator.conf.d && "
            "cat > /etc/systemd/zram-generator.conf.d/override.conf <<'EOF'
"
            f"[zram0]\nzram-size = {zram_size}\ncompression-algorithm = zstd\n"
            "EOF
"
            f"systemctl restart {ZRAM_SERVICE} >/dev/null 2>&1 || true"
        )
        self.run_elevated(["bash", "-c", script], "Automatic configuration applied")

    def on_apply_zram(self, *_args):
        size = self.size_entry.get_text().strip()
        algorithm = self.algorithm_combo.get_active_text() or "zstd"
        if not size:
            self.show_error("Enter a zRAM size, for example: 4G, 2048M or ram / 2")
            return
        if not self.confirm("Apply zRAM configuration", f"Set zRAM size to {size} and algorithm to {algorithm}?\n\nA live restart may affect active swap."):
            return

        script = (
            "mkdir -p /etc/systemd/zram-generator.conf.d && "
            "cat > /etc/systemd/zram-generator.conf.d/override.conf <<'EOF'
"
            f"[zram0]\nzram-size = {size}\ncompression-algorithm = {algorithm}\n"
            "EOF
"
            f"systemctl restart {ZRAM_SERVICE} >/dev/null 2>&1 || true"
        )
        self.run_elevated(["bash", "-c", script], f"zRAM set to {size} using {algorithm}")


class ZramApplication(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="org.github.mars74da4p.zram-manager")

    def do_activate(self):
        win = self.props.active_window
        if not win:
            win = ZramWindow(self)
        win.present()


def main():
    app = ZramApplication()
    app.run()


if __name__ == "__main__":
    main()
