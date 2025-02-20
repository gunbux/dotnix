{ config, pkgs, lib, ghostty, zen-browser, ... }:
{
  imports = [
    # GNOME specific settings
    ./modules/home/dconf.nix
    ./modules/home/hyprland.nix
    ./modules/home/zed.nix
  ];

  nixpkgs.config.allowUnfree = true;

  # Let Home Manager install & manage itself
  programs.home-manager.enable = true;

  # Base config for Home Manager
  home.username = "chun";
  home.homeDirectory = "/home/chun";

  home.packages = with pkgs; [
    # AI
    aider-chat

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

    # VPN
    mullvad-vpn
    tailscale

    # Mouse
    solaar

    # Core
    git
    uv
    lazygit
    nfs-utils
    tmux
    libcxx
    # power-profiles-daemon # This clashes with TLP

    # TODO: Move this to DE specific config
    # System Utils
    marksman
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
    conda
    jq
    libbpf
    libelf
    elfutils
    libz
    meson
    ninja
    nodejs
    bun
    python312
    tree-sitter
    # libnfc
    ccid
    gnumake
    kitty
    geekbench
    zstd
    logiops

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
    # dog
    zoxide

    # NUS Bloat
    (openfortivpn.overrideAttrs(
          old: {
            src = builtins.fetchTarball {
              url = "https://github.com/adrienverge/openfortivpn/archive/refs/tags/v1.20.4.tar.gz";
              sha256 = "sha256:1dzw16ndvghkkhq8z5w6vyxblrjkmns0mfh8r6z8q4r95dal59i4";
            };
    }))

    # Apps
    apostrophe
    code-cursor
    # zed-editor
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
    mpv
    thunderbird
    musescore

    davinci-resolve
  ] ++ [
      zen-browser.packages.${pkgs.system}.default
      ghostty.packages.${pkgs.system}.default
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
    # extraLuaConfig = lib.fileContents ./config/nvim/init.lua;
  };

  # LazyVim Config
  home.file."./.config/nvim/" = {
    source = ./config/lazyvim;
    recursive = true;
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
    initExtra = ''
      # Load environment variables from ~/.env if it exists
      if [ -f "$HOME/.env" ]; then
        source "$HOME/.env"
      fi
    '';
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

    shellAliases = {
      lg = "lazygit";
    };
  };

  # Direnv Config
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Hyprland config
  wayland.windowManager.hyprland.enable = true;

  home.stateVersion = "23.05";
}
