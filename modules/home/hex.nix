{
  inputs,
  pkgs,
  ...
}: {
  # Hex local voice dictation (anoma.ly/hex). Upstream's flake only builds for
  # x86_64-linux; greptile-mac gets the Homebrew cask instead.
  imports = [inputs.hex.homeManagerModules.hex];

  programs.hex = {
    enable = true;
    package = pkgs.hex;
    # Starts with graphical-session.target, which niri and COSMIC both activate.
    autostart = true;
    # Download the selected model once the network is up; activation never does.
    installModel = true;
    # muesli's capsule (modules/home/muesli.nix) replaces Hex's own during a
    # meeting, so only one shows.
    settings."meetings.show_recording_indicator" = false;
  };
}
