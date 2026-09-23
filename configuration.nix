{ config, pkgs, ... }@args:

(import ./modules/base.nix args) // {
  # Extend the base in place to preserve workstation module ordering.
  imports = [
    ./modules/desktop.nix
    ./modules/packages.nix
    ./modules/gaming.nix
  ];

  # Required by software with non-free licenses, including Steam
  # and NVIDIA's userspace driver components.
  nixpkgs.config.allowUnfree = true;

  # Home Manager owns Corey's applications and user-level configuration.
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    users.corey = import ./home/corey.nix;
  };
}
