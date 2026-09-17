{ pkgs, ... }:

{
  # Hyprland compositor.
  # UWSM manages the graphical session and its environment.
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  # Noctalia provides the desktop shell/bar.
  programs.noctalia = {
    enable = true;
    systemd.enable = true;
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

  # Astronaut theme files for SDDM.
  environment.systemPackages = with pkgs; [
    sddm-astronaut
  ];

  # Graphical login manager.
  services.displayManager.sddm = {
    enable = true;
    package = pkgs.kdePackages.sddm;
    wayland.enable = true;
    theme = "sddm-astronaut-theme";

    # Qt components required by the Astronaut theme.
    extraPackages = with pkgs; [
      kdePackages.qtmultimedia
      kdePackages.qtsvg
      kdePackages.qtvirtualkeyboard
    ];
  };

  # Desktop portals provide Wayland applications with things such as
  # file pickers, screenshots, screen sharing, and sandbox integration.
  xdg.portal = {
    enable = true;

    extraPortals = with pkgs; [
      xdg-desktop-portal-hyprland
      xdg-desktop-portal-gtk
    ];

    config.hyprland.default = [
      "hyprland"
      "gtk"
    ];
  };
}
