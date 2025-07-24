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
    ./modules/home/applications.nix
    ./modules/home/cli.nix
    ./modules/home/git.nix
    ./modules/home/kitty.nix
    ./modules/home/neovim.nix
    ./modules/home/zed.nix
  ];

  # Let Home Manager install & manage itself
  programs.home-manager.enable = true;

  # Base config for Home Manager
  home.username = "chun";
  home.homeDirectory = "/home/chun";

  home.packages = with pkgs; [
    # AI
    # aider-chat-full

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
    clang-tools
    # commitizen
    conda
    elfutils
    geekbench
    ghostscript_headless
    gnumake
    iperf
    jq
    lua-language-server
    logiops
    marksman
    meson
    ninja
    nmap
    nodejs
    postman
    rsync
    rust-analyzer
    rustfmt
    starship
    termshark
    tmux
    tree-sitter
    tshark
    uv
    wget
    zls
    zstd

    # NUS Bloat
    openfortivpn
  ];

  home.stateVersion = lib.mkForce "23.05";
}
