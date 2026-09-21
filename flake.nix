{
  description = "Corey's NixOS configuration";

  inputs = {
    # Stable NixOS release used by every host in this repo.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Manages Corey's user applications and dotfiles.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hyprland desktop shell/bar.
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, noctalia, ... }: {
    nixosConfigurations = {
      # Current development/test VM.
      nixos-vm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        modules = [
          ./configuration.nix
          ./hosts/vm/default.nix

          home-manager.nixosModules.home-manager
          noctalia.nixosModules.default
        ];
      };

      # Physical desktop.
      nixos-desktop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        modules = [
          ./configuration.nix
          ./hosts/desktop/default.nix

          home-manager.nixosModules.home-manager
          noctalia.nixosModules.default
        ];
      };
    };
  };
}
