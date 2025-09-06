# Linux-specific packages
{pkgs, ...}: {
  home.packages = with pkgs; [
    # Linux-related System Utils
    amdgpu_top
    ccid
    gnupg
    libbpf
    libcxx
    libelf
    libz
    nautilus
    nfs-utils
    pinentry-tty
    pipewire
    libqalculate
    rcon
    tectonic
    wireplumber
    wl-clipboard
    xdg-desktop-portal
    xdg-desktop-portal-wlr
  ];
}
