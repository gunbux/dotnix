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

      # Gnome Extensions
      pop-launcher
      gnome.gnome-tweaks
      gnomeExtensions.pop-shell
      gnomeExtensions.pop-launcher-super-key
      gnomeExtensions.blur-my-shell
    ];

    # Neovim Configs
    programs.neovim = {
      enable = true;
      defaultEditor = true;
      extraConfig = lib.fileContents ./config/nvim/init.vim;
    };

    # Gnome Config
    gtk = {
      enable = true;

      iconTheme = {
      name = "Tela";
      package = pkgs.tela-icon-theme;
    };

      theme = {
        name = "pop-dark";
        package = pkgs.pop-gtk-theme;
      };

      cursorTheme = {
        name = "Numix-Cursor";
        size = 35;
        package = pkgs.numix-cursor-theme;
      };

      gtk3.extraConfig = {
        Settings = ''
          gtk-application-prefer-dark-theme=1
        '';
      };

      gtk4.extraConfig = {
        Settings = ''
          gtk-application-prefer-dark-theme=1
        '';
      };
    };

    home.sessionVariables.GTK_THEME = "pop-dark";

    dconf.settings = {
      "org/gnome/shell" = {
         favorite-apps = [
           "org.gnome.Console.desktop"
           "org.gnome.Nautilus.desktop"
           "spotify.desktop"
           "discord.desktop"
           "vivaldi-stable.desktop"
         ];
      };

      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        clock-format = "12h";
      };

      "org/gnome/desktop/wm/preferences" = {
        workspace-names = [ "Main" ];
      };

      "org/gnome/desktop/sound" = {
        allow-volume-above-100-percent = true;
      };

      "org/gnome/desktop/interface" = {
         font-name = "Source Sans 3 11";
         document-font-name = "Source Sans 3 11";
         monospace-font-name = "JetBrainsMono Nerd Font 10";
      };

      "org/gnome/shell" = {
        disable-user-extensions = false;

        enabled-extensions = [
          "blur-my-shell@aunetx"
          "pop-launcher-super-key@ManeLippert"
          "pop-shell@system76.com"
          "launch-new-instance@gnome-shell-extensions.gcampax.github.com"
        ];
      };
    };

    home.stateVersion = "23.05";
  };
}
