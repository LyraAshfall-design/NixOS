{ pkgs, ... }:

let
  sessionMenu = pkgs.writeShellApplication {
    name = "session-menu";

    runtimeInputs = with pkgs; [
      fuzzel
      sway
      swaylock
      systemd
    ];

    text = ''
      swaymsg focus_follows_mouse no >/dev/null
      restore_focus() {
        swaymsg focus_follows_mouse yes >/dev/null
      }
      trap restore_focus EXIT

      choice="$(
        printf '%s\n' \
          "Lock" \
          "Suspend" \
          "Logout" \
          "Reboot" \
          "Shutdown" |
          fuzzel \
            --dmenu \
            --keyboard-focus=exclusive \
            --prompt="Session > " \
            --width=30 \
            --lines=5
      )" || exit 0

      confirm() {
        printf '%s\n' "Yes" "No" |
          fuzzel \
            --dmenu \
            --keyboard-focus=exclusive \
            --prompt="$1 > " \
            --width=24 \
            --lines=2
      }

      case "$choice" in
        "Lock")
          swaylock -f
          ;;

        "Suspend")
          systemctl suspend
          ;;

        "Logout")
          swaymsg exit
          ;;

        "Reboot")
          if [ "$(confirm "Reboot")" = "Yes" ]; then
            systemctl reboot
          fi
          ;;

        "Shutdown")
          if [ "$(confirm "Shutdown")" = "Yes" ]; then
            systemctl poweroff
          fi
          ;;
      esac
    '';
  };
in
{
  home.packages = [
    sessionMenu
  ];
}
