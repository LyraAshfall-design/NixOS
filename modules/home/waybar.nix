{ pkgs, ... }:

{
  programs.waybar = {
    enable = true;

    systemd = {
      enable = true;
      targets = [ "sway-session.target" ];
    };

    settings = {
      mainBar = {
        layer = "top";
        position = "bottom";
        height = 34;
        spacing = 4;

        modules-left = [
          "sway/workspaces"
        ];

        modules-center = [
          "sway/window"
        ];

        modules-right = [
          "cpu"
          "memory"
          "network"
          "pulseaudio"
          "clock"
          "tray"
        ];

        "sway/workspaces" = {
          disable-scroll = true;
          all-outputs = false;
          format = "{name}";

          persistent-workspaces = {
            "1" = [ "DP-3" ];
            "2" = [ "DP-3" ];
            "3" = [ "DP-3" ];

            "4" = [ "DP-2" ];
            "5" = [ "DP-2" ];
            "6" = [ "DP-2" ];
          };
        };

        "sway/window" = {
          max-length = 70;
          separate-outputs = true;
        };

        cpu = {
          format = "CPU {usage}%";
          interval = 2;
        };

        memory = {
          format = "RAM {percentage}%";
          interval = 2;
        };

        network = {
          format-wifi = "{essid} {signalStrength}%";
          format-ethernet = "ETH";
          format-disconnected = "Offline";
          tooltip = true;
        };

        pulseaudio = {
          format = "VOL {volume}%";
          format-muted = "MUTED";
          scroll-step = 5;
          on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
        };

        clock = {
          format = "{:%a %b %d  %H:%M}";
          tooltip-format = "{:%A, %B %d, %Y}";
          timezone = "Etc/GMT+7";
        };

        tray = {
          spacing = 8;
        };
      };
    };

    style = ''
      * {
        font-family: sans-serif;
        font-size: 13px;
        min-height: 0;
      }

      window#waybar {
        background: rgba(30, 30, 46, 0.94);
        color: #cdd6f4;
      }

      #workspaces {
        margin: 4px 3px;
        padding: 0 3px;
        background: #313244;
        border-radius: 9px;
      }

      #workspaces button {
        min-width: 28px;
        padding: 0 7px;
        margin: 3px 2px;

        color: #7f849c;
        background: transparent;

        border: none;
        border-radius: 7px;
      }

      #workspaces button:hover {
        color: #cdd6f4;
        background: #45475a;
      }

      #workspaces button.focused {
        color: #1e1e2e;
        background: #89b4fa;
      }

      #workspaces button.visible {
        color: #cdd6f4;
      }

      #workspaces button.urgent {
        color: #1e1e2e;
        background: #f38ba8;
      }

      #window {
        margin: 4px 6px;
        padding: 0 12px;

        color: #bac2de;
        background: #313244;

        border-radius: 9px;
      }

      #cpu,
      #memory,
      #network,
      #pulseaudio,
      #clock,
      #tray {
        margin: 4px 3px;
        padding: 0 10px;

        color: #cdd6f4;
        background: #313244;

        border-radius: 9px;
      }

      #pulseaudio.muted {
        color: #7f849c;
      }

      #network.disconnected {
        color: #f38ba8;
      }

      #clock {
        margin-right: 4px;
        color: #89b4fa;
      }
    '';
  };
}
