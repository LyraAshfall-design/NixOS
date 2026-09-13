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
}
