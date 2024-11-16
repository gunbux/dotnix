# TODO:
# Switch to cherry picked zen kernel
# asus-nb-wmi power consumption
{config, pkgs, ... }:
{
  # Swap
   swapDevices = [ {
    device = "/var/lib/swapfile";
    size = 16*1024;
  } ];

  # Networking
  networking.hostName = "legion-nix";
  networking.networkmanager.wifi.powersave = true;

  # Kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [
    "initcall_blacklist=acpi_cpufreq_init"
    "amd_pstate=active"
  ];

  # Boot correct driver early
  boot.initrd.kernelModules = [ "amdgpu" ];
  boot.kernelModules = [ "amd-pstate" ];

  # NTFS Support
  boot.supportedFilesystems = [ "ntfs" ];

  # Hardware Acceleration
  hardware.graphics = {
    enable = true;
  };

  # Power Mangement
  powerManagement = {
    enable = true;
    powertop.enable = true;
  };

  # Auto CPU-Freq config
  services.auto-cpufreq = {
    enable = true;
  };

  # TLP Config, use one or the other but not both
  services.power-profiles-daemon.enable = false; # Defaults to true in Gnome 44
  # services.tlp = {
  #   enable = true;
  #   settings = {
  #     CPU_DRIVER_OPMODE_ON_AC="active";
  #     CPU_DRIVER_OPMODE_ON_BAT="active";
  #     CPU_SCALING_GOVERNOR_ON_AC="performance";
  #     CPU_SCALING_GOVERNOR_ON_BAT="powersave";
  #     CPU_ENERGY_PERF_POLICY_ON_AC="balance_performance";
  #     CPU_ENERGY_PERF_POLICY_ON_BAT="balance_power";
  #     CPU_MIN_PERF_ON_AC=0;
  #     CPU_MAX_PERF_ON_AC=100;
  #     CPU_MIN_PERF_ON_BAT=0;
  #     CPU_MAX_PERF_ON_BAT=30;
  #   };
  # };


  # Services
  services.upower.enable = true;

  environment.systemPackages = with pkgs; [
    brightnessctl
  ];
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = false;

  # Virtualization
  virtualisation.virtualbox.host.enable = true;
  users.extraGroups.vboxusers.members = [ "chun" ];
}
