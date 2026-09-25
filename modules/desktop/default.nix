{ pkgs, ... }:

{
  imports = [
    ./sddm.nix
    ./sway.nix
  ];

  # File management only; this does not enable the XFCE desktop.
  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-archive-plugin
      thunar-volman
    ];
  };
  services.gvfs.enable = true;
  services.tumbler.enable = true;
  environment.systemPackages = [ pkgs.file-roller ];

  # Retained Hyprland fallback compositor.
  # UWSM manages the graphical session and its environment.
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  # Noctalia remains the fallback shell; Sway has independent utilities.
  programs.noctalia = {
    enable = true;
    systemd.enable = true;
  };

  # UWSM imports the desktop identity before graphical-session.target starts.
  systemd.user.services.noctalia.unitConfig.ConditionEnvironment = "XDG_CURRENT_DESKTOP=Hyprland";

  # Shared by Sway and the fallback session, without sourcing UWSM files.
  # Terminals set TERM themselves; home.pointerCursor owns XCURSOR settings.
  environment.sessionVariables = {
    BROWSER = "firefox";
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_QPA_PLATFORMTHEME = "qt6ct";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
  };

  # Credential storage for graphical applications.
  services.gnome.gnome-keyring.enable = true;

  # Allows PipeWire to request realtime scheduling priority.
  security.rtkit.enable = true;

  # Desktop audio stack.
  # PulseAudio compatibility is provided through PipeWire.
  services.pipewire = {
    enable = true;

    alsa = {
      enable = true;

      # Needed by some 32-bit applications and games.
      support32Bit = true;
    };

    pulse.enable = true;
  };

  # Desktop portals provide Wayland applications with things such as
  # file pickers, screenshots, screen sharing, and sandbox integration.
  xdg.portal = {
    enable = true;

    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
    ];

    # The compositor modules install their own portal backends. Sway provides
    # GTK defaults plus WLR ScreenCast/Screenshot routing automatically.
    config.hyprland.default = [
      "hyprland"
      "gtk"
    ];
  };
}
