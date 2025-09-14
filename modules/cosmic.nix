{
  config,
  pkgs,
  lib,
  ...
}: {
  # Enable COSMIC desktop environment
  services.displayManager.cosmic-greeter.enable = true;
  services.desktopManager.cosmic.enable = true;
}
