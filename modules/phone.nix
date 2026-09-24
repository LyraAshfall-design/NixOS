{ ... }:

{
  # Phone integration for hosts that explicitly import this module.
  # NixOS also opens the TCP/UDP ports required by KDE Connect.
  programs.kdeconnect.enable = true;
}
