{ ... }:

{
  # Use NVIDIA's driver instead of Nouveau.
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Required for modern Wayland compositors.
    modesetting.enable = true;

    # RTX 2080 SUPER supports NVIDIA's open kernel module.
    open = true;

    # Preserve GPU state/VRAM across suspend and resume.
    powerManagement.enable = true;

    moduleParams.nvidia.NVreg_TemporaryFilePath = "/var/tmp";

    # Install the NVIDIA settings utility.
    nvidiaSettings = true;
  };
}
