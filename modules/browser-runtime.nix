{pkgs, ...}: {
  programs.nix-ld = {
    enable = true;
    # T3 downloads Chrome outside the Nix store and launches it through nix-ld.
    libraries = with pkgs; [
      glib
      nspr
      nss
      at-spi2-core
      dbus
      libx11
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxrandr
      libgbm
      expat
      libxcb
      libxkbcommon
      systemd
      alsa-lib
    ];
  };
}
