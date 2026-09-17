{ ... }:

{
  # Use NVIDIA's driver instead of Nouveau.
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Required for modern Wayland compositors such as Hyprland.
    modesetting.enable = true;

    # Use NVIDIA's open kernel module.
    # This matches the known-good driver model on the RTX 2080 SUPER.
    open = true;

    # Install the NVIDIA settings utility.
    nvidiaSettings = true;
  };
}
