# home-manager configurations
# Ideally, OS-agnostic configurations should go here.
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ./cli.nix
    ./dev.nix
    ./git.nix
    ./kitty.nix
    ./neovim.nix
    ./tmux.nix
    ./zed.nix
  ];

  # Let Home Manager install & manage itself
  programs.home-manager.enable = true;

  # Base config for Home Manager
  home.username = "chun";
  home.homeDirectory = "/home/chun";
  home.stateVersion = lib.mkForce "23.05";
}
