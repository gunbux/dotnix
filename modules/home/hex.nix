{inputs, ...}: {
  # Hex local voice dictation (anoma.ly/hex). Upstream's flake only builds for
  # x86_64-linux; greptile-mac gets the Homebrew cask instead.
  imports = [inputs.hex.homeManagerModules.hex];

  programs.hex = {
    enable = true;
    # Starts with graphical-session.target, which niri and COSMIC both activate.
    autostart = true;
    # Download the selected model once the network is up; activation never does.
    installModel = true;
  };
}
