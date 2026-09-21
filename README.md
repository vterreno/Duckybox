# Duckybox

A one-shot customizer that turns **Parrot OS (MATE)** into a Pwnbox-style workstation with a violet **Duckybox** identity across the whole visual chain.

Brand violet `#4B0E8F` · accent `#7C3AED` · backdrop `#12071F`

## What it themes

| Stage | What you get |
|---|---|
| GRUB | Violet menu with the duck background and a violet timeout bar |
| Plymouth | The duck mark alone on deep violet, static by default |
| Login screen | LightDM greeter or SDDM, whichever the machine actually uses, with the duck background |
| MATE | `Duckybox` GTK theme (GTK2/3/4 plus `metacity-1` for Marco), violet Papirus icons, Plank dock, duck wallpaper picked by resolution |
| KDE Plasma | `Duckybox` colour scheme with violet titlebars, Papirus-Dark violet icons, Konsole profile, same wallpaper |
| VPN | `tun0` address in the top panel (Command applet on MATE, tray + plasmoid on KDE) |
| Terminal | mate-terminal and Konsole palettes, plus OSC sequences for any terminal |
| tmux | Violet status bar, window and pane styling |
| bash | Duck banner, violet prompt with the VPN IP inline |

Both desktops are supported and detected automatically. `--session auto` themes whichever of MATE and KDE is installed, so a machine with both gets both.

## Performance

The desktop stays, the expensive parts go.

On MATE: Marco compositing off, `reduced-resources` on, animations disabled, desktop icon drawing off, bottom panel replaced by Plank.

On KDE: KWin compositing off (X11 only), animation duration factor zero, blur and slide effects disabled, and Baloo file indexing disabled, which is the biggest single win on a pentest box.

`mate-*` and `plasma-*` packages are never purged, since removing them breaks networking and VPN on Parrot.

## Keyboard and mouse

The installer sets the keyboard layout to **Spanish (Latin America)**, `latam` in XKB terms, and turns on **inverted scroll direction** for every pointing device. Change the layout with `--keyboard`, for example `sudo ./install.sh --keyboard us`.

Both are applied at two levels on purpose. System-wide, through `localectl` and `/etc/default/keyboard` for the layout and an `InputClass` snippet in `/etc/X11/xorg.conf.d/99-duckybox-input.conf` for scrolling, so they hold at the login screen and in sessions the installer never sees. Then again per desktop, because MATE and Plasma keep their own copies and their settings panels would otherwise still show the old values.

Plasma keys scroll direction by vendor id, product id and device name rather than offering one global switch, so the apply script enumerates the pointing devices and writes an entry per device. Only devices that actually expose the libinput property are touched. The change also lands in the running session, so no logout is needed. On Wayland the X11 snippet does not apply, but the Plasma settings still do.

## Boot splash

The stage between GRUB and the login screen has three styles, picked with `--plymouth`:

- **`minimal`** (default) — the duck mark alone, centred and static on the violet backdrop. No progress bar, no fade, no text.
- **`full`** — the duck fades in, then a violet progress bar fills below it.
- **`none`** — no splash at all. Removes `quiet splash` from the kernel command line so the boot shows kernel and systemd messages. Other kernel parameters are preserved.

Switching is a re-run, never a file edit: `sudo ./install.sh --plymouth full`. Both variants live in `configs/plymouth/duckybox/` and the installer copies the chosen one to `duckybox.script`.

Neither variant draws a spinner or throbber, so if you see one, it belongs to another theme. Three things decide which theme runs and they do not agree, which is why a theme can be installed while a distro splash still draws: `/etc/plymouth/plymouthd.conf` wins over the `default.plymouth` alternative, and the initramfs carries its own copy of the theme that draws during early boot, before the root filesystem is mounted. The installer sets all three and warns if the initramfs does not contain the Duckybox theme. `duckybox-doctor` reports each one, including any other theme still baked into the initramfs — `spinner` and `bgrt` are the usual suspects. Plasma's own startup splash, a separate loader between the login screen and the desktop, is disabled by the KDE script.

## X11 versus Wayland

The installer makes the Plasma **X11** session the default, because Wayland breaks Peek and KWin ignores the compositing switch. Wayland stays available at the login screen; only the default changes. Pass `--keep-wayland` to leave the default alone.

