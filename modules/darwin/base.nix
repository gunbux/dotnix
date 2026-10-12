# Common nix-darwin configuration
{pkgs, ...}: {
  # Nix Settings
  # Assumes Nix was installed with the upstream installer, so nix-darwin owns
  # the daemon. Set `nix.enable = false` if using the Determinate installer.
  nix = {
    package = pkgs.nixVersions.latest;

    gc = {
      automatic = true;
      interval = {Hour = 3;};
      options = "--delete-older-than 7d";
    };

    # `auto-optimise-store` can corrupt the store on macOS; optimise on a timer instead.
    optimise.automatic = true;

    settings = {
      trusted-users = ["@admin"];
      sandbox = true;
      max-jobs = "auto";
      keep-going = true;
      log-lines = 20;
      warn-dirty = false;
      experimental-features = [
        "flakes"
        "nix-command"
      ];
      keep-derivations = false;
      keep-outputs = false;
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };

  nixpkgs.config.allowUnfree = true;

  # Shell
  programs.zsh.enable = true;

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    source-sans-pro
    source-serif-pro
  ];

  # Touch ID for sudo (also works inside tmux)
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    reattach = true;
  };

  # Declarative Homebrew, for GUI apps that nixpkgs packages poorly on macOS.
  # Homebrew itself must be installed once by hand (https://brew.sh).
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      # Leave apps installed outside this config (e.g. by company MDM) alone.
      cleanup = "none";
    };
  };

  system.defaults = {
    dock = {
      autohide = true;
      show-recents = false;
      mru-spaces = false;
    };
    finder = {
      AppleShowAllExtensions = true;
      FXPreferredViewStyle = "Nlsv";
      ShowPathbar = true;
    };
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
    };
    trackpad.Clicking = true;
  };
}
