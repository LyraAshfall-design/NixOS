{ config, ... }:

{
  # System modules specific to the physical desktop.
  imports = [
    ./hardware-configuration.nix
    ../../modules/desktop/nvidia.nix
    ../../modules/virtualization.nix
    ../../modules/desktop/phone.nix
    ../../modules/services/tailscale.nix
    ../../modules/services/ssh.nix
  ];

  networking.hostName = "nixos-desktop";

  users.users.corey.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHjllgndoGDQ3RbrHTrm8wK+OeQkFNQZZpUYlOfXppaw coreys-s23"
  ];

  # Ordinary OpenSSH over Tailscale; no SSH opening on LAN/WAN interfaces.
  networking.firewall.interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts =
    config.services.openssh.ports;

  # The physical PC boots using UEFI.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 15;
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

}