How the default is set depends on the display manager, which is detected from the `display-manager.service` systemd alias rather than assumed. LightDM takes a `user-session` in `/etc/lightdm/lightdm.conf.d/99-duckybox.conf`. SDDM has no equivalent setting for interactive logins, so the installer seeds the session it remembers per user in `/var/lib/sddm/state.conf`.

## Why the theme applies at your next login

On Plasma, applying the theme during install is not enough on its own. The running session keeps its configuration in memory and writes it back out as the session ends, so a reboot right after installing can undo everything the installer wrote. That is why the desktop used to come up stock and needed a manual re-run.

The installer now leaves a one-shot autostart entry that re-applies the theme about ten seconds into your next login, from inside a real session, and then deletes itself. Plasma's panel restarts when that happens, so expect a brief flash. Its log is at `~/.cache/duckybox-first-login.log`, and `/opt/duckybox/apply-desktop.sh` re-applies at any time.

## Tools installed

**Flameshot**, **Peek**, **OpenVPN** (`openvpn-connect`), **linpeas** / **winpeas** (PEASS-ng into `/opt/duckybox/tools`), **Obsidian** (from GitHub Releases, per architecture) and **SysReptor** (Docker, at `/opt/sysreptor`, UI on `http://127.0.0.1:8000/`).

Parrot ships four virtual desktops by default; the installer reduces that to **one** on both MATE and KDE.

The VPN address is shown **in the top panel**, not as a floating corner overlay: a MATE Command applet running `vpnpanel.sh`, plus a system-tray indicator (`vpn-indicator.py`) on both desktops, and a Plasma plasmoid on KDE.

### Architecture detection

The installer detects the CPU before installing anything third-party and reports it as a family and a word size, for example `x86 64-bit (amd64)` or `arm 64-bit (arm64)`. `dpkg --print-architecture` decides, falling back to `uname -m` only when dpkg is absent, because a 64-bit kernel can run a 32-bit userland where every `.deb` is 32-bit.

Only the downloads that are not apt packages care:

| | x86_64 / amd64 | arm64 / aarch64 | 32-bit (i386, armhf) |
|---|---|---|---|
| Obsidian | `.deb` from GitHub Releases | arm64 tarball unpacked to `/opt/obsidian` | not published, `WARN` and skip |
| SysReptor | amd64 images | arm64 images, picked from the Docker manifest | no image, `WARN` and skip |

Obsidian publishes no arm64 `.deb`, so on arm64 the tarball is installed instead: it lands in `/opt/obsidian`, gets a symlink at `/usr/local/bin/obsidian` and a desktop entry, and its `chrome-sandbox` helper is made setuid root, which a `.deb` would do from its postinst and Electron refuses to start without.

The download URL is resolved from the recent release list rather than `/releases/latest`, since the newest Obsidian release is often a mobile-only build whose only asset is an `.apk`.

Everything else — apt packages, the GTK theme build, the boot chain, both desktops — is architecture independent and installs identically.

### SysReptor needs real Docker, not podman

Parrot ships `podman-docker`, which installs a podman shim at `/usr/bin/docker`. That makes `command -v docker` succeed while `docker` is not Docker, and SysReptor's own installer rejects it on the spot: its check is literally `docker --version | grep -q podman`.

By default the installer detects this and skips SysReptor with an explanation rather than removing packages you did not ask it to remove. Pass `--force-docker` to swap the shim for official Docker. Only the `podman-docker` package is removed, so the `podman` command keeps working; podman itself is never touched.

## Requirements

- Parrot OS Security or Home with **MATE** or **KDE Plasma**, behind **LightDM** or **SDDM**
- root via `sudo`
- Network for `apt`, the GTK theme build, Obsidian and Docker images
- **amd64 or arm64.** Both are fully supported; the installer detects which and picks the matching Obsidian download and SysReptor images. On a 32-bit userland everything themes normally, but Obsidian and SysReptor are skipped with a `WARN` because neither publishes 32-bit builds.

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
| `--session WHICH` | Desktop to theme: `auto` (default), `mate`, `kde`, `both`, `none` |
| `--keep-wayland` | Do not make Plasma X11 the default session |
| `--plymouth STYLE` | Boot splash: `minimal` (default), `full`, `none` |
| `--force-docker` | Replace Parrot's `podman-docker` shim with official Docker |
| `--skip-obsidian` | Do not download Obsidian |
| `--skip-sysreptor` | Do not install Docker or SysReptor |
| `--skip-plymouth` | Leave the boot splash alone |
| `--skip-grub` | Leave GRUB alone |
| `--skip-gtk` | Do not build the GTK theme or recolor icons |

