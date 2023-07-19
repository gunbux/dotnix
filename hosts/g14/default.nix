# TODO:
# Switch to cherry picked zen kernel
{config, pkgs, ... }:
{
  # Networking
  networking.hostName = "chun-lappy";

  # Kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Power Mangement
  powerManagement = {
    enable = true;
    powertop.enable = true;
  };

  # Services
  services.upower.enable = true;

  environment.systemPackages = with pkgs; [
    brightnessctl
  ];
  hardware.bluetooth.enable = true;
}
