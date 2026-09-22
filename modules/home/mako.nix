{ pkgs, ... }:

let
  makoCenter = pkgs.writeShellApplication {
    name = "mako-center";

    runtimeInputs = with pkgs; [
      mako
      jq
      fuzzel
    ];

    text = ''
      active="$(makoctl list -j)"
      history="$(makoctl history -j)"

      entries="$(
        jq -rn \
          --argjson active "$active" \
          --argjson history "$history" '
            [
              (
                $active[]? |
                "● " +
                (.app_name // "Notification") +
                ": " +
                (.summary // "") +
                (
                  if (.body // "") != ""
                  then " — " + (.body | gsub("\n"; " "))
                  else ""
                  end
                )
              ),
              (
                $history[]? |
                "○ " +
                (.app_name // "Notification") +
                ": " +
                (.summary // "") +
                (
                  if (.body // "") != ""
                  then " — " + (.body | gsub("\n"; " "))
                  else ""
                  end
                )
              )
            ]
            | .[]
          '
      )"

      if [ -z "$entries" ]; then
        entries="No notifications"
      fi

      printf '%s\n' "$entries" |
        fuzzel \
          --dmenu \
          --prompt="Notifications > " \
          --width=70 \
          --lines=12 \
          >/dev/null
    '';
  };

in {
  services.mako = {
    enable = true;

    settings = {
      anchor = "top-right";
      layer = "overlay";

      width = 360;
      height = 120;
      margin = "10";
      padding = "12";

      font = "sans-serif 11";

      background-color = "#1e1e2ef2";
      text-color = "#cdd6f4ff";
      border-color = "#89b4faff";

      border-size = 2;
      border-radius = 10;

      icons = true;
      max-icon-size = 48;

      markup = true;
      default-timeout = 5000;

      format = "<b>%s</b>\\n%b";
    };
  };

  home.packages = [
    makoCenter
  ];

  # Home Manager configures Mako and its D-Bus activation, but does not
  # automatically bind the daemon to the Sway session. Do that explicitly.
  systemd.user.services.mako = {
    Unit = {
      Description = "Mako notification daemon";
      After = [ "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };

    Service = {
      ExecStart = "${pkgs.mako}/bin/mako";
      Restart = "on-failure";
    };

    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };
}
