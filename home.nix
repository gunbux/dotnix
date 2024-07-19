{ config, pkgs, lib, ... }:
# Declaratively add Home Manager
{
  imports = [ <home-manager/nixos> ];

  home-manager.users.chun = {
    nixpkgs.config.allowUnfree = true;

    # Let Home Manager install & manage itself
    programs.home-manager.enable = true;

    # Gnome Configs
    imports = [ ./modules/dconf.nix ];

    # Base config for Home Manager
    home.username = "chun";
    home.homeDirectory = "/home/chun";

    home.packages = with pkgs; [
      # Nix utils
      niv

      # Docker
      docker

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
      libcxx
      # power-profiles-daemon # This clashes with TLP

      # System Utils
      iperf
      btop
      rsync
      starship
      wget
      tshark
      nmap
      wl-clipboard
      rcon

      # DevTools
      gcc
      cargo
      ninja
      nodejs
      bun
      yarn
      python312
      # libnfc
      ccid
      gnumake
      alacritty
      geekbench

      # Modern Unix
      bat
      eza
      lsd
      delta
      du-dust
      duf
      fzf
      fd
      ripgrep
      mcfly
      cheat
      tldr
      gping
      dog
      z-lua

      # NUS Bloat
      (openfortivpn.overrideAttrs(
            old: {
              src = builtins.fetchTarball https://github.com/adrienverge/openfortivpn/archive/refs/tags/v1.20.4.tar.gz;
      }))

      # Apps
      apostrophe
      obs-studio
      steam
      blender
      spotify
      bitwarden
      discord
      qbittorrent
      telegram-desktop
      terminal-typeracer
      jetbrains.webstorm
      jetbrains.clion
      jetbrains.goland
      jetbrains.idea-ultimate
      # davinci-resolve

      # Gnome Dependencies
      tela-icon-theme
      pop-gtk-theme
      nordzy-cursor-theme

      # Gnome Extensions
      gnome.gnome-tweaks
      gnomeExtensions.blur-my-shell
      gnomeExtensions.vitals
      gnomeExtensions.supergfxctl-gex
      gnomeExtensions.user-avatar-in-quick-settings
      gnomeExtensions.just-perfection
      gnomeExtensions.space-bar
      gnomeExtensions.gsconnect
      gnomeExtensions.forge
      gnomeExtensions.unite
      gnomeExtensions.pano
      # gnomeExtensions.bat_consumption_wattmeter
    ];

    # Neovim Configs
    programs.neovim = {
      enable = true;
      defaultEditor = true;
      extraConfig = lib.fileContents ./config/nvim/init.vim;
    };

    # Shell Config
    programs.starship = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    programs.zsh = {
      enable = true;
      defaultKeymap = "emacs";
      autosuggestion.enable = true;
      enableCompletion = true;
      autocd = true;
    };

    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    home.stateVersion = "23.05";
  };
}
