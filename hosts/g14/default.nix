# TODO:
# Switch to cherry picked zen kernel
# asus-nb-wmi power consumption
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  # Override the supergfxd package
  nixpkgs.overlays = [
    (final: prev: {
      supergfxctl = prev.callPackage ../../pkgs/supergfxctl {};
    })
  ];

  imports = [
    ../../base.nix
    ./hardware-configuration.nix
    inputs.nixos-hardware.nixosModules.asus-zephyrus-ga402
    inputs.home-manager.nixosModules.home-manager
  ];

  # scx
  #services.scx.enable = true;

  # Swap
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 16 * 1024;
    }
  ];

  # Networking
  networking.hostName = "chun-lappy";
  networking.networkmanager = {
    enable = true;
    # wifi.powersave = true; # Powersave seems to kill connection for enterprise university wifi
  };

  # Kernel
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;
  boot.kernelParams = [
    "initcall_blacklist=acpi_cpufreq_init"
    "amd_pstate=active" # Enables amd_pstate_epp I believe?
  ];

  # Boot correct driver early
  boot.initrd.kernelModules = ["amdgpu"];

  boot.kernelModules = ["amd-pstate" "vboxdrv"];

  # NTFS Support
  boot.supportedFilesystems = ["ntfs"];

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

  # Steam Configs
  programs.steam = {
    enable = true;
  };

  # bcc
  # programs.bcc = {
  #   enable = true;
  # };

  # Logitech
  hardware.logitech.wireless = {
    enable = true;
    enableGraphical = true;
  };

  # Dynamic Linking for non nix programs
  # programs.nix-ld.enable = true;
  #   programs.nix-ld.libraries = with pkgs; [
  #     # Add any missing dynamic libraries for unpackaged programs
  #     # here, NOT in environment.systemPackages
  #   ];

  # Services
  services.upower.enable = true;
  services.supergfxd = {
    enable = true;
    settings = {
      hotplug_type = "Asus";
      # mode = "Hybrid";
    };
  };

  services.asusd.enable = true;
  services.asusd.enableUserService = true;

  environment.systemPackages = with pkgs; [
    brightnessctl
    # scx
  ];

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = lib.mkForce false;
    settings = {
      General = {
        Experiemental = true;
        KernelExperiemental = true;
      };
    };
  };

  # Virtualization
  virtualisation.virtualbox.host.enable = true;
  # virtualisation.virtualbox.guest.enable = true;
  # virtualisation.virtualbox.guest.x11 = true;
  users.extraGroups.vboxusers.members = ["chun"];
}
