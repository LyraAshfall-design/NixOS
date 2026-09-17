{pkgs, config, ...}:

{
  home.username = "corey";
  home.homeDirectory = "/home/corey";
  home.stateVersion = "26.05";

 xdg.userDirs = {
     enable = true;
     createDirectories = true;

     desktop = "${config.home.homeDirectory}/Desktop";
     documents = "${config.home.homeDirectory}/Documents";
     download = "${config.home.homeDirectory}/Downloads";
     music = "${config.home.homeDirectory}/Music";
     pictures = "${config.home.homeDirectory}/Pictures";
   };


  programs.home-manager.enable = true;

  programs.kitty = { 
    enable = true;
    extraConfig = ''
      include themes/noctalia.conf
      background_opacity 0.82
    '';
   };

  programs.fish = {
    enable = true;
    shellAliases = {
      ll = "ls -lah";
      rebuild = "sudo nixos-rebuild switch --flake ~/nixos-config#nixos";
    };

   interactiveShellInit = ''
      set -g fish_greeting
    '';
  };

  programs.yazi.enable = true;

  home.packages = with pkgs; [
    firefox
    vesktop
    btop
    qt6Packages.qt6ct
    papirus-icon-theme
    bibata-cursors
    fastfetch
    satty
    gnome-text-editor
    gnome-calculator
    hyprpicker
  ];

 # Hyprland
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    configType = "lua";
    systemd.enable = false;

    extraConfig = builtins.readFile ./corey/hypr/hyprland.lua;
  };

  xdg.configFile."qt6ct/qt6ct.conf".text = ''
    [Appearance]
    color_scheme_path=/home/corey/.local/share/color-schemes/noctalia.colors
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

  xdg.configFile."uwsm/env".text = ''
  export BROWSER=firefox
  export TERM=xterm-kitty

  export QT_QPA_PLATFORM="wayland;xcb"
  export QT_QPA_PLATFORMTHEME="qt6ct"
  export ELECTRON_OZONE_PLATFORM_HINT=auto

  export HYPRCURSOR_THEME="Bibata-Modern-Ice"
  export HYPRCURSOR_SIZE=24
  export XCURSOR_THEME="Bibata-Modern-Ice"
  export XCURSOR_SIZE=24

  # NVIDIA settings get enabled for the physical desktop later.
  # export GBM_BACKEND=nvidia-drm
  # export __GLX_VENDOR_LIBRARY_NAME=nvidia
  # export LIBVA_DRIVER_NAME=nvidia
  # export __GL_GSYNC_ALLOWED=1
'';

  xdg.configFile."hypr/config" = {
    source = ./corey/hypr/config;
    recursive = true;
  };

  xdg.configFile."hypr/xdph.conf".source =
    ./corey/hypr/xdph.conf;

  xdg.configFile."noctalia/config.toml".source =
   ./corey/noctalia/config.toml;

  xdg.portal = {
    enable = true;
    config.common.default = "*";
  };

}
