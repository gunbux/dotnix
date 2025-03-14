{
  config,
  pkgs,
  lib,
  ...
}: {
  # HyDE dunst configs
  home.file.".config/dunst/dunst.conf" = lib.mkForce {
    source = ../../config/dunst/dunst.conf;
    force = true;
    mutable = true;
  };
}
