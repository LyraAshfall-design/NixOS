{ pkgs, ... }:

{
  # Base system/admin tools.
  # Desktop applications used only by Corey belong in Home Manager.
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
  ];
}
