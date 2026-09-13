{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    git
    btop
    fastfetch
    kitty
    firefox
    yazi
  ];
}
