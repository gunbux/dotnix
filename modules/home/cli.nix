# Command Line Applications
{pkgs, ...}: {
  home.packages = with pkgs; [
    bat
    bpftools
    btop
    cheat
    commitizen
    delta
    docker
    dog
    duf
    dust
    elfutils
    eza
    fd
    fzf
    gping
    impala
    iperf
    jq
    lsd
    mcfly
    ncdu
    nh
    nix-output-monitor
    nmap
    opencode
    pokego
    presenterm
    ripgrep
    rsync
    starship
    termshark
    tldr
    tmux
    unrar
    unzip
    wget
    xz
    zip
    zoxide
    zstd
  ];

  # Mutt Configs
  home.file.".config/mutt/" = {
    source = ../../config/mutt;
    recursive = true;
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

    initContent = ''
      pokego --no-title -r 1-6
      # Set OPENROUTER_API_KEY from ~/.openrouter if it exists
      if [ -f "$HOME/.openrouter" ]; then
        export OPENROUTER_API_KEY=$(cat "$HOME/.openrouter")
      fi

      if [[ $TERM != "dumb" ]]; then
        eval "$(/etc/profiles/per-user/chun/bin/starship init zsh)"
      fi

      if [ "$TMUX" = "" ]; then tmux; fi
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
}
