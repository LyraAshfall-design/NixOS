{ ... }:

{
  # Hardware detected when this VM was installed.
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "nixos-vm";

  # This VM was installed with legacy GRUB on its virtual disk.
  # These settings must not be reused by the physical desktop.
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
    useOSProber = true;
  };
}
