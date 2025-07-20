{
  description = "Chun's flake";

  ## NOTE: As much as possible, all of the inputs should just follow nixpkgs so everything is a consistent build.
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ## allows nix-locate to find binaries and comma for one-time runs.
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ## Sane hyprland defaults
    hydenix = {
      url = "github:richen604/hydenix";
      inputs.hydenix-nixpkgs.follows = "nixpkgs";
    };
    ## Non-nixpkgs Applications
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {...} @ inputs: let
    system = "x86_64-linux";

    ## Custom overlays for specific packages
    overlays = {
      ## supergfxctl with a reverted version because of a regression in latest.
      supergfxctl = final: prev: {
        supergfxctl = prev.callPackage ./pkgs/supergfxctl/default.nix {};
      };
    };

    ## Configs for ASUS Zephyrus G14
    g14Config = inputs.hydenix.inputs.hydenix-nixpkgs.lib.nixosSystem {
      inherit (inputs.hydenix.lib) system;
      specialArgs = {
        inherit inputs;
      };
      modules = [
        ./modules/hyde.nix
        ./modules/gnome.nix
        ./hosts/g14/default.nix
        {
          nixpkgs.overlays = [overlays.supergfxctl];
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.users.chun.imports = [
            inputs.nix-index-database.homeModules.nix-index
            ./home.nix

            # HyDE-specific modules
            inputs.hydenix.lib.homeModules
            ./modules/home/hydenix.nix
            ./modules/home/swaylock.nix
            ./modules/home/hyprland.nix
            ./modules/home/dunst.nix

            # GNOME specific settings
            ./modules/home/dconf.nix
          ];
        }
      ];
    };

    ## Configs for Lenovo Legion 5 (2021)
    legionConfig = inputs.hydenix.inputs.hydenix-nixpkgs.lib.nixosSystem {
      inherit (inputs.hydenix.lib) system;
      specialArgs = {
        inherit inputs;
      };
      modules = [
        ./modules/hyde.nix
        ./modules/gnome.nix
        ./modules/cosmic.nix
        ./hosts/legion/default.nix
        {
          nixpkgs.overlays = [overlays.supergfxctl];
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.backupFileExtension = ".bak";
          home-manager.users.chun.imports = [
            inputs.nix-index-database.homeModules.nix-index
            ./home.nix

            # HyDE-specific modules
            inputs.hydenix.lib.homeModules
            ./modules/home/hydenix.nix
            ./modules/home/swaylock.nix
            ./modules/home/hyprland.nix
            ./modules/home/dunst.nix

            # GNOME specific settings
            ./modules/home/dconf.nix
          ];
        }
      ];
    };
  in {
    ## Build both nixos configurations
    nixosConfigurations = {
      "chun-lappy" = g14Config;
      "legion-nix" = legionConfig;
    };

    #  WARN: This is a configuration for just the home-manager, but is not tested.
    # homeConfigurations = {
    #   "chun@non-nixos" = inputs.home-manager.lib.homeManagerConfiguration {
    #     pkgs = import inputs.nixpkgs {
    #       inherit system;
    #     };
    #     modules = [
    #       ./home.nix
    #       {
    #         home = {
    #           username = "chun";
    #           homeDirectory = "/home/chun";
    #           stateVersion = "23.05";
    #         };
    #       }
    #     ];
    #     extraSpecialArgs = with inputs; {
    #       inherit nixpkgs;
    #     };
    #   };
    # };
  };
}
