{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    # GNOME specific settings
    # ./modules/home/dconf.nix
    # ./modules/home/hyprland.nix
    ./modules/home/zed.nix

    # Hyde override for vscode
    ./modules/home/hyde-vscode.nix
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
      nautilus
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
      # python312
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
      inputs.zen-browser.packages.${pkgs.system}.default
      inputs.ghostty.packages.${pkgs.system}.default
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

  # Ghostty Config
  home.file.".config/ghostty/config" = {
    source = config/ghostty/config;
    force = true;
    mutable = true;
  };

  # Swaylock Config
  home.file.".config/swaylock/config" = {
    source = config/swaylock/config;
    force = true;
    mutable = true;
  };

  # Additional hyprland configs
  home.file.".config/hypr/monitors.conf" = lib.mkForce {
    source = config/hypr/monitors.conf;
    force = true;
    mutable = true;
  };

  home.file.".config/hypr/userprefs.conf" = lib.mkForce {
    source = config/hypr/userprefs.conf;
    force = true;
    mutable = true;
  };

  home.file.".config/hypr/keybindings.conf" = lib.mkForce {
    source = config/hypr/keybindings.conf;
    force = true;
    mutable = true;
  };

  home.file.".config/waybar/config.ctl" = lib.mkForce {
    source = config/waybar/config.ctl;
    force = true;
    mutable = true;
  };

  # Hyde dunst configs
  home.file.".config/dunst/dunst.conf" = lib.mkForce {
    source = config/dunst/dunst.conf;
    force = true;
    mutable = true;
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

    # Hacky override to hyde configs
    initExtra = lib.mkForce ''
      # Set OPENROUTER_API_KEY from ~/.openrouter if it exists
      if [ -f "$HOME/.openrouter" ]; then
        export OPENROUTER_API_KEY=$(cat "$HOME/.openrouter")
      fi

      if [[ $TERM != "dumb" ]]; then
        eval "$(/etc/profiles/per-user/chun/bin/starship init zsh)"
      fi
    '';

    initExtraFirst = lib.mkForce ''
      #Display Pokemonks
      pokemon-colorscripts --no-title -r 1-3
    '';

    shellAliases = {
      lg = "lazygit";
      c = "clear";
      l = "eza -lh --icons=auto";
      ls = "eza --icons=auto";
      ll = "eza -lha --icons=auto --sort=name --group-directories-first";
      ld = "eza -lhD --icons=auto";
    };
  };

  # Shell Config
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  # Direnv Config
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Hyprland config
  wayland.windowManager.hyprland.enable = true;

  home.stateVersion = lib.mkForce "23.05";
}
