# Work MacBook (Apple Silicon)
{...}: {
  imports = [
    ../../modules/darwin/base.nix
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";

  networking.hostName = "greptile-mac";

  users.users.chun.home = "/Users/chun";
  system.primaryUser = "chun";

  homebrew.casks = [
    # Editors / Terminals
    "cursor"
    "ghostty"
    "kitty"
    "visual-studio-code"

    # Browsers
    "vivaldi"
    "zen"

    # Work
    "orbstack" # Docker runtime
    "postman"
    "slack"
    "tailscale-app"
    "zoom"

    # Personal
    "discord"
    "localsend"
    "paseo"
    "spotify"
    "t3-code"
    "telegram"
  ];

  system.stateVersion = 6;
}
