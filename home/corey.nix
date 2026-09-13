{pkgs, ...}:

{
  home.username = "corey";
  home.homeDirectory = "/home/corey";
  home.stateVersion = "26.05";

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
  ];

 # Hyprland
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    configType = "lua";
    systemd.enable = false;

    extraConfig = ''
      hl.bind("SUPER + RETURN", hl.dsp.exec_cmd("kitty"))
      hl.bind("SUPER + Q", hl.dsp.window.close())
      hl.bind("SUPER + W", hl.dsp.exec_cmd("firefox"))
      hl.bind("SUPER + SHIFT + E", hl.dsp.exit())
    '';
  };
}
