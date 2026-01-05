# FW12-specific home-manager modules
{inputs, ...}: {
  imports = [
    # Base home config
    ../../modules/home/base.nix

    # HyDE-specific modules
    inputs.hydenix.homeModules.default
    ../../modules/home/linux.nix
    ../../modules/home/applications.nix
    ../../modules/home/mpv.nix
    ../../modules/home/hydenix.nix
    ../../modules/home/dunst.nix

    # GNOME specific settings
    ../../modules/home/dconf.nix
  ];
}
