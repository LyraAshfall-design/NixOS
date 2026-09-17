{ ... }:

{
  imports = [
    ../../modules/nvidia.nix
  ];

  networking.hostName = "nixos-desktop";

  # Firmware for Wi-Fi / Bluetooth and other hardware
  hardware.enableRedistributableFirmware = true;

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.blueman.enable = true;

  # Audio
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;

    alsa = {
      enable = true;
      support32Bit = true;
    };

    pulse.enable = true;
  };
}
