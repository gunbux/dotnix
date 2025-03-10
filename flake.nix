{
  description = "Chun's flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ghostty.url = "github:ghostty-org/ghostty";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
  };

  outputs = {...} @ inputs: let
    system = "x86_64-linux";
    pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    zen = inputs.zen-browser.packages."${system}";
  in {
    nixosConfigurations = {
      "chun-lappy" = inputs.nixpkgs.lib.nixosSystem {
        modules = [
          ./base.nix
          ./hosts/g14/default.nix
          inputs.nixos-hardware.nixosModules.asus-zephyrus-ga402
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = with inputs; {
              inherit zen-browser;
              inherit ghostty;
            };
            home-manager.users.chun = import ./home.nix;
          }
        ];
      };

      "legion-nix" = inputs.nixpkgs.lib.nixosSystem {
        modules = [
          ./base.nix
          ./hosts/legion/default.nix
          inputs.nixos-hardware.nixosModules.lenovo-legion-15arh05h
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = with inputs; {
              inherit zen-browser;
              inherit ghostty;
            };
            home-manager.users.chun = import ./home.nix;
          }
        ];
      };
    };

    homeConfigurations = {
      "chun@non-nixos" = inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
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
        extraSpecialArgs = with inputs; {
          inherit nixpkgs;
        };
      };
    };
  };
}
