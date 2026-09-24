{ config, pkgs, ... }:

{
  # Phone integration for hosts that explicitly import this module.
  # NixOS also opens the TCP/UDP ports required by KDE Connect.
  programs.kdeconnect.enable = true;

  # Discover Android Wireless Debugging endpoints even when ADB lacks mDNS support.
  services.avahi = {
    enable = true;
    openFirewall = true;
  };

  # Run independently of the desktop session, with access to Corey's files.
  services.syncthing = {
    enable = true;
    user = "corey";
    group = config.users.users.corey.group;
    dataDir = config.users.users.corey.home;
    configDir = "${config.users.users.corey.home}/.config/syncthing";
    guiAddress = "127.0.0.1:8384";
    openDefaultPorts = true;

    # Preserve devices and folders added interactively after activation.
    overrideDevices = false;
    overrideFolders = false;
  };

  # systemd provides Android USB access rules for the active local session.
  # Current NixOS no longer needs programs.adb.enable or an adbusers group.
  environment.systemPackages = with pkgs; [
    android-tools # adb and fastboot for USB debugging.
    scrcpy # Display and control the phone over ADB.
  ];
}
