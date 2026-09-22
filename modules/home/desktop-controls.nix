{ pkgs, lib, osConfig, ... }:

let
  bluetooth = osConfig.services.blueman.enable;
  desktopControls = pkgs.writeShellApplication {
    name = "desktop-controls";
    runtimeInputs = with pkgs; [ fuzzel pavucontrol networkmanagerapplet qt6Packages.qt6ct ]
      ++ lib.optional bluetooth pkgs.blueman;
    text = ''
      choice="$(printf '%s\n' "Audio" "Network" ${lib.optionalString bluetooth "Bluetooth"} "Qt appearance" "Notifications" "Session" |
        fuzzel --dmenu --prompt="Desktop > ")" || exit 0
      case "$choice" in
        Audio) exec pavucontrol ;;
        Network) exec nm-connection-editor ;;
        ${lib.optionalString bluetooth "Bluetooth) exec blueman-manager ;;"}
        "Qt appearance") exec qt6ct ;;
        Notifications) exec mako-center ;;
        Session) exec session-menu ;;
      esac
    '';
  };
in
{
  home.packages = [ desktopControls ];
}
