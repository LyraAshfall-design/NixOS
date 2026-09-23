{ config, pkgs, ... }:

{
  # Common system settings for both hosts.
  imports = [ ./packages.nix ];

  # Enable the modern Nix CLI and flake support.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # ---------------------------------------------------------------------------
  # Nix store maintenance
  # ---------------------------------------------------------------------------

  # Automatically remove old, unreachable store paths once a week.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Prune only system generations before the existing weekly GC. The +25
  # selector preserves the current generation; user profiles are not targeted.
  systemd.services.nix-gc.preStart = ''
    ${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +25
  '';

  # Deduplicate identical files in the Nix store.
  nix.optimise.automatic = true;


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

  # Compatibility version for this installation.
  # Do not change this merely because NixOS itself is upgraded later.
  system.stateVersion = "26.05";
}
