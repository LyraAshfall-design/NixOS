# Sway migration audit

Repository audit, 2026-09-22. Changes are configuration only; no rebuild switch,
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

Every remaining case-insensitive `noctalia|hyprland|hypr|uwsm` repository
reference falls into the intentional fallback groups below (including explanatory
comments and this audit). No Sway command still invokes either shell/compositor.

| Location | Classification and dependency |
| --- | --- |
| `flake.nix`, `flake.lock` | Intentional fallback: Noctalia input, locked dependency, module imports for both hosts. |
| `modules/desktop.nix` | Intentional fallback: Hyprland/UWSM enablement, Noctalia installation/service, Hyprland-only portal preference. Noctalia startup is conditional on `XDG_CURRENT_DESKTOP=Hyprland`; the current process was not stopped. |
| `home/corey.nix` | Intentional fallback: compositor enablement, Lua/xdph deployment, `hyprpicker`, Noctalia config deployment, and HYPRCURSOR settings in `uwsm/env-hyprland`. Portal routing mirrors the system configuration for both sessions. |
| `home/corey/hypr/**` | Intentional fallback: Lua modules, compositor commands/rules, Noctalia controls, UWSM application launching, share picker and portal screencopy configuration. The obsolete autostart module and its import were removed; UWSM handles environment import and session lifecycle. |
| `home/corey/noctalia/config.toml` | Intentional fallback: shell, lockscreen, greeter sync and remaining palette generation. Kitty and Qt template generation is disabled. |
| `modules/home/desktop-agents.nix` | Intentional fallback compatibility comments: shared Polkit agent, Sway-specific applet services and fallback XDG autostart. |
| `docs/sway-migration.md` | Audit documentation of fallback dependencies and deferred generated-file cleanup. |

Sway receives GTK default portals and WLR ScreenCast/Screenshot from the pinned
NixOS module. The Hyprland module installs its own portal; the redundant explicit
package entry was removed. Home Manager mirrors system routing so user-level
portal files cannot select a different backend for Sway.

Kitty now has basic static colors; qt6ct uses its packaged `darker.conf` palette.
Common browser, Qt and Electron settings are system session variables, available
to both desktops without sourcing UWSM files. Cursor settings remain owned by
Home Manager. The global TERM override was removed: Kitty sets its own TERM.
No NVIDIA settings were changed. Brightness shortcuts were removed from both
sessions: `/sys/class/backlight` is empty and the repository has no DDC/CI setup.
Sway's Noctalia restart hook was removed; stop/start/subscribe/cleanup is intact.
Emoji, weather, calendar and desktop utilities have independent implementations.

### Still needing removal in a later generated-file cleanup

Read-only inspection of the live home directory found GTK3/4 `gtk.css` imports
of `noctalia.css`, KDE `kdeglobals` naming Noctalia, and an Alacritty import of
`themes/noctalia.toml`. A generated btop theme also exists, but no btop config
selecting it was found. These are outside repository ownership and are retained
alongside the fallback template generators; no live files were overwritten.
The old Kitty and Qt generated files may remain on disk but are no longer read
by the managed Kitty/qt6ct configs. Retire the remaining generators and migrate
those live consumers deliberately during theming/fallback retirement.

## Validation and next interactive checks

`nix flake check` passed for both hosts after this cleanup. Evaluated portal
routing, installed backends, Noctalia's startup condition and Sway lifecycle
were inspected. `git diff --check` passed. No configuration was activated.

After a deliberate activation, reload Sway and test emoji selection/paste,
weather and calendar popups, audio/network/Bluetooth utilities and their window
rules. Open Kitty and qt6ct to verify independent colors. Test a browser file
picker and screen share. Shared session environment changes take full effect
on the next normal login; a Sway reload does not refresh the login environment.
On a later deliberate Hyprland login, verify Noctalia starts, fallback shortcuts
and portals work, and UWSM cleans up the session. On a fresh Sway login, verify
Noctalia does not start. Existing running Noctalia is not stopped by its new
startup condition. Do not infer runtime success from static validation.
