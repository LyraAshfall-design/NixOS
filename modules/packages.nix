{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    git
    btop
    wl-clipboard
    fastfetch
    kitty
    firefox
    yazi
  ];
}
