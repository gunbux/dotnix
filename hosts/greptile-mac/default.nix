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
    # Window automation (PaperWM is configured through Home Manager)
    "hammerspoon"
    "codexbar" # Bundled CLI supplies the SwiftBar AI quota widget

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
    "zoom"
    # Slack and Tailscale are installed by company MDM (Iru); don't let brew fight it.

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
