{ pkgs, config, ... }:

{
  # Corey's background services.
  imports = [
    ./corey/services/mogledger.nix
    ../modules/home
  ];

  # ---------------------------------------------------------------------------
  # Home Manager identity
  # ---------------------------------------------------------------------------

  home.username = "corey";
  home.homeDirectory = "/home/corey";

  # Home Manager compatibility version.
  # Do not change this merely because Home Manager itself is upgraded.
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  # ---------------------------------------------------------------------------
  # Standard user directories
  # ---------------------------------------------------------------------------

  xdg.userDirs = {
    enable = true;
    createDirectories = true;

    desktop = "${config.home.homeDirectory}/Desktop";
    documents = "${config.home.homeDirectory}/Documents";
    download = "${config.home.homeDirectory}/Downloads";
    music = "${config.home.homeDirectory}/Music";
    pictures = "${config.home.homeDirectory}/Pictures";
  };

  # ---------------------------------------------------------------------------
  # Shell
  # ---------------------------------------------------------------------------

  programs.fish = {
    enable = true;

    shellAliases = {
      ll = "ls -lah";
    };

    # Rebuild whichever host this configuration is currently running on.
    # Example:
    #   nixos-desktop -> .#nixos-desktop
    functions = {
      rebuild = ''
        sudo nixos-rebuild switch --flake ~/nixos-config#(hostname)
        set -l rebuild_status $status
        if test $rebuild_status -eq 0
          set generation (readlink /nix/var/nix/profiles/system | string match -r -g 'system-([0-9]+)-' | head -n1)
          if test -z "$generation"
            set generation unknown
          end
          notify-send -a NixOS "System rebuild succeeded" "Active generation: $generation"
          return 0
        end

        notify-send -u critical -a NixOS "System rebuild failed" "Check the terminal output for errors and activation status."
        return $rebuild_status
      '';

      update = ''
        cd ~/nixos-config; or return
        nix flake update; or return
        rebuild
      '';
    };

    interactiveShellInit = ''
      # Disable Fish's default greeting.
      set -g fish_greeting
    '';
  };

  # ---------------------------------------------------------------------------
  # User applications
  # ---------------------------------------------------------------------------

  home.packages = with pkgs; [
    firefox
    vesktop
    bitwarden-desktop
    fastfetch
    wl-clipboard
    onlyoffice-desktopeditors
    xivlauncher
    satty
    gnome-text-editor
    gnome-calculator
    codex
    hyprpicker
  ];

  # ---------------------------------------------------------------------------
  # Hyprland
  # ---------------------------------------------------------------------------

  # NixOS installs Hyprland itself.
  # Home Manager owns Corey's Hyprland configuration.
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    # NixOS owns portal backends and routing.
    portalPackage = null;

    # The imported configuration is written using Hyprland's Lua support.
    configType = "lua";

    # UWSM manages the session instead of Home Manager's Hyprland service.
    systemd.enable = false;

    extraConfig = builtins.readFile ./corey/hypr/hyprland.lua;
  };

  # Deploy the modular Lua configuration directory.
  xdg.configFile."hypr/config" = {
    source = ./corey/hypr/config;
    recursive = true;
  };

  # Hyprland desktop portal configuration.
  xdg.configFile."hypr/xdph.conf".source = ./corey/hypr/xdph.conf;

  # ---------------------------------------------------------------------------
  # UWSM environment for the retained Hyprland fallback only.
  # Common application settings live in modules/desktop/default.nix.
  # ---------------------------------------------------------------------------

  xdg.configFile."uwsm/env-hyprland".text = ''
    export HYPRCURSOR_THEME="${config.home.pointerCursor.name}"
    export HYPRCURSOR_SIZE=24
  '';

  # ---------------------------------------------------------------------------
  # Noctalia
  # ---------------------------------------------------------------------------

  xdg.configFile."noctalia/config.toml".source = ./corey/noctalia/config.toml;
}
