# Linux-specific packages
{
  pkgs,
  inputs,
  ...
}: {
  home.packages = with pkgs;
    [
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
      scx.full
      tectonic
      wireplumber
      wl-clipboard
      xdg-desktop-portal
      xdg-desktop-portal-wlr
    ]
    ++ [
      inputs.quickshell.packages.${pkgs.system}.default
    ];
}
