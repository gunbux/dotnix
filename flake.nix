{
  description = "Chun's flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
  };

  outputs = { self, nixpkgs, nixos-hardware, home-manager, chaotic }: {

    nixosConfigurations = {
      "chun-lappy" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./base.nix
          ./hosts/g14/default.nix
          chaotic.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.chun = import ./home.nix;
          }
        ];
      };

      "legion-nix" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./base.nix
          ./hosts/legion/default.nix
          nixos-hardware.nixosModules.lenovo-legion-15arh05h
          chaotic.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.chun = import ./home.nix;
          }
        ];
      };
    };

    homeConfigurations = {
      "chun@non-nixos" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        modules = [ 
          ./home.nix
          {
            home = {
              username = "chun";
              homeDirectory = "/home/chun";
              stateVersion = "23.05";
            };
          }
        ];
        extraSpecialArgs = {
          inherit nixpkgs;
        };
      };
    };
  };
}
