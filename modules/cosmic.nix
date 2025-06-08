{
  config,
  pkgs,
  lib,
  ...
}: {
  # Enable COSMIC desktop environment
  services.desktopManager.cosmic.enable = true;
  # services.displayManager.cosmic-greeter.enable = true;
}
