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
      choice="$(
        printf '%s\n' \
          "Lock" \
          "Suspend" \
          "Logout" \
          "Reboot" \
          "Shutdown" |
          fuzzel \
            --dmenu \
            --prompt="Session > " \
            --width=30 \
            --lines=5
      )" || exit 0

      confirm() {
        printf '%s\n' "Yes" "No" |
          fuzzel \
            --dmenu \
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