## After install

1. **Reboot.** GRUB, the splash and the login screen should all be violet.
2. At the login screen, confirm the session is **Plasma (X11)**, now the default.
3. Log in. Colours, icons, wallpaper and the VPN overlay apply on their own.
4. Connect your OpenVPN profile so `tun0` gets an address; it shows up top-right and in the shell prompt.
5. SysReptor: `/opt/duckybox/sysreptor-start.sh` and `sysreptor-stop.sh`. Log out and back in once if Docker denies permission.

Plasma rewrites its configuration when a session ends, so edits made while a session is running can be undone. If something still looks stock, log out and back in, or re-apply:

```bash
/opt/duckybox/apply-desktop.sh          # auto-detects your session
/opt/duckybox/apply-desktop.sh kde      # or force one
```

The panel's menu button is the one piece that needs the panel to be running: it is set through Plasma's own scripting API, the same path the icon picker uses, because the widget ids are assigned when the panel is built and Parrot ships the launcher pointing at a Parrot-branded icon. Run the command above from inside the Plasma session, not over SSH.

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

Artwork is written out as JPEG and generated scenes as PNG. Encoding photographic artwork as PNG would losslessly preserve the source's own JPEG artifacts at roughly ten times the size, so the wallpaper set stays around 1 MB instead of 11 MB. The apply scripts accept either extension. Supply the artwork at the highest resolution you have: the 3840x2160 output is a straight downscale when the source is large enough, and only upscales when it is not.

The GTK theme is [Orchis](https://github.com/vinceliuice/Orchis-theme) with its purple palette overwritten by the Duckybox violet before `sassc` compiles it, installed as `Duckybox`. Icons are the packaged `Papirus-Dark` with folders relinked to their violet variants, the same mechanism `papirus-folders` uses.

## Layout

```
install.sh
assets/brand/duckybox-logo.png     # the one source of truth for branding
assets/duck.txt                    # braille duck, generated
assets/{plymouth,wallpapers,grub,greeter,icons}/
configs/{tmux,gtk,terminal,bash,plank,plymouth,grub,lightdm}/
configs/kde/                       # colour scheme, Konsole profile
configs/conky/                     # legacy (no longer used; VPN is in the panel)
configs/kde/plasmoids/             # Duckybox VPN panel plasmoid
scripts/generate-brand.sh          # all asset generation
scripts/install-gtk-theme.sh       # Orchis -> Duckybox violet, icon recolor
scripts/apply-mate-theme.sh        # per-user MATE settings
scripts/apply-kde-theme.sh         # per-user Plasma settings
scripts/duckybox-doctor.sh         # verification report
scripts/vpnpanel.sh vpnbash.sh     # VPN IP for panel and prompt
scripts/vpn-indicator.py           # top-panel tray indicator
scripts/openvpn-connect.sh         # OpenVPN profile helper
scripts/lib/common.sh              # shared helpers for the apply scripts
scripts/lib/pbm2braille.py         # PNG -> braille converter
```

## Notes

- Backups of replaced files use the `.duckybox.bak` suffix.
- Obsidian, SysReptor and the GTK theme build are best-effort: failures log a `WARN` and the install continues.
- If a machine was themed by the older Turfbox version, the installer removes its `~/.bashrc` block automatically.
- On very fast boots the splash may only flash briefly; that is Plymouth, not the theme.
- Parrot ships its own `GRUB_BACKGROUND`, and `grub-mkconfig` sources `/etc/default/grub.d/*.cfg` *after* `/etc/default/grub`, so a distro snippet can silently win. The installer disables the stock background and writes `/etc/default/grub.d/99-duckybox.cfg`, which is sourced last.
