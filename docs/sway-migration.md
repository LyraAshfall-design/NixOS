# Sway migration audit

Repository audit, 2026-09-21. Changes are configuration only; no rebuild switch,
service restart, compositor reload, logout, suspend, or reboot was performed.

## Structure

`flake.nix` builds VM and desktop hosts from `configuration.nix`, host modules,
Home Manager, and the Noctalia module. Shared system desktop services live in
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

| Location | Dependency / next step |
| --- | --- |
| `modules/home/sway.nix` | Super+period still uses Noctalia emoji search; Super+Alt+W still uses its weather panel. Choose replacements before removal. |
| `modules/home/sway.nix` | Brightness keys still use Noctalia. This machine exposes no `/sys/class/backlight` devices, so blindly replacing these with brightnessctl would not work. Verify external-monitor DDC/CI support, permissions, and desired output selection before replacing them. |
| `modules/home/sway.nix` | The existing session startup still restarts Noctalia. Remove that command only after its remaining functions have replacements. Preserve the surrounding stop/start/subscribe/cleanup lifecycle. |
| `home/corey.nix` | Kitty includes `themes/noctalia.conf`; qt6ct uses `noctalia.colors`. Replace these with independently managed themes before removing generated files. |
| `home/corey/noctalia/config.toml` | Wallpaper-derived templates also cover GTK3/4, btop, KDE colors, Qt, and Alacritty. Audit generated files in the live home directory before moving ownership to Home Manager; do not overwrite them blindly. Greeter synchronization and Noctalia lockscreen configuration also remain. |
| `home/corey.nix` | Hyprland Home Manager enablement, Lua deployment, `xdph.conf`, and Hyprland-specific portal preference remain intentionally. `hyprpicker` is installed and used by the Hyprland Super+P shortcut; Sway has no corresponding color-picker binding yet. |
| `home/corey.nix` | `uwsm/env` contains common browser, terminal, Qt, Electron, and Xcursor settings alongside HYPRCURSOR variables. Preserve needed common settings in Sway's environment before removing UWSM configuration. Sway currently does not source this file. |
| `home/corey/hypr/` | Retained Lua configuration, Noctalia shortcuts/window rules, Hyprland share-picker rule, monitor recovery, autostart targets, and portal screencopy settings are fallback-session configuration. Remove together only when retiring that session. |
| `modules/desktop.nix` | Hyprland/UWSM, Noctalia service, and Hyprland portal remain enabled. Keep shared keyring, PipeWire, rtkit, SDDM, and GTK portal services when later removing those blocks. |
| `flake.nix`, `flake.lock` | Noctalia input and module imports for both hosts remain. Remove these last, with the lock entry updated through Nix. |

Sway already receives WLR ScreenCast/Screenshot and GTK default portal routing
from the pinned NixOS Sway module. No replacement portal configuration is needed.
GNOME Keyring, NetworkManager, and desktop Bluetooth already have system-level
support independent of Noctalia. Keep those services.

## Validation and next interactive checks

`nix flake check path:/home/corey/nixos-config` passed for both hosts. The explicit
path includes newly added modules before they are tracked by Git; add the new
modules when committing so normal Git-backed flake commands include them.
Both host variants of desktop-controls and sway-window-picker were built,
including writeShellApplication's shell syntax and ShellCheck checks.
Evaluated agent units and portal routing were inspected.

After a deliberate activation, verify Polkit prompts, NetworkManager secrets and
tray menus, Bluetooth pairing, window selection (including scratchpad), and portal
screen sharing. Graphical/runtime behavior was not exercised during this unattended
change. Validate session cleanup and NVIDIA resume later with the user present;
no power-state testing was performed here.
