# Duckybox

A one-shot customizer that turns **Parrot OS (MATE)** into a Pwnbox-style workstation with a violet **Duckybox** identity across the whole visual chain.

Brand violet `#4B0E8F` · accent `#7C3AED` · backdrop `#12071F`

## What it themes

| Stage | What you get |
|---|---|
| GRUB | Violet menu with the duck background and a violet timeout bar |
| Plymouth | Duck mark fading in over deep violet with a real progress bar |
| LightDM | Greeter background, Duckybox GTK theme and violet icons |
| MATE desktop | `Duckybox` GTK theme (GTK2/3/4 plus `metacity-1` for Marco), violet Papirus icons, duck wallpaper picked by resolution |
| Panel | VPN IP from `tun0` in the top panel, Pwnbox-style |
| Dock | Plank with a violet `Duckybox` dock theme |
| Terminal | mate-terminal palette plus OSC sequences for any terminal |
| tmux | Violet status bar, window and pane styling |
| bash | Duck banner, violet prompt with the VPN IP inline |

## Performance

MATE stays, but the heavy parts go: Marco compositing off, `reduced-resources` on, animations disabled, desktop icon drawing off, the bottom panel replaced by Plank. `mate-*` packages are never purged, since removing them breaks networking and VPN on Parrot.

## Tools installed

**Flameshot**, **Peek**, **Obsidian** (amd64 `.deb` from GitHub Releases) and **SysReptor** (Docker, at `/opt/sysreptor`, UI on `http://127.0.0.1:8000/`).

## Requirements

- Parrot OS Security or Home with **MATE** and **LightDM**
- root via `sudo`
- Network for `apt`, the GTK theme build, Obsidian and Docker images
- amd64 for the Obsidian auto-install; ~8 GB RAM for SysReptor

## Install

```bash
git clone https://github.com/vterreno/Turfbox.git duckybox
cd duckybox
sudo ./install.sh
```

| Flag | Meaning |
|---|---|
| `--dry-run` | Log every action without touching the system |
| `--verbose` | Extra debug lines in the log |
| `--regen-brand` | Rebuild all brand assets from the logo |
| `--skip-obsidian` | Do not download Obsidian |
| `--skip-sysreptor` | Do not install Docker or SysReptor |
| `--skip-plymouth` | Leave the boot splash alone |
| `--skip-grub` | Leave GRUB alone |
| `--skip-gtk` | Do not build the GTK theme or recolor icons |

## After install

1. **Reboot.** GRUB, the splash and the login screen should all be violet.
2. Log into MATE. Theme, icons, wallpaper and Plank apply automatically.
3. Add the VPN indicator to the top panel, one time only:
   - Right-click the top panel → **Add to Panel** → **Command**
   - Command: `/opt/duckybox/vpnpanel.sh`, interval `5`
   - Also written to `~/.config/duckybox/VPN_PANEL.txt`
4. Connect your OpenVPN profile so `tun0` gets an address.
5. SysReptor: `/opt/duckybox/sysreptor-start.sh` and `sysreptor-stop.sh`. Log out and back in once if Docker denies permission.

## Verify

One command collects the whole report, including the install log tail:

```bash
bash /opt/duckybox/duckybox-doctor.sh
```

## Branding

Everything visual is derived from a single file, `assets/brand/duckybox-logo.png`. Replace it and run:

```bash
bash scripts/generate-brand.sh
```

That regenerates the transparent mark, the braille duck art, the Plymouth images, wallpapers at 1920x1080 / 2560x1440 / 3840x2160, the GRUB backgrounds, the greeter background and the menu icon set.

The wallpaper is the one exception to being generated from the logo: if `assets/brand/duckybox-wallpaper.jpg` (or `.png`) exists, that artwork is scaled to the three desktop resolutions **and** used as the login background, instead of the generated gradient scene. Drop in any 16:9 image to change it; other aspect ratios are centre-cropped to fill. GRUB keeps its own generated background, since its menu needs the lower half of the screen empty.

The GTK theme is [Orchis](https://github.com/vinceliuice/Orchis-theme) with its purple palette overwritten by the Duckybox violet before `sassc` compiles it, installed as `Duckybox`. Icons are the packaged `Papirus-Dark` with folders relinked to their violet variants, the same mechanism `papirus-folders` uses.

## Layout

```
install.sh
assets/brand/duckybox-logo.png     # the one source of truth for branding
assets/duck.txt                    # braille duck, generated
assets/{plymouth,wallpapers,grub,greeter,icons}/
configs/{tmux,gtk,terminal,bash,plank,plymouth,grub,lightdm}/
scripts/generate-brand.sh          # all asset generation
scripts/install-gtk-theme.sh       # Orchis -> Duckybox violet, icon recolor
scripts/apply-mate-theme.sh        # per-user desktop settings
scripts/duckybox-doctor.sh         # verification report
scripts/vpnpanel.sh vpnbash.sh     # VPN IP for panel and prompt
scripts/lib/pbm2braille.py         # PNG -> braille converter
```

## Notes

- Backups of replaced files use the `.duckybox.bak` suffix.
- Obsidian, SysReptor and the GTK theme build are best-effort: failures log a `WARN` and the install continues.
- If a machine was themed by the older Turfbox version, the installer removes its `~/.bashrc` block automatically.
- Peek works best on X11, which is the Parrot MATE default.
- On very fast boots the splash may only flash briefly; that is Plymouth, not the theme.
