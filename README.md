# Turfbox

Script to customize **Parrot OS (MATE)** into a Pwnbox-style desktop with an orange **Turfbox** theme.

## Features

- Lighter MATE setup (Marco compositing off, Plank dock, fewer heavy panel applets)
- Orange dark aesthetic (GTK overrides, terminal colors, wallpaper)
- VPN IP (`tun0`) on the top panel via `/opt/turfbox/vpnpanel.sh`
- VPN IP in the bash prompt
- Custom orange **tmux** status bar
- **Plymouth** boot splash: “Turfbox” + horse ASCII (fade + progress pulse)
- Installs **Flameshot**, **Peek**, **Obsidian** (amd64 `.deb`), and **SysReptor** (Docker)
- Structured install logging to `/var/log/turfbox-install.log`

## Requirements

- Parrot OS Security or Home with **MATE**
- `sudo` / root
- Network (for `apt`, Obsidian, Docker images, SysReptor)
- amd64 recommended for Obsidian auto-install
- ~8 GB RAM recommended for SysReptor (per upstream docs)

## Install

```bash
git clone https://github.com/vterreno/Turfbox.git
cd Turfbox
sudo ./install.sh
```

Options:

| Flag | Meaning |
|------|---------|
| `--dry-run` | Log actions without changing the system |
| `--verbose` | Extra debug lines in the log |
| `--skip-obsidian` | Do not download Obsidian |
| `--skip-plymouth` | Skip Plymouth / GRUB / initramfs changes |
| `--skip-sysreptor` | Do not install Docker / SysReptor |

## After install

1. **Reboot** to see the Turfbox Plymouth splash.
2. Log into **MATE**. Plank and the orange theme should load.
3. Add the VPN indicator to the top panel (once):
   - Right-click top panel → **Add to Panel** → **Command**
   - Command: `/opt/turfbox/vpnpanel.sh`
   - Interval: `5` seconds  
   Details are also in `~/.config/turfbox/VPN_PANEL.txt`.
4. Connect your OpenVPN profile so `tun0` gets an IP — the panel and prompt will show it.
5. Use **Flameshot**, **Peek**, and **Obsidian** from the dock/menus.
6. Open **SysReptor** at [http://127.0.0.1:8000/](http://127.0.0.1:8000/)  
   - Start: `/opt/turfbox/sysreptor-start.sh`  
   - Stop: `/opt/turfbox/sysreptor-stop.sh`  
   - Notes: `~/.config/turfbox/SYSREPTOR.txt`  
   - Log out/in once if `docker` permission is denied (docker group).

## Verify

```bash
# VPN helper
/opt/turfbox/vpnpanel.sh

# tmux theme
tmux new -s turfbox

# Install log
less /var/log/turfbox-install.log

# Plymouth theme
plymouth-set-default-theme -l | grep turfbox

# SysReptor
docker compose -f /opt/sysreptor/deploy/docker-compose.yml ps 2>/dev/null || true
curl -sI http://127.0.0.1:8000/ | head -n1
```

## Layout

```
install.sh
assets/horse.txt
assets/turfbox-banner.txt
configs/tmux/tmux.conf
configs/gtk/
configs/plymouth/turfbox/
configs/bash/turfbox.bashrc
scripts/vpnpanel.sh
scripts/vpnbash.sh
scripts/apply-mate-theme.sh
scripts/generate-splash.sh
```

## Notes

- The installer does **not** purge `mate-*` packages (that can break networking/VPN).
- Obsidian and SysReptor installs are best-effort: failures are logged as `WARN` and the rest continues.
- SysReptor uses the [official install script](https://docs.sysreptor.com/setup/installation/) after ensuring Docker; officially aimed at Ubuntu but works on Parrot/Kali-style hosts when Docker is present.
- Peek works best on X11 (default Parrot MATE).
- Backups of overwritten files use the `.turfbox.bak` suffix.
