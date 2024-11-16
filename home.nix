{ config, pkgs, lib, ... }:
# Declaratively add Home Manager
{
  nixpkgs.config.allowUnfree = true;

  # Let Home Manager install & manage itself
  programs.home-manager.enable = true;

  # Gnome Configs
  imports = [ ./modules/dconf.nix ];

  # Base config for Home Manager
  home.username = "chun";
  home.homeDirectory = "/home/chun";

  home.packages = with pkgs; [
    # scx
    # scx

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
    lazygit
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
    termshark
    tshark
    nmap
    wl-clipboard
    rcon
    gnupg
    pinentry-tty

    # DevTools
    # gcc
    bpftools
    cargo
    clang
    jq
    libbpf
    libelf
    elfutils
    libz
    meson
    ninja
    nodejs
    bun
    yarn
    python312
    tree-sitter
    # libnfc
    ccid
    gnumake
    kitty
    geekbench
    zstd

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
    zoxide

    # NUS Bloat
    (openfortivpn.overrideAttrs(
          old: {
            src = builtins.fetchTarball https://github.com/adrienverge/openfortivpn/archive/refs/tags/v1.20.4.tar.gz;
    }))

    # Apps
    apostrophe
    code-cursor
    zed-editor
    obs-studio
    steam
    blender
    spotify
    bitwarden
    discord
    qbittorrent
    telegram-desktop
    # terminal-typeracer
    jetbrains.webstorm
    jetbrains.pycharm-professional
    jetbrains.clion
    jetbrains.rust-rover
    jetbrains.goland
    jetbrains.idea-ultimate
    neomutt
    thunderbird
    musescore

    # davinci-resolve

    # Gnome Dependencies
    tela-icon-theme
    pop-gtk-theme
    nordzy-cursor-theme

    # Gnome Extensions
    gnome-tweaks
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

  # Git Configs
  programs.git = {
    enable = true;
    aliases = { lola = "log --graph --decorate --pretty=oneline --abbrev-commit --all"; };
    delta.enable = true;
    userName = "Chun Yu";
    userEmail = "lamchunyu00@gmail.com";
    # TODO: Add signing
  };

  # Neovim Configs
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    extraLuaConfig = lib.fileContents ./config/nvim/init.lua;
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
    plugins = [
        {
          name = "zsh-nix-shell";
          file = "nix-shell.plugin.zsh";
          src = pkgs.fetchFromGitHub {
            owner = "chisui";
            repo = "zsh-nix-shell";
            rev = "v0.8.0";
            sha256 = "1lzrn0n4fxfcgg65v0qhnj7wnybybqzs4adz7xsrkgmcsr0ii8b7";
        };
      }
    ];
    oh-my-zsh = {
      enable = true;
      plugins = [
        "zoxide"
        "fzf"
      ];
    };
  };

  # Direnv Config
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Hyprland config
  # wayland.windowManager.hyprland.enable = true;

  home.stateVersion = "23.05";
}
