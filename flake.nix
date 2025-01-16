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
    ghostty.url = "github:ghostty-org/ghostty";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
  };

  outputs = { self, nixpkgs, nixos-hardware, home-manager, chaotic, ghostty, zen-browser }: {

    nixosConfigurations = {
      "chun-lappy" =
        let
          system = "x86_64-linux";
          zen = zen-browser.packages."${system}";
        in nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./base.nix
            ./hosts/g14/default.nix
            nixos-hardware.nixosModules.asus-zephyrus-ga402
            chaotic.nixosModules.default
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit zen-browser; inherit ghostty; };
              home-manager.users.chun = import ./home.nix;
            }
          ];
        };

      "legion-nix" =
        let
          system = "x86_64-linux";
          zen = zen-browser.packages."${system}";
        in nixpkgs.lib.nixosSystem {
          modules = [
            ./base.nix
            ./hosts/legion/default.nix
            nixos-hardware.nixosModules.lenovo-legion-15arh05h
            chaotic.nixosModules.default
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit zen-browser; inherit ghostty; };
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
