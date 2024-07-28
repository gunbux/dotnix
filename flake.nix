{
  description = "Basic flake support";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
  };

  outputs = { self, nixpkgs, chaotic, home-manager }: {

    nixosConfigurations = {
      "chun-lappy" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./base.nix
          ./hosts/g14/default.nix
          chaotic.nixosModules.default
        ];
      };

      "legion-nix" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./base.nix
          ./hosts/legion/default.nix
          chaotic.nixosModules.default
        ];
      };
    };
  };
}
