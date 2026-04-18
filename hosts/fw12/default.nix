{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ../../base.nix
    ./hardware-configuration.nix
    inputs.nixos-hardware.nixosModules.framework-12-13th-gen-intel
    inputs.home-manager.nixosModules.home-manager
  ];

  # Swap
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 16 * 1024;
    }
  ];

  # Networking
  networking.hostName = "fw12";
  networking.networkmanager = {
    enable = true;
    wifi.powersave = true;
  };

  # Kernel
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;

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

  # Steam/Gaming Configs
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    gamescopeSession.enable = true;
  };

  programs.gamescope = {
    enable = true;
    capSysNice = false;
  };

  # Logitech
  hardware.logitech.wireless = {
    enable = true;
    enableGraphical = true;
  };

  # Services
  services.upower.enable = true;
  environment.systemPackages = with pkgs; [
    brightnessctl
    mangohud
  ];

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experiemental = true;
        KernelExperiemental = true;
      };
    };
  };
}
