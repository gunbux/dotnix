{
  description = "Chun's flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    hydenix = {
      url = "github:richen604/hydenix";
    };
  };

  outputs = {...} @ inputs: let
    system = "x86_64-linux";

    # Hyde Configs
    g14Config = inputs.hydenix.inputs.hydenix-nixpkgs.lib.nixosSystem {
      inherit (inputs.hydenix.lib) system;
      specialArgs = {
        inherit inputs;
      };
      modules = [
        ./modules/hyde.nix
        ./hosts/g14/default.nix
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.users.chun.imports = [
            inputs.hydenix.lib.homeModules
            ./home.nix

            ./modules/home/hydenix.nix
            # HyDE-specific modules
            ./modules/home/swaylock.nix
            ./modules/home/hyprland.nix
            ./modules/home/dunst.nix
          ];
        }
      ];
    };
  in {
    nixosConfigurations = {
      "chun-lappy" = g14Config;

      "legion-nix" = inputs.nixpkgs.lib.nixosSystem {
        modules = [
          ./base.nix
          ./modules/gnome.nix
          ./hosts/legion/default.nix
          inputs.nixos-hardware.nixosModules.lenovo-legion-15arh05h
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {inherit inputs;};
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
