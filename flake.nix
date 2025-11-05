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
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ## Non-nixpkgs Applications
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    hyprlauncher.url = "github:hyprwm/hyprlauncher";
    minegrub-theme.url = "github:Lxtharia/minegrub-theme";
    minecraft-plymouth-theme.url = "github:nikp123/minecraft-plymouth-theme";
  };

  outputs = {...} @ inputs: let
    system = "x86_64-linux";

    ## Custom overlays for specific packages
    overlays = {
      ## supergfxctl with a reverted version because of a regression in latest.
      supergfxctl = final: prev: {
        supergfxctl = prev.callPackage ./pkgs/supergfxctl/default.nix {};
      };
      pokego = final: prev: {
        pokego = prev.callPackage ./pkgs/pokego/default.nix {};
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
        {
          nixpkgs.overlays = [overlays.supergfxctl];
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.backupFileExtension = ".bak";
          home-manager.users.chun.imports = [
            ./home.nix

            # HyDE-specific modules
            inputs.hydenix.homeModules.default
            ./modules/home/linux.nix
            ./modules/home/applications.nix
            ./modules/home/mpv.nix
            ./modules/home/hydenix.nix
            ./modules/home/swaylock.nix
            ./modules/home/dunst.nix

            # GNOME specific settings
            ./modules/home/dconf.nix
          ];
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
        {
          nixpkgs.overlays = [
            overlays.supergfxctl
            inputs.hydenix.overlays.default
          ];
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.backupFileExtension = ".bak";
          home-manager.users.chun.imports = [
            inputs.hydenix.homeModules.default
            ./home.nix
            ./modules/home/linux.nix
            ./modules/home/applications.nix
            ./modules/home/mpv.nix

            # HyDE-specific modules
            ./modules/home/hydenix.nix
            ./modules/home/swaylock.nix
            ./modules/home/dunst.nix

            # GNOME specific settings
            ./modules/home/dconf.nix
          ];
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
          nixpkgs.overlays = [overlays.pokego];
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.users.chun.imports = [
            ./home.nix
          ];
        }
      ];
    };
  in {
    ## Build all these nixos configs.
    nixosConfigurations = {
      "chun-lappy" = g14Config;
      "legion-nix" = legionConfig;
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
          ./home.nix
        ];
        extraSpecialArgs = {
          inherit inputs;
        };
      };
    };
  };
}
