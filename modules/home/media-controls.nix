{ pkgs, ... }:

{
  home.packages = with pkgs; [
    wireplumber
    playerctl
    pavucontrol
  ];
}
