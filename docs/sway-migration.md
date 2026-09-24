# Sway migration audit

Repository audit, 2026-09-22. Changes are configuration only; no rebuild switch,
service restart, compositor reload, logout, suspend, or reboot was performed.

## Structure

`flake.nix` composes the desktop from `configuration.nix`, its host module,
Home Manager, Noctalia, and the official SilentSDDM module. The VM imports
`modules/base.nix` and `hosts/vm/default.nix` directly, using XFCE without Home
Manager or Noctalia. Shared system desktop services live in
`modules/desktop.nix`; Sway system integration is in `modules/desktop/sway.nix`.
`home/corey.nix` now imports `modules/home/default.nix`, which aggregates the
small desktop Home Manager modules. Personal identity, applications, and the
retained Hyprland configuration remain in `home/corey.nix`.

## Replacements in this change

- `desktop-agents.nix`: standalone GNOME Polkit agent follows
  `graphical-session.target`, serving both desktops. Noctalia's built-in Polkit
  agent is disabled to avoid duplicate registration. NetworkManager's applet
  provides network secrets/authentication and an indicator in Waybar's tray;
  its service starts/stops with Sway. Blueman's applet/pairing agent also follows
  Sway, only on hosts where the system Blueman service is enabled (desktop).
  Per-user XDG autostart entries exclude Sway to avoid starting the applets twice,
  while preserving autostart in Hyprland.
- `desktop-controls.nix`: Super+Z and Super+X open one Fuzzel menu for audio,
  network connections, Bluetooth (desktop only), Qt appearance, notifications,
  and session actions. This replaces the practical controls, not Noctalia's
  shell-specific settings or palette generator.
- `window-picker.nix`: Super+Tab selects native Wayland and XWayland windows by
  Sway container ID. Cancellation and empty trees exit without changing focus.
- Waybar's network indicator opens `nm-connection-editor` on click.
- Existing monitor layout, workspace assignments, refresh rates, NVIDIA power
  settings, and Sway lifecycle commands are unchanged. Existing unrelated
  shortcuts and desktop tools are unchanged.

## Remaining references and removal prerequisites

Every remaining case-insensitive `noctalia|hyprland|hypr|uwsm` repository
reference falls into the intentional fallback groups below (including explanatory
comments and this audit). No Sway command still invokes either shell/compositor.

| Location | Classification and dependency |
| --- | --- |
| `flake.nix`, `flake.lock` | Intentional fallback: Noctalia input, locked dependency, module imports for the desktop host only. |
| `modules/desktop.nix` | Intentional fallback: Hyprland/UWSM enablement, Noctalia installation/service, Hyprland-only portal preference. Noctalia startup is conditional on `XDG_CURRENT_DESKTOP=Hyprland`; the current process was not stopped. |
| `home/corey.nix` | Intentional fallback: compositor enablement, Lua/xdph deployment, `hyprpicker`, Noctalia config deployment, and HYPRCURSOR settings in `uwsm/env-hyprland`. Portal routing mirrors the system configuration for both sessions. |
| `home/corey/hypr/**` | Intentional fallback: Lua modules, compositor commands/rules, Noctalia controls, UWSM application launching, share picker and portal screencopy configuration. The obsolete autostart module and its import were removed; UWSM handles environment import and session lifecycle. |
| `home/corey/noctalia/config.toml` | Intentional fallback: shell, lockscreen, greeter sync and internal shell palette. All shared application template generators are disabled; shared themes belong to Home Manager. |
| `modules/home/desktop-agents.nix` | Intentional fallback compatibility comments: shared Polkit agent, Sway-specific applet services and fallback XDG autostart. |
| `docs/sway-migration.md` | Audit documentation of fallback dependencies and deferred generated-file cleanup. |

Sway receives GTK default portals and WLR ScreenCast/Screenshot from the pinned
NixOS module. The Hyprland module installs its own portal; the redundant explicit
package entry was removed. Home Manager mirrors system routing so user-level
portal files cannot select a different backend for Sway.

