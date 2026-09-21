#!/usr/bin/env python3
"""Duckybox — VPN status in the top-panel system tray (MATE / KDE)."""

from __future__ import annotations

import os
import re
import signal
import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

Indicator = None
for _mod, _ver in (
    ("AyatanaAppIndicator3", "0.1"),
    ("AppIndicator3", "0.1"),
):
    try:
        gi.require_version(_mod, _ver)
        Indicator = getattr(__import__("gi.repository", fromlist=[_mod]), _mod)
        break
    except (ValueError, ImportError, AttributeError):
        continue

if Indicator is None:
    sys.stderr.write("No AppIndicator library found; install gir1.2-ayatanaappindicator3-0.1\n")
    sys.exit(1)

ICON_CONNECTED = "network-vpn"
ICON_DISCONNECTED = "network-offline"
POLL_SECONDS = 5


def vpn_status() -> tuple[str, str]:
    try:
        out = subprocess.check_output(
            ["ip", "-4", "-o", "addr", "show", "tun0"],
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "VPN: Disconnected", ICON_DISCONNECTED

    match = re.search(r"inet\s+(\d+\.\d+\.\d+\.\d+)", out)
    if not match:
        return "VPN: Disconnected", ICON_DISCONNECTED
    return f"VPN: {match.group(1)}", ICON_CONNECTED


class VpnIndicator:
    def __init__(self) -> None:
        self.indicator = Indicator.Indicator.new(
            "duckybox-vpn",
            ICON_DISCONNECTED,
            Indicator.IndicatorCategory.SYSTEM_SERVICES,
        )
        self.indicator.set_status(Indicator.IndicatorStatus.ACTIVE)
        self.indicator.set_title("Duckybox VPN")

        menu = Gtk.Menu()
        quit_item = Gtk.MenuItem(label="Quit")
        quit_item.connect("activate", lambda *_: Gtk.main_quit())
        menu.append(quit_item)
        menu.show_all()
        self.indicator.set_menu(menu)

        self.refresh()
        GLib.timeout_add_seconds(POLL_SECONDS, self.refresh)

    def refresh(self) -> bool:
        label, icon = vpn_status()
        self.indicator.set_label(label, "VPN: 000.000.000.000")
        self.indicator.set_icon_full(icon, label)
        return True


def main() -> int:
    # Single instance: a second copy would just duplicate the tray entry.
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/tmp/duckybox-{os.getuid()}")
    os.makedirs(runtime, exist_ok=True)
    lock_path = os.path.join(runtime, "duckybox-vpn.lock")
    lock_fd = open(lock_path, "w", encoding="utf-8")
    try:
        import fcntl

        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return 0

    signal.signal(signal.SIGINT, signal.SIG_DFL)
    VpnIndicator()
    Gtk.main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
