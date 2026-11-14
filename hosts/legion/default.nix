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
    ./hardware-configuration.nix
    inputs.nixos-hardware.nixosModules.lenovo-legion-15arh05h
    inputs.home-manager.nixosModules.home-manager
  ];

  # Swap
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 16 * 1024;
    }
  ];

  # Keep swapped-out pages compressed in RAM before they reach the swap file,
  # so a game's memory comes back from RAM, not disk, after a big build.
  boot.zswap = {
    enable = true;
    compressor = "zstd";
    maxPoolPercent = 25;
    shrinkerEnabled = true;
  };

  # Builds give up memory before the desktop does (14 GB of RAM). Past this,
  # the kernel reclaims build memory first; builds slow down, games don't.
  systemd.services.nix-daemon.serviceConfig.MemoryHigh = "6G";

  # Steam runs each game in an app-steam-app<ID>-<pid>.scope. When RAM runs
  # out, the kernel swaps other apps before a game's first 8G, and kills
  # nothing. A cgroup only gets this protection if every parent has it too.
  systemd.slices."user".sliceConfig.MemoryLow = "8G";
  systemd.slices."user-" = {
    overrideStrategy = "asDropin";
    sliceConfig.MemoryLow = "8G";
  };
  systemd.services."user@".serviceConfig.MemoryLow = "8G";
  systemd.user.slices."app".sliceConfig.MemoryLow = "8G";
  systemd.user.units."app-steam-.scope" = {
    overrideStrategy = "asDropin";
    text = "[Scope]\nMemoryLow=8G\n";
  };

  # sched_ext: scx_lavd in its auto mode, which picks power or performance
  # itself. Recommended by the Deadlock Linux guide for better 1% lows.
  services.scx-loader = {
    enable = true;
    config.default_sched = "scx_lavd";
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
  # gamemoded needs this group to switch the CPU governor through polkit.
  users.users.chun.extraGroups = ["gamemode"];

  programs.gamescope = {
    enable = true;
    capSysNice = false;
  };

  # Logitech
  hardware.logitech.wireless.enable = true;
  programs.solaar.enable = true;

  # Power Mangement
  # We remove power-profiles-daemon because it clashes with powerManagement, I think.
  powerManagement = {
    enable = true;
    # NOTE: `powertop --auto-tune` writes power/control=auto to *every* USB
    # device, which runtime-suspends the mouse receiver and keyboards. The
    # first input after an idle stretch then has to resume the whole chain
    # (device -> hub -> xHCI root hub -> PCI controller out of D3), which is
    # perceptible as input latency. Left off deliberately.
    powertop.enable = false;
  };

  # Keep USB HID devices out of runtime suspend. Matches any USB interface
  # claiming HID class (bInterfaceClass == 03) and pins power/control on its
  # parent usb_device, since power/control lives on the device, not the
  # interface. Fires on hotplug, e.g. replugging a wireless receiver.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_interface", ATTR{bInterfaceClass}=="03", RUN+="/bin/sh -c 'echo on > /sys%p/../power/control'"
  '';
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

  # Dynamic Linking for non nix programs
  programs.nix-ld.enable = true;

  # NOTE: VirtualBox tends to cause recompilations of the kernel, enable only where neccessary.
  # Virtualization
  # virtualisation.virtualbox.host.enable = true;
  # users.extraGroups.vboxusers.members = ["chun"];
}
