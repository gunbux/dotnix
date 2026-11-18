# Linux-specific packages
{
  pkgs,
  inputs,
  ...
}: {
  # muesli builds on Hex and provides the meeting capsule hex.nix relies on.
  imports = [./hex.nix ./muesli.nix];

  home.packages = with pkgs; [
    # Linux-related System Utils
    ccid
    fuse3
    gnupg
    libbpf
    libcxx
    libelf
    libqalculate
    libz
    logiops
    nfs-utils
    pinentry-tty
    pipewire
    scx.full
    tectonic
    wireplumber
    wl-clipboard
    xdg-desktop-portal
    xdg-desktop-portal-wlr
  ];
}
