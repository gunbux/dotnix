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
    hydenix = {
      # Available inputs:
      # Main: github:richen604/hydenix
      # Dev: github:richen604/hydenix/dev
      # Commit: github:richen604/hydenix/<commit-hash>
      # Version: github:richen604/hydenix/v1.0.0
      url = "github:richen604/hydenix";
    };
  };

  outputs = {...} @ inputs: let
    system = "x86_64-linux";
    pkgs = import inputs.nixpkgs {
      inherit system;
    };

    # Hyde Configs
    g14Config = inputs.hydenix.lib.mkConfig {
      userConfig = import ./hosts/g14/config.nix;
      extraInputs = inputs;
      # Pass user's pkgs to be used alongside hydenix's pkgs (eg. userPkgs.kitty)
      extraPkgs = pkgs;
    };
  in {
    nixosConfigurations = {
      ${g14Config.userConfig.host} = g14Config.nixosConfiguration;

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
