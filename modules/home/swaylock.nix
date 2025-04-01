{
  config,
  pkgs,
  lib,
  ...
}: {
  # Install swaylock package
  home.packages = with pkgs; [
    swaylock
    swayidle
    swaylock-fancy
  ];

  # Swaylock Config
  home.file.".config/swaylock/config" = {
    source = lib.mkForce ../../config/swaylock/config;
    force = true;
    mutable = true;
  };
}
