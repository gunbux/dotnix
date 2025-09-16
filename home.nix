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
    ./modules/home/cli.nix
    ./modules/home/dev.nix
    ./modules/home/git.nix
    ./modules/home/kitty.nix
    ./modules/home/neovim.nix
    ./modules/home/tmux.nix
    ./modules/home/zed.nix
  ];

  # Let Home Manager install & manage itself
  programs.home-manager.enable = true;

  # Base config for Home Manager
  home.username = "chun";
  home.homeDirectory = "/home/chun";
  home.stateVersion = lib.mkForce "23.05";
}
