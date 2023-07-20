{ config, pkgs, lib, ... }:
# Declaratively add Home Manager
let
  home-manager = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/master.tar.gz";
in
{
  imports = [
    (import "${home-manager}/nixos")
  ];

  home-manager.users.chun = {
    nixpkgs.config.allowUnfree = true;
    
    # Let Home Manager install & manage itself
    programs.home-manager.enable = true;
  
    # Base config for Home Manager
    home.username = "chun";
    home.homeDirectory = "/home/chun";
  
    home.packages = with pkgs; [
      # Nix utils
      niv
  
      # Archiving
      unrar
      unzip
      xz
      zip
  
      # PDF
      evince
  
      # Web
      vivaldi
  
      # Core
      git
      nfs-utils
      tmux

      # System Utils
      iperf
      btop
      fzf
      fd
      rsync
      starship
      wget
      tshark
      nmap

      # DevTools
      gcc
      cargo
      ninja
      nodejs
      python312

      # Apps
      spotify
      bitwarden
      discord
      # davinci-resolve
    ];

    # Neovim Configs
    programs.neovim = {
      enable = true;
      defaultEditor = true;
      extraConfig = lib.fileContents ./config/nvim/init.vim;
    };

    home.stateVersion = "23.05";
  };
}
