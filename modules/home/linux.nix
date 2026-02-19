# Linux-specific packages
{
  pkgs,
  inputs,
  ...
}: {
  home.packages = with pkgs; [
    # Linux-related System Utils
    ccid
    gnupg
    libbpf
    libcxx
    libelf
    libqalculate
    libz
    logiops
    nautilus
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
