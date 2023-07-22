# TODO:
# Switch to cherry picked zen kernel
# asus-nb-wmi power consumption
{config, pkgs, ... }:
{
  # Networking
  networking.hostName = "chun-lappy";

  # Kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [
    "initcall_blacklist=acpi_cpufreq_init"
    "amd_pstate=active" # Enables amd_pstate_epp I believe?
  ];

  boot.kernelModules = [ "amd-pstate" ];

  # Power Mangement
  powerManagement = {
    enable = true;
    powertop.enable = true;
  };
  services.auto-cpufreq = {
    enable = true;
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
