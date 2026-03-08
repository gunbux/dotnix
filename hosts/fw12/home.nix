# FW12-specific home-manager modules
{inputs, ...}: {
  imports = [
    # Base home config
    ../../modules/home/base.nix

    ../../modules/home/linux.nix
    ../../modules/home/niri.nix
    ../../modules/home/applications.nix
    ../../modules/home/mpv.nix
    ../../modules/home/swaylock.nix

    # GNOME specific settings
    ../../modules/home/dconf.nix
  ];
}
