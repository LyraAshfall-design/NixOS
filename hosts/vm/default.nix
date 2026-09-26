{ ... }:

{
  # Hardware detected when this VM was installed.
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  networking.hostName = "nixos-vm";

  # Preserve the lab VM's existing SSH access, formerly in the shared base.
  # The desktop's key-only/Tailscale policy is enabled separately.
  services.openssh = {
    enable = true;
    openFirewall = true;

    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "no";
    };
  };

  # Keep swap on the existing ext4 root filesystem; NixOS creates and
  # initializes this file when its declared size does not match.
  swapDevices = [
    {
      device = "/swapfile";
      size = 8192;
    }
  ];

  # Required by unfree applications in Corey's Home Manager configuration.
  nixpkgs.config.allowUnfree = true;

  services.qemuGuest.enable = true;

  services.xserver.enable = true;
  services.xserver.desktopManager.xfce.enable = true;
  services.xserver.displayManager.lightdm.enable = true;

  # Home Manager owns Corey's applications and user-level configuration.
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    users.corey = import ../../home/corey.nix;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
