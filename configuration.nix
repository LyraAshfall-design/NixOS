{ pkgs, ... }:

{
  # Shared workstation configuration.
  # Host-specific hardware and boot settings live under hosts/.
  imports = [
    ./modules/desktop.nix
    ./modules/packages.nix
    ./modules/gaming.nix
  ];

  # Enable the modern Nix CLI and flake support.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Track the newest kernel available in the pinned NixOS release.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # NetworkManager handles wired and wireless networking.
  networking.networkmanager.enable = true;

  # Remote shell access.
  # Password authentication is enabled while building/testing the system.
  # We can switch this to SSH keys later.
  services.openssh = {
    enable = true;
    openFirewall = true;

    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "no";
    };
  };

  # Regional settings.
  time.timeZone = "America/Vancouver";
  i18n.defaultLocale = "en_CA.UTF-8";

  # Keyboard layout used by X11/XWayland applications.
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Fish is Corey's login shell.
  programs.fish.enable = true;

  # Primary user account.
  users.users.corey = {
    isNormalUser = true;
    description = "Corey";

    # wheel = sudo access
    # networkmanager = permission to manage network connections
    extraGroups = [
      "networkmanager"
      "wheel"
    ];

    shell = pkgs.fish;
  };

  # Required by software with non-free licenses, including Steam
  # and NVIDIA's userspace driver components.
  nixpkgs.config.allowUnfree = true;

  # Home Manager owns Corey's applications and user-level configuration.
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    users.corey = import ./home/corey.nix;
  };

  # Compatibility version for this installation.
  # Do not change this merely because NixOS itself is upgraded later.
  system.stateVersion = "26.05";
}
