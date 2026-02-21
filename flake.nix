{
  description = "Chun's flake";

  ## NOTE: As much as possible, all of the inputs should just follow nixpkgs so everything is a consistent build.
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # WSL Support
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    ## Sane hyprland defaults
    hydenix = {
      url = "github:richen604/hydenix";
      # inputs.nixpkgs.follows = "nixpkgs";
    };
    ## Non-nixpkgs Applications
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    minegrub-theme.url = "github:Lxtharia/minegrub-theme";
    minecraft-plymouth-theme.url = "github:nikp123/minecraft-plymouth-theme";
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {...} @ inputs: let
    system = "x86_64-linux";

    ## Custom overlays for specific packages
    overlays = {
      custom-packages = final: prev: {
        ## supergfxctl with a reverted version because of a regression in latest.
        supergfxctl = prev.callPackage ./pkgs/supergfxctl/default.nix {};
        ## So shell doesn't break outside of hyde
        pokego = prev.callPackage ./pkgs/pokego/default.nix {};
        ## Fun cursor
        banana-cursor-dreams = prev.callPackage ./pkgs/pokego/default.nix {};
      };
    };

    ## Configs for ASUS Zephyrus G14
    g14Config = inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
      };
      modules = [
        inputs.chaotic.nixosModules.default
        inputs.hydenix.nixosModules.default
        inputs.minegrub-theme.nixosModules.default
        ./hosts/g14/default.nix
        ./modules/hyde.nix
        ./modules/cosmic.nix
        ./modules/niri.nix
        {
          nixpkgs.overlays = [overlays.custom-packages];
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.users.chun.imports = [./hosts/g14/home.nix];
        }
      ];
    };

    ## Configs for Lenovo Legion 5 (2021)
    legionConfig = inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
      };
      modules = [
        inputs.chaotic.nixosModules.default
        inputs.hydenix.nixosModules.default
        inputs.minegrub-theme.nixosModules.default
        ./hosts/legion/default.nix
        ./modules/hyde.nix
        ./modules/cosmic.nix
        ./modules/niri.nix
        {
          nixpkgs.overlays = [
            overlays.custom-packages
            inputs.hydenix.overlays.default
          ];
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.users.chun.imports = [./hosts/legion/home.nix];
        }
      ];
    };

    ## Configs for Framework 12
    fw12Config = inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
      };
      modules = [
        inputs.chaotic.nixosModules.default
        inputs.hydenix.nixosModules.default
        inputs.minegrub-theme.nixosModules.default
        ./hosts/fw12/default.nix
        ./modules/hyde.nix
        ./modules/cosmic.nix
        {
          nixpkgs.overlays = [overlays.custom-packages];
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.users.chun.imports = [./hosts/fw12/home.nix];
        }
      ];
    };

    ## WSL Configs
    wsl = inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      modules = [
        inputs.nixos-wsl.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
        ./modules/nix.nix
        ./modules/wsl.nix
        {
          nixpkgs.overlays = [overlays.custom-packages];
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.users.chun.imports = [
            ./modules/home/base.nix
          ];
        }
      ];
    };
  in {
    ## Build all these nixos configs.
    nixosConfigurations = {
      "chun-lappy" = g14Config;
      "legion-nix" = legionConfig;
      "fw12" = fw12Config;
      "wsl" = wsl;
    };

    homeConfigurations = {
      "non-nixos" = inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        modules = [
          {
            home = {
              username = "chun";
              homeDirectory = "/home/chun";
              stateVersion = "23.05";
            };
          }
          ./modules/home/base.nix
        ];
        extraSpecialArgs = {
          inherit inputs;
        };
      };
    };
  };
}
