{ pkgs, config, osConfig, ... }:

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


  home.pointerCursor = {
    enable = true;
    gtk.enable = true;
    x11.enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 24;
  };

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
  # Terminal
  # ---------------------------------------------------------------------------

  programs.kitty = {
    enable = true;

    extraConfig = ''
      # Static fallback until the desktop theming pass.
      foreground #cdd6f4
      background #1e1e2e
      cursor #f5e0dc
      selection_foreground #1e1e2e
      selection_background #cdd6f4

      background_opacity 0.82
    '';
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
    #   nixos-vm      -> .#nixos-vm
    #   nixos-desktop -> .#nixos-desktop
  functions = {
    rebuild = ''
      sudo nixos-rebuild switch --flake ~/nixos-config#(hostname)
    '';

    update = ''
      cd ~/nixos-config
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
  # File manager
  # ---------------------------------------------------------------------------

  programs.yazi.enable = true;

  # ---------------------------------------------------------------------------
  # User applications
  # ---------------------------------------------------------------------------

  home.packages = with pkgs; [
    firefox
    vesktop
    bitwarden-desktop
    btop
    fastfetch
    wl-clipboard
    onlyoffice-desktopeditors
    qt6Packages.qt6ct
    papirus-icon-theme
    bibata-cursors
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
  xdg.configFile."hypr/xdph.conf".source =
    ./corey/hypr/xdph.conf;

  # ---------------------------------------------------------------------------
  # Qt theming
  # ---------------------------------------------------------------------------

  xdg.configFile."qt6ct/qt6ct.conf".text = ''
    [Appearance]
    color_scheme_path=${pkgs.qt6Packages.qt6ct}/share/qt6ct/colors/darker.conf
    custom_palette=true
    icon_theme=Papirus
    standard_dialogs=default
    style=Fusion

    [Fonts]
    fixed="monospace,9,-1,2,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
    general="Sans Serif,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"

    [Interface]
    activate_item_on_single_click=1
    buttonbox_layout=0
    cursor_flash_time=1000
    dialog_buttons_have_icons=1
    double_click_interval=400
    keyboard_scheme=2
    menus_have_icons=true
    show_shortcuts_in_context_menus=true
    toolbutton_style=4
    underline_shortcut=1
    wheel_scroll_lines=3

    [Troubleshooting]
    force_raster_widgets=1
  '';

  # ---------------------------------------------------------------------------
  # UWSM environment for the retained Hyprland fallback only.
  # Common application settings live in modules/desktop.nix.
  # ---------------------------------------------------------------------------

  xdg.configFile."uwsm/env-hyprland".text = ''
    export HYPRCURSOR_THEME="Bibata-Modern-Ice"
    export HYPRCURSOR_SIZE=24
  '';

  # ---------------------------------------------------------------------------
  # Noctalia
  # ---------------------------------------------------------------------------

  xdg.configFile."noctalia/config.toml".source =
    ./corey/noctalia/config.toml;

  # Portal routing is owned by the NixOS desktop modules for both sessions.
  # Mirror it at user scope because the fallback compositor enables HM portals.
  xdg.portal.config = osConfig.xdg.portal.config;
}
