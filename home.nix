{ config, pkgs, lib, ghostty, zen-browser, ... }:
{
  imports = [
    # GNOME specific settings
    ./modules/home/dconf.nix
    ./modules/home/hyprland.nix
    ./modules/home/zed.nix
  ];

  # Let Home Manager install & manage itself
  programs.home-manager.enable = true;

  # Base config for Home Manager
  home.username = "chun";
  home.homeDirectory = "/home/chun";

  home.packages = with pkgs; [
    # AI
    aider-chat

    # Screen sharing
    xdg-desktop-portal
    xdg-desktop-portal-wlr
    pipewire
    wireplumber

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

    # System Utils
    amdgpu_top
    btop
    gnupg
    iperf
    marksman
    nmap
    pinentry-tty
    rcon
    rsync
    starship
    termshark
    tshark
    wget
    wl-clipboard

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
      # Set OPENROUTER_API_KEY from ~/.openrouter if it exists
      if [ -f "$HOME/.openrouter" ]; then
        export OPENROUTER_API_KEY=$(cat "$HOME/.openrouter")
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