`modules/home/theme.nix` owns a shared static warm cat-cafe palette for GTK3/4,
Kitty, qt6ct and KDE colors, plus Papirus-Dark icons with muted brown folders and
the existing Bibata cursor. GTK, Qt/KDE and Fuzzel share the icon theme selection;
Mako searches its package directly. Folder colors are selected declaratively at
build time, while application logos retain their original colors.
It is imported only through `modules/home/default.nix`. `home/corey.nix` imports
only that aggregator and Corey-specific `mogledger.nix`; no duplicate desktop
imports remain. Sway borders, Waybar, Fuzzel, Mako, swaylock, SwayOSD and the
weather popup consume the same palette; calendar and utilities inherit GTK.
Kitty includes all 16 ANSI colors. Waybar is a compact 25px top bar with the
existing module order followed by a far-right button invoking `session-menu`.
Common browser, Qt and Electron settings are system session variables, available
to both desktops without sourcing UWSM files. Cursor settings remain owned by
Home Manager. The global TERM override was removed: Kitty sets its own TERM.
No NVIDIA settings were changed. Brightness shortcuts were removed from both
sessions: `/sys/class/backlight` is empty and the repository has no DDC/CI setup.
Sway's Noctalia restart hook was removed; stop/start/subscribe/cleanup is intact.
Emoji, weather, calendar and desktop utilities have independent implementations.

### Live residue and ownership (rechecked during polish)

| Live path | Ownership / classification |
| --- | --- |
| `~/.config/kitty/kitty.conf`, `~/.config/qt6ct/qt6ct.conf` | Already Home Manager symlinks; no active Noctalia imports. |
| `~/.config/gtk-{3,4}.0/gtk.css` | Now Home Manager symlinks; declarative warm CSS with no Noctalia import. |
| `~/.config/kdeglobals` | Now a Home Manager symlink; declarative KDE colors with no Noctalia selection. |
| `~/.config/alacritty/alacritty.toml` | Now a Home Manager symlink to an empty config. Alacritty is not installed/launched by this repo. |
| `~/.config/gtk-{3,4}.0/noctalia.css` | Stale unmanaged generated targets; no managed consumer imports them. |
| `~/.config/alacritty/themes/noctalia.toml` | Stale unmanaged generated target; no managed consumer imports it. |
| `~/.local/share/color-schemes/noctalia.colors` | Stale unmanaged KDE scheme; no managed consumer selects it. |
| `~/.config/btop/themes/noctalia.theme` | Unmanaged dormant theme; no btop config selects it. Generator disabled. |

All these files were inspected read-only. No live files were edited, deleted,
archived or copied during this pass. The previously unmanaged consumers were
already migrated before this pass; the old activation collision advice no longer
applies. Remaining generated targets can be removed during a later cleanup.
Noctalia's disabled-template undo hooks may also remove those unused targets on
its next start; they leave the new import-free consumer contents unchanged.

All repository legacy references are intentional fallback or audit comments,
as classified in the table above. Live files in this table are stale/unmanaged
residue. There is no remaining generated-theme dependency in the built Sway
consumer configs; future removal is limited to residue and eventual fallback
retirement. No fallback retirement is part of this change.

## Desktop polish

- `modules/home/theme.nix` remains the palette owner. Its read-only color option
  also supplies the system greeter; `terminal-theme.nix` uses the same palette for
  btop, Yazi, Fish syntax and a compact prompt, and Git diff/status/branch colors.
  Kitty retains its complete warm ANSI palette. Neither bat nor fzf is installed,
  so neither was added just for theming. Existing Fish helpers remain intact.
- `file-manager.nix` keeps Yazi and declares a Sway-specific MIME default for
  directories. The unmanaged general `mimeapps.list` (Discord association) stays
  untouched. Super+E opens Thunar. The system module supplies archive/volume
  plugins, File Roller, GVfs and Tumbler without enabling the XFCE desktop.
