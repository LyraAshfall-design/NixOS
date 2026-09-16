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

  programs.kitty.enable = true;

  programs.bash = {
    enable = true;
    shellAliases = {
      ll = "ls -lah";
      rebuild = "sudo nixos-rebuild switch";
    };
  };

  programs.yazi.enable = true;

  home.packages = with pkgs; [
    firefox
    btop
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
