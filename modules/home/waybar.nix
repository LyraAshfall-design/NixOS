{ pkgs, desktopTheme, ... }:

let
  catMark = ../../assets/theme/cat-mark.svg;
  catMarkHover = pkgs.writeText "cat-mark-hover.svg"
    (builtins.replaceStrings [ "#E8DCCB" ] [ "#D19A66" ] (builtins.readFile catMark));
  catMarkActive = pkgs.writeText "cat-mark-active.svg"
    (builtins.replaceStrings [ "#E8DCCB" ] [ "#FFFFFF" ] (builtins.readFile catMark));
  nowPlaying = pkgs.writeShellApplication {
    name = "waybar-now-playing";
    runtimeInputs = with pkgs; [ jq playerctl ];
    text = ''
      player=""
      status=""
      paused_player=""

      while IFS= read -r candidate; do
        candidate_status="$(playerctl -p "$candidate" status 2>/dev/null || true)"
        case "$candidate_status" in
          Playing)
            player="$candidate"
            status="$candidate_status"
            break
            ;;
          Paused)
            [ -n "$paused_player" ] || paused_player="$candidate"
            ;;
        esac
      done < <(playerctl -l 2>/dev/null || true)

      if [ -z "$player" ] && [ -n "$paused_player" ]; then
        player="$paused_player"
        status="Paused"
      fi

      [ -n "$player" ] || exit 0

      artist="$(playerctl -p "$player" metadata artist 2>/dev/null || true)"
      title="$(playerctl -p "$player" metadata title 2>/dev/null || true)"
      [ -n "$artist" ] || artist="Unknown artist"
      [ -n "$title" ] || title="Unknown track"

      jq -cn \
        --arg text "♪ $artist — $title" \
        --arg status "''${status,,}" \
        --arg tooltip "$artist — $title" \
        '{text:$text,class:$status,tooltip:$tooltip}'
    '';
  };
in

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
        position = "top";
        height = 20;
        spacing = 2;

        modules-left = [
          "sway/workspaces"
          "custom/now-playing"
        ];

        modules-center = [
          "sway/window"
        ];

        modules-right = [
          "cpu"
          "memory"
          "network"
          "pulseaudio"
          "custom/weather"
          "clock"
          "custom/nix-generation"
          "custom/notifications"
          "tray"
          "custom/session"
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
          max-length = 55;
          separate-outputs = true;
        };

        "custom/now-playing" = {
          exec = "${nowPlaying}/bin/waybar-now-playing";
          return-type = "json";
          format = "{}";
          max-length = 42;
          interval = 2;
          hide-empty-text = true;
          on-click = "${pkgs.playerctl}/bin/playerctl play-pause";
          on-scroll-up = "${pkgs.playerctl}/bin/playerctl previous";
          on-scroll-down = "${pkgs.playerctl}/bin/playerctl next";
          tooltip = true;
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
          on-click = "${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
          tooltip = true;
        };

        pulseaudio = {
          format = "VOL {volume}%";
          format-muted = "MUTED";
          scroll-step = 5;
          on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
        };

        "custom/weather" = {
          exec = "${pkgs.wttrbar}/bin/wttrbar";
          return-type = "json";
          format = "{}";
          interval = 3600;
          on-click = "weather-popup";
          exec-on-event = false;
          tooltip = true;
        };

        clock = {
          format = "{:%a %b %d  %H:%M}";
          tooltip-format = "{:%A, %B %d, %Y}";
          timezone = "Etc/GMT+7";
          on-click = "calendar-popup";
        };

        tray = {
          icon-size = 14;
          spacing = 4;
        };

        "custom/session" = {
          format = " ";
          tooltip = false;
          on-click = "session-menu";
        };

        # Static bell: history is read only when the existing center is opened.
        "custom/notifications" = {
          format = "🔔︎";
          tooltip-format = "Notifications";
          on-click = "mako-center";
        };

        "custom/nix-generation" = {
          exec = "nix-generation";
          interval = 300;
          return-type = "json";
          format = "{}";
          on-click = "system-grimoire";
          tooltip = true;
        };
      };
    };

    style = ''
      * {
        font-family: sans-serif;
        font-size: 11px;
        min-height: 0;
      }

      window#waybar {
        background: rgba(${desktopTheme.rgb "base"}, 0.94);
        color: ${desktopTheme.hex "text"};
      }

      #workspaces {
        margin: 1px 2px;
        padding: 0 2px;
        background: ${desktopTheme.hex "surface"};
        border-radius: 5px;
      }

      #workspaces button {
        min-width: 18px;
        padding: 0 4px;
        margin: 1px;

        color: ${desktopTheme.hex "muted"};
        background: transparent;

        border: none;
        border-radius: 4px;
      }

      #workspaces button:hover {
        color: ${desktopTheme.hex "text"};
        background: ${desktopTheme.hex "overlay"};
      }

      #workspaces button.focused {
        color: ${desktopTheme.hex "base"};
        background: ${desktopTheme.hex "accent"};
      }

      #workspaces button.visible:not(.focused) {
        color: ${desktopTheme.hex "text"};
      }

      #workspaces button.urgent {
        color: ${desktopTheme.hex "base"};
        background: ${desktopTheme.hex "urgent"};
      }

      #window {
        margin: 1px 3px;
        padding: 0 6px;

        color: ${desktopTheme.hex "muted"};
        background: ${desktopTheme.hex "surface"};

        border-radius: 5px;
      }

      #cpu,
      #memory,
      #network,
      #pulseaudio,
      #custom-weather,
      #custom-now-playing,
      #clock,
      #custom-notifications,
      #tray,
      #custom-session {
        margin: 1px 2px;
        padding: 0 6px;

        color: ${desktopTheme.hex "text"};
        background: ${desktopTheme.hex "surface"};

        border-radius: 5px;
      }

      #pulseaudio.muted {
        color: ${desktopTheme.hex "muted"};
      }

      #network {
        color: ${desktopTheme.hex "sage"};
      }

      #network.disconnected {
        color: ${desktopTheme.hex "urgent"};
      }

      #clock {
        margin-right: 2px;
        color: ${desktopTheme.hex "accent"};
      }

      #custom-now-playing {
        min-width: 0;
        margin-right: 3px;
        color: ${desktopTheme.hex "text"};
      }

      #custom-now-playing.paused {
        color: ${desktopTheme.hex "muted"};
      }

      #custom-session {
        min-width: 18px;
        color: ${desktopTheme.hex "text"};
        background-image: url("${catMark}");
        background-repeat: no-repeat;
        background-position: center;
        background-size: 16px 16px;
      }

      #custom-notifications {
        font-family: "Unifont Upper", sans-serif;
        color: ${desktopTheme.hex "text"};
      }

      #custom-notifications:hover {
        color: ${desktopTheme.hex "accent"};
        background: ${desktopTheme.hex "overlay"};
      }

      #custom-session:hover {
        color: ${desktopTheme.hex "accent"};
        background-color: ${desktopTheme.hex "overlay"};
        background-image: url("${catMarkHover}");
      }

      #custom-session:active {
        color: #FFFFFF;
        background-image: url("${catMarkActive}");
      }

      #custom-nix-generation {
        color: ${desktopTheme.hex "muted"};
      }

      #custom-nix-generation:hover {
        color: ${desktopTheme.hex "accent"};
        background: ${desktopTheme.hex "overlay"};
      }
    '';
  };
}
