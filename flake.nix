{
  description = "Corey's NixOS configuration";

  inputs = {
    # Shared nixos-unstable input; flake.lock pins the revision for every host.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Manages Corey's user applications and dotfiles.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hyprland desktop shell/bar.
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    silent-sddm = {
      url = "github:uiriansan/SilentSDDM";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      disko,
      noctalia,
      silent-sddm,
      ...
    }:
    {
      nixosConfigurations = {
        # Physical desktop.
        nixos-desktop = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            ./configuration.nix
            ./hosts/desktop/default.nix

            disko.nixosModules.disko
            home-manager.nixosModules.home-manager
            noctalia.nixosModules.default
            silent-sddm.nixosModules.default
          ];
        };
      };
    };
}
