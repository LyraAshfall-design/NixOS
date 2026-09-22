{ pkgs, lib, osConfig, desktopTheme, ... }:

let
  bluetooth = osConfig.services.blueman.enable;
  emojiPicker = pkgs.writeShellApplication {
    name = "emoji-picker";
    runtimeInputs = with pkgs; [ bemoji fuzzel wl-clipboard curl coreutils gnugrep gnused ];
    text = ''
      export BEMOJI_PICKER_CMD="${pkgs.fuzzel}/bin/fuzzel --dmenu --prompt='Emoji > '"
      exec bemoji -c
    '';
  };
  weatherReport = pkgs.writeShellApplication {
    name = "weather-report";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      if ! curl --fail --silent --show-error --connect-timeout 10 --max-time 30 \
        'https://wttr.in/?m&T'; then
        printf '\nWeather unavailable. Check your connection and try again.\n'
      fi
      printf '\nPress Enter to close.\n'
      read -r _ || true
    '';
  };
  weatherPopup = pkgs.writeShellApplication {
    name = "weather-popup";
    text = ''
      exec ${pkgs.kitty}/bin/kitty --class weather-popup --title Weather \
        -o background_opacity=1 -o initial_window_width=100c -o initial_window_height=32c \
        -o foreground='${desktopTheme.hex "text"}' -o background='${desktopTheme.hex "base"}' \
        ${weatherReport}/bin/weather-report
    '';
  };
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
  home.packages = [ desktopControls emojiPicker weatherPopup pkgs.gsimplecal ];

  xdg.configFile."gsimplecal/config".text = ''
    show_calendar = 1
    show_timezones = 0
    mark_today = 1
    close_on_unfocus = 1
    mainwindow_decorated = 0
  '';

  # Match native Wayland app IDs and XWayland classes separately.
  wayland.windowManager.sway.config.window.commands =
    let
      utilities = "(?i)^(pavucontrol|org.pulseaudio.pavucontrol|nm-connection-editor|blueman-manager|gsimplecal|weather-popup)$";
      command = "floating enable, move position center, opacity 0.92";
    in [
      { criteria.app_id = utilities; inherit command; }
      { criteria.class = utilities; inherit command; }
    ];
}
