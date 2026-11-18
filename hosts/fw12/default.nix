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
    wifi.powersave = true;
  };

  # Keep the RTC in UTC. No Windows on this machine, and a local-time RTC is
  # never updated by timesyncd, so it drifts by whole time-zone offsets when
  # tzupdate changes zones while traveling.
  time.hardwareClockInLocalTime = lib.mkForce false;

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
    # Shows in Steam as "GE-Proton"; tracks the nixpkgs pin.
    extraCompatPackages = [pkgs.proton-ge-bin];
  };

  programs.gamemode.enable = true;
  # NT sync primitives in the kernel. Proton uses /dev/ntsync when it exists,
  # instead of emulating Windows sync objects in wineserver.
  boot.kernelModules = ["ntsync"];

  # Same game memory floor as legion-nix. Steam runs each game in an
  # app-steam-app<ID>-<pid>.scope; the kernel never reclaims its first 8G and
  # swaps other apps instead. The iGPU uses system RAM too, so 8G of 16G is
  # the floor, not more. Every parent cgroup needs the floor for it to apply.
  systemd.slices."user".sliceConfig.MemoryMin = "8G";
  systemd.slices."user-" = {
    overrideStrategy = "asDropin";
    sliceConfig.MemoryMin = "8G";
  };
  systemd.services."user@".serviceConfig.MemoryMin = "8G";
  systemd.user.slices."app".sliceConfig.MemoryMin = "8G";
  systemd.user.units."app-steam-.scope" = {
    overrideStrategy = "asDropin";
    text = "[Scope]\nMemoryMin=8G\n";
  };
  # With a hard floor, the kernel OOM killer would pick the biggest process:
  # the game. systemd-oomd acts first, at 90% swap, and kills the cgroup with
  # the most swap. Swap only: the pressure trigger could pick a stuttering game.
  systemd.slices."-".sliceConfig.ManagedOOMSwap = "kill";

  # sched_ext: scx_lavd in its auto mode, which picks power or performance
  # itself. Recommended by the Deadlock Linux guide for better 1% lows.
  services.scx-loader = {
    enable = true;
    config.default_sched = "scx_lavd";
  };

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
