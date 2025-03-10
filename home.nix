{
  config,
  pkgs,
  lib,
  ghostty,
  zen-browser,
  ...
}: {
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

  home.packages = with pkgs;
    [
      # Linux-related System Utils
      amdgpu_top
      ccid
      git
      gnupg
      libbpf
      libcxx
      libelf
      libz
      marksman
      nfs-utils
      pinentry-tty
      pipewire
      rcon
      tectonic
      wireplumber
      wl-clipboard
      xdg-desktop-portal
      xdg-desktop-portal-wlr

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

      # DevTools
      # gcc
      # libnfc
      alejandra
      bpftools
      btop
      bun
      cargo
      clang
      commitizen
      conda
      elfutils
      geekbench
      gnumake
      iperf
      jq
      lazygit
      logiops
      meson
      ninja
      nmap
      nodejs
      python312
      rsync
      starship
      termshark
      tmux
      tree-sitter
      tshark
      uv
      wget
      zstd

      # Modern Unix
      # dog
      bat
      cheat
      delta
      du-dust
      duf
      eza
      fd
      fzf
      gping
      lsd
      mcfly
      ncdu
      ripgrep
      tldr
      zoxide

      # NUS Bloat
      openfortivpn

      # Apps
      # terminal-typeracer
      # zed-editor
      apostrophe
      bitwarden
      blender
      code-cursor
      davinci-resolve
      discord
      glow
      jetbrains.clion
      jetbrains.goland
      jetbrains.idea-ultimate
      jetbrains.pycharm-professional
      jetbrains.rust-rover
      jetbrains.webstorm
      kitty
      mpv
      musescore
      neomutt
      obs-studio
      qbittorrent
      spotify
      steam
      telegram-desktop
      thunderbird
      youtube-music
    ]
    ++ [
      zen-browser.packages.${pkgs.system}.default
      ghostty.packages.${pkgs.system}.default
    ];

  # Git Configs
  programs.git = {
    enable = true;
    aliases = {lola = "log --graph --decorate --pretty=oneline --abbrev-commit --all";};
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

  # LazyGit Config
  home.file."./.config/lazygit/config.yml" = {
    source = ./config/lazygit/config.yml;
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