- `modules/desktop/sddm.nix` uses the pinned
  [official SilentSDDM module](https://github.com/uiriansan/SilentSDDM/wiki).
  A bundled, store-readable café scene keeps the greeter independent of home
  permissions. Warm colors, restrained controls, no blur and no animations are
  configured. Sway is the default; Sway, Hyprland and Hyprland/UWSM sessions remain
  available. Authentication and auto-login settings are unchanged. Noctalia's
  separate greeter-sync setting is retained for fallback/future removal; it does
  not configure SDDM.

### Wallpaper filtering

Wallhaven now runs first with varied warm keywords, supported warm/dark API
color filters, landscape/minimum-resolution metadata and SFW purity. A small
preview is scored before downloading a full image. Full-image resolution,
orientation, SHA1 history, final color validation and symlink/application flow
remain in place. Reddit remains supported, with fewer cold-focused sources.

The 32px sample score rewards darkness, warm pixels, palette proximity and muted
saturation; it penalizes cold hues, neon saturation and excessive brightness.
Rejected previews/full images report the score breakdown. Defaults near the top
of the script are tunable through environment variables: `THEME_MIN_SCORE=60`,
`THEME_SAMPLE_SIZE=32`, `THEME_DEBUG=0`, `MAX_THEME_ATTEMPTS=40`,
`MAX_SOURCE_ATTEMPTS=4`, `MAX_REDDIT_ATTEMPTS=6`, `MAX_SOURCE_REQUESTS=32`,
`CURL_CONNECT_TIMEOUT=5`, and `CURL_MAX_TIME=25`. The request/time budgets bound
search duration; exhausting them exits cleanly without replacing the wallpaper.

### Resource audit

- One SwayOSD process used about 69 MiB RSS / 47 MiB PSS at inspection. Shared
  mappings contribute to RSS; a single snapshot cannot establish a leak. Current
  logs show CSS loading and an optional libinput-backend wait, not repeated
  current-session crashes. Keep it; compare PSS over time while exercising volume.
- Blueman's applet launches `blueman-tray` as its tray helper; those names do not
  indicate duplicate startup. Existing Sway-only service/fallback autostart
  separation remains. The applet was inactive at inspection; logs contain a
  PulseAudio active-profile callback error. Manually test Bluetooth tray/pairing
  after a fresh login before changing this integration.
- One nm-applet process provides tray and network secret-agent behavior; retain
  it. Xwayland remains enabled for application compatibility. No desktop agents
  were removed or restarted.

## Validation and next interactive checks

`nix flake check` passed for both hosts. New modules are Git-visible. Generated
Home Manager files were built and checked: GTK3/4, Kitty, qt6ct including its
palette, KDE and Alacritty have no Noctalia references. Evaluated portal
routing, installed backends, Noctalia's startup condition and Sway lifecycle
were inspected. The SilentSDDM theme and Home Manager files also built. Fish
syntax, Bash syntax, ShellCheck, and `git diff --check` passed. Offline wallpaper
tests covered preview rejection before full download, duplicate/history handling,
final-score rejection, Reddit fallback, empty results, missing previews, metadata
rejection, network failure and invalid tunables. Evaluated Sway settings match the
pre-polish snapshot except Super+E; portal routing, suspend settings, NVIDIA module
parameters and Sway systemd lifecycle match. No configuration was activated.

After a deliberate activation, reload Sway and test emoji selection/paste,
weather and calendar popups, audio/network/Bluetooth utilities and their window
rules. Open Kitty and qt6ct to verify independent colors. Test a browser file
picker and screen share. Shared session environment changes take full effect
on the next normal login; a Sway reload does not refresh the login environment.
On a later deliberate Hyprland login, verify Noctalia starts, fallback shortcuts
and portals work, and UWSM cleans up the session. On a fresh Sway login, verify
Noctalia does not start. Existing running Noctalia is not stopped by its new
startup condition. Do not infer runtime success from static validation.

For this polish pass also check Waybar clipping on both displays, all existing
click actions and the far-right session menu (cancel destructive actions), Thunar
archive/thumbnail/removable-media behavior, `xdg-mime query default inode/directory`
returning `thunar.desktop` in Sway, and btop/Yazi/Fish/Git colors in a fresh Kitty.
Preview the greeter before activation with:

```sh
nix run ".#nixosConfigurations.nixos-desktop.config.programs.silentSDDM.package'.test"
```

The preview cannot verify real authentication or session startup. Test both
desktop choices during a planned login. Use `THEME_DEBUG=1 ~/.local/bin/wallpaper-next`
to tune real-image filtering after activation; it deliberately changes wallpaper
on success. The static bundled greeter image does not follow desktop rotation.
