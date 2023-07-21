# TODO:
# Switch to cherry picked zen kernel
# asus-nb-wmi power consumption
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
  services.supergfxd.enable = true;
  services.asusd.enable = true;
  services.asusd.enableUserService = true;

  environment.systemPackages = with pkgs; [
    brightnessctl
  ];
  hardware.bluetooth.enable = true;
}
