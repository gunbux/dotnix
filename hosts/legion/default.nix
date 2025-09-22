# Legion 5 (2021) nixosModule
# This provides sane configuration for anyone using a Legion 15.
# Just remember to change personal stuff like hostname and timezones.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ../../base.nix
    ../../nixos_modules/scx-loader
    ./hardware-configuration.nix
    inputs.nixos-hardware.nixosModules.lenovo-legion-15arh05h
    inputs.home-manager.nixosModules.home-manager
    inputs.hydenix.lib.nixOsModules
  ];

  hydenix = {
    enable = true;
    hostname = "legion-nix";
    timezone = "Asia/Singapore";
    locale = "en_US.UTF-8";
    sddm.enable = false;
  };

  # Swap
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 16 * 1024;
    }
  ];

  # scx
  services.scx-loader = {
    enable = true;
    default_sched = "scx_lavd";
    scheduler_config = ''
      [scheds.scx_lavd]
      auto_mode = []
      gaming_mode = ["--performance"]
      lowlatency_mode = ["--performance"]
      powersave_mode = ["--powersave"]
      server_mode = []
    '';
  };

  # Networking
  networking.hostName = "legion-nix";
  networking.networkmanager = {
    enable = true;
    wifi.powersave = true;
  };

  # Kernel
  # NOTE: A lot of the kernel configs that I used to care about are now all in nixos-hardware (amd-pstate, amdgpu initrd).
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;

  # NTFS Support
  boot.supportedFilesystems = ["ntfs"];

  # Hardware Acceleration
  hardware.graphics = {
    enable = true;
  };

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
  };

  # Power Mangement
  # We remove power-profiles-daemon because it clashes with powerManagement, I think.
  powerManagement = {
    enable = true;
    powertop.enable = true;
  };
  services.auto-cpufreq = {
    enable = true;
  };
  services.power-profiles-daemon.enable = false; # Defaults to true in Gnome 44

  # Sensible defaults
  environment.systemPackages = with pkgs; [
    brightnessctl
  ];
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Virtualization
  virtualisation.virtualbox.host.enable = true;
  users.extraGroups.vboxusers.members = ["chun"];
}
