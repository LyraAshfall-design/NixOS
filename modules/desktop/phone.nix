{ pkgs, ... }:

{
  # Phone integration for hosts that explicitly import this module.
  # NixOS also opens the TCP/UDP ports required by KDE Connect.
  programs.kdeconnect.enable = true;

  # Discover Android Wireless Debugging endpoints even when ADB lacks mDNS support.
  services.avahi = {
    enable = true;
    openFirewall = true;
  };

  # systemd provides Android USB access rules for the active local session.
  # Current NixOS no longer needs programs.adb.enable or an adbusers group.
  environment.systemPackages = with pkgs; [
    android-tools # adb and fastboot for USB debugging.
    scrcpy # Display and control the phone over ADB.
  ];
}
