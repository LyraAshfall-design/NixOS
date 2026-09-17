{ ... }:

{
  # Hardware-specific modules for the physical desktop.
  imports = [
    ../../modules/nvidia.nix
  ];

  networking.hostName = "nixos-desktop";

  # The physical PC boots using UEFI.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Firmware required by hardware such as Wi-Fi and Bluetooth devices.
  hardware.enableRedistributableFirmware = true;

  # Physical Bluetooth hardware support.
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # GUI Bluetooth manager.
  services.blueman.enable = true;

  # A real hardware-configuration.nix will be added when NixOS is
  # installed on the physical machine. Do not fabricate disk UUIDs.
}
