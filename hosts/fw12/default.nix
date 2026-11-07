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
    ../../modules/waydroid.nix
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
    # Wi-Fi power save delays inbound frames until the card wakes, and the
    # T3 Connect relay times out waiting for this host to answer.
    wifi.powersave = false;
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
    powertop = {
      enable = true;
      # powertop --auto-tune turns Wi-Fi power save back on; undo only that.
      postStart = ''
        for dev in /sys/class/net/*/wireless; do
          ${lib.getExe pkgs.iw} dev "$(basename "$(dirname "$dev")")" set power_save off || true
        done
      '';
    };
  };

  # Auto CPU-Freq config
  services.auto-cpufreq = {
    enable = true;
  };

  # TLP Config, use one or the other but not both
  services.power-profiles-daemon.enable = false; # Defaults to true in Gnome 44
  # nixos-hardware's laptop profile enables TLP, which defaults to Wi-Fi power
  # save on battery.
  services.tlp.settings = {
    WIFI_PWR_ON_AC = "off";
    WIFI_PWR_ON_BAT = "off";
  };

  # Steam/Gaming Configs
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    gamescopeSession.enable = true;
  };

  programs.gamemode.enable = true;

  programs.gamescope = {
    enable = true;
    capSysNice = false;
  };

  # Logitech
  hardware.logitech.wireless.enable = true;
  programs.solaar.enable = true;

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

  # Dynamic Linking for non nix programs
  programs.nix-ld.enable = true;
}
