{ pkgs, ... }:

let
  nixGeneration = pkgs.writeShellApplication {
    name = "nix-generation";
    runtimeInputs = with pkgs; [ coreutils jq nix ];
    text = ''
      generation="$(readlink /nix/var/nix/profiles/system 2>/dev/null || true)"
      number="$(printf '%s' "$generation" | sed -n 's/.*system-\([0-9][0-9]*\)-.*/\1/p')"
      [ -n "$number" ] || number="?"
      jq -cn --arg text "Nix $number" --arg tooltip "Active NixOS generation $number" \
        '{text:$text,tooltip:$tooltip}'
    '';
  };
  systemGrimoire = pkgs.writeShellApplication {
    name = "system-grimoire";
    excludeShellChecks = [ "SC2016" ];
    runtimeInputs = with pkgs; [ fuzzel kitty nixos-rebuild systemd coreutils fish sway ];
    text = ''
      # The single-quoted arguments below are Fish programs passed verbatim to kitty.
      swaymsg focus_follows_mouse no >/dev/null
      restore_focus() {
        swaymsg focus_follows_mouse yes >/dev/null
      }
      trap restore_focus EXIT

      choice="$(printf '%s\n' "Rebuild" "Generations" "Rollback" "System info" "Services" "Logs" "Open config" |
        fuzzel --dmenu --keyboard-focus=exclusive --prompt="System > " --width=34 --lines=7)" || exit 0
      case "$choice" in
        Rebuild) exec kitty --title "NixOS rebuild" fish -lc 'rebuild; read -r' ;;
        Generations) exec kitty --title "NixOS generations" fish -lc 'nix-env --list-generations --profile /nix/var/nix/profiles/system; read -r' ;;
        Rollback) exec kitty --title "NixOS rollback" fish -lc 'read -P "Rollback to previous generation? [y/N] " answer; string match -qi y $answer; and sudo nixos-rebuild switch --rollback; read -r' ;;
        "System info") exec kitty --title "System info" fish -lc 'nixos-version; uname -sr; read -r' ;;
        Services) exec kitty --title "User services" fish -lc 'systemctl --user --no-pager --type=service; read -r' ;;
        Logs) exec kitty --title "Boot logs" fish -lc 'journalctl -b --no-pager -n 80; read -r' ;;
        "Open config") exec kitty --title "NixOS config" fish -lc 'cd ~/nixos-config; exec $EDITOR flake.nix' ;;
      esac
    '';
  };
in
{
  home.packages = [ nixGeneration systemGrimoire pkgs.libnotify ];
}
