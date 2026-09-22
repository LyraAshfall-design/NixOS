{ lib, pkgs, osConfig, ... }:

{
  # Noctalia's built-in agent is disabled in its config to avoid competing
  # authentication dialogs. Keep authentication available in both desktops.
  services.polkit-gnome.enable = true;

  services.network-manager-applet.enable = true;
  xsession.preferStatusNotifierItems = true;
  home.packages = [ pkgs.networkmanagerapplet ];

  systemd.user.services.network-manager-applet = {
    Unit = {
      After = lib.mkForce [ "sway-session.target" "tray.target" ];
      PartOf = lib.mkForce [ "sway-session.target" ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Install.WantedBy = lib.mkForce [ "sway-session.target" ];
    Service.Restart = "on-failure";
  };

  services.blueman-applet = lib.mkIf osConfig.services.blueman.enable {
    enable = true;
    systemdTargets = [ "sway-session.target" ];
  };

  # Systemd owns these applets in Sway. Preserve XDG autostart in Hyprland.
  xdg.configFile."autostart/nm-applet.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=NetworkManager Applet
    Exec=${pkgs.networkmanagerapplet}/bin/nm-applet --indicator
    NotShowIn=sway;
  '';
  xdg.configFile."autostart/blueman.desktop" = lib.mkIf osConfig.services.blueman.enable {
    text = ''
      [Desktop Entry]
      Type=Application
      Name=Blueman Applet
      Exec=${pkgs.blueman}/bin/blueman-applet
      NotShowIn=sway;
    '';
  };
}
