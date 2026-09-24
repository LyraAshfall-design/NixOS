{ ... }:

{
  imports = [
    ./modules/base.nix
    ./modules/desktop.nix
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
