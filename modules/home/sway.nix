{ pkgs, osConfig, ... }:

{
  wayland.windowManager.sway = {
    enable = true;
    package = null;

    # Tie user services to the actual lifetime of the Sway session.
    #
    # The initial stop handles a stale sway-session.target left behind
    # by the previous compositor session.
    systemd = {
      enable = true;

      extraCommands = [
        "systemctl --user stop sway-session.target || true"
        "systemctl --user reset-failed"
        "systemctl --user start sway-session.target"

        # Remain alive until this Sway compositor exits.
        "swaymsg -mt subscribe '[]' || true"

        # Stop services belonging to this Sway session.
        "systemctl --user stop sway-session.target"
      ];
    };

    config = {
      modifier = "Mod4";
      terminal = "${pkgs.kitty}/bin/kitty";

      bars = [ ];

      # -----------------------------------------------------------------------
      # Displays
      # -----------------------------------------------------------------------

      output = {
        "DP-3" = {
          mode = "1920x1080@179.998Hz";
          position = "0 0";
        };

        "DP-2" = {
          mode = "1920x1080@179.998Hz";
          position = "1920 0";
        };
      };

      # Three workspaces per monitor.
      workspaceOutputAssign = [
        { workspace = "1"; output = "DP-3"; }
        { workspace = "2"; output = "DP-3"; }
        { workspace = "3"; output = "DP-3"; }

        { workspace = "4"; output = "DP-2"; }
        { workspace = "5"; output = "DP-2"; }
        { workspace = "6"; output = "DP-2"; }
      ];

      # -----------------------------------------------------------------------
      # Appearance / layout
      # -----------------------------------------------------------------------

      gaps = {
        inner = 3;
        outer = 1;
        smartGaps = false;
      };

      window = {
        titlebar = false;
        border = 1;
      };

      floating = {
        modifier = "Mod4";
        titlebar = false;
        border = 1;
      };

      # -----------------------------------------------------------------------
      # Keybindings
      # -----------------------------------------------------------------------

      keybindings = {
        # Applications
        "Mod4+Return" =
          "exec ${pkgs.kitty}/bin/kitty";

        "Mod4+w" =
          "exec ${pkgs.firefox}/bin/firefox";

        "Mod4+e" =
          "exec ${osConfig.programs.thunar.finalPackage}/bin/thunar";

        "Mod4+t" =
          "exec ${pkgs.gnome-text-editor}/bin/gnome-text-editor --new-window";

        "Mod4+c" =
          "exec ${pkgs.gnome-calculator}/bin/gnome-calculator";

        "XF86Calculator" =
          "exec ${pkgs.gnome-calculator}/bin/gnome-calculator";

        "Ctrl+Shift+Escape" =
          "exec ${pkgs.kitty}/bin/kitty -e ${pkgs.btop}/bin/btop";

        # Steam + Vesktop
        "Mod4+g" =
          "exec steam & ${pkgs.vesktop}/bin/vesktop";

        # ---------------------------------------------------------------------
        # Window management
        # ---------------------------------------------------------------------

        "Mod4+q" =
          "kill";

        "Mod4+Mod1+space" =
          "floating toggle";

        "Mod4+f" =
          "fullscreen toggle";

        "Mod4+j" =
          "layout toggle split";

        "Mod1+Tab" =
          "focus next";

        # Focus windows
        "Mod4+Left" =
          "focus left";

        "Mod4+Right" =
          "focus right";

        "Mod4+Up" =
          "focus up";

        "Mod4+Down" =
          "focus down";

        # Move windows
        "Mod4+Shift+Left" =
          "move left";

        "Mod4+Shift+Right" =
          "move right";

        "Mod4+Shift+Up" =
          "move up";

        "Mod4+Shift+Down" =
          "move down";

        # ---------------------------------------------------------------------
        # Workspaces
        # ---------------------------------------------------------------------

        "Mod4+1" =
          "workspace number 1";

        "Mod4+2" =
          "workspace number 2";

        "Mod4+3" =
          "workspace number 3";

        "Mod4+4" =
          "workspace number 4";

        "Mod4+5" =
          "workspace number 5";

        "Mod4+6" =
          "workspace number 6";

        "Mod4+Shift+1" =
          "move container to workspace number 1";

        "Mod4+Shift+2" =
          "move container to workspace number 2";

        "Mod4+Shift+3" =
          "move container to workspace number 3";

        "Mod4+Shift+4" =
          "move container to workspace number 4";

        "Mod4+Shift+5" =
          "move container to workspace number 5";

        "Mod4+Shift+6" =
          "move container to workspace number 6";

        # ---------------------------------------------------------------------
        # Scratchpad
        # ---------------------------------------------------------------------

        "Mod4+Shift+s" =
          "move scratchpad";

        "Mod4+s" =
          "scratchpad show";
        # ---------------------------------------------------------------------
        # Fuzzel
        # ---------------------------------------------------------------------

        "Mod4+space" =
          "exec ${pkgs.fuzzel}/bin/fuzzel";

        # ---------------------------------------------------------------------
        # Desktop utilities
        # ---------------------------------------------------------------------

        "Mod4+z" =
          "exec desktop-controls";

        "Mod4+x" =
          "exec desktop-controls";

        "Mod4+period" =
          "exec emoji-picker";

        "Mod4+l" =
          "exec ${pkgs.swaylock}/bin/swaylock -f";

        "Mod4+Mod1+c" =
          "exec session-menu";

        "Mod4+Tab" =
          "exec sway-window-picker";

        "Mod4+v" =
          "exec clipboard-picker";

        "Mod4+Shift+w" =
          "exec ~/.local/bin/wallpaper-next";

        "Mod4+Mod1+w" =
          "exec weather-popup";

        # ---------------------------------------------------------------------
        # Mako notification center
        # ---------------------------------------------------------------------

        "Mod4+a" =
          "exec mako-center";

        # ---------------------------------------------------------------------
        # Screenshots
        # ---------------------------------------------------------------------

        "Print" =
          "exec screenshot-region";

        "Mod4+Print" =
          "exec screenshot-fullscreen";

        # ---------------------------------------------------------------------
        # Audio
        # ---------------------------------------------------------------------

        "XF86AudioRaiseVolume" =
          "exec swayosd-client --output-volume raise";

        "XF86AudioLowerVolume" =
          "exec swayosd-client --output-volume lower";

        "XF86AudioMute" =
          "exec swayosd-client --output-volume mute-toggle";

        "XF86AudioMicMute" =
          "exec swayosd-client --input-volume mute-toggle";


        # ---------------------------------------------------------------------
        # Media
        # ---------------------------------------------------------------------

        "XF86AudioPlay" =
          "exec ${pkgs.playerctl}/bin/playerctl play-pause";

        "XF86AudioPause" =
          "exec ${pkgs.playerctl}/bin/playerctl play-pause";

        "XF86AudioNext" =
          "exec ${pkgs.playerctl}/bin/playerctl next";

        "XF86AudioPrev" =
          "exec ${pkgs.playerctl}/bin/playerctl previous";

        # ---------------------------------------------------------------------
        # Session
        # ---------------------------------------------------------------------

        "Mod4+Shift+e" =
          "exit";
      };
    };
  };
}
