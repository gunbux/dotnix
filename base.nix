# Nix OS Configs
# TODO:
# Add Pipewire configs
# Add btrfs configs
# Add secure boot support with lanzaboote
{ config, pkgs, lib, inputs, options, ... }:

{
  imports = [
    # Include the results of the hardware scan.
    /etc/nixos/hardware-configuration.nix

    # Include host specific configs
    ./hosts/g14/default.nix

    # Include modular configs here
    ./modules/gnome.nix
    ./modules/fonts.nix
    # ./modules/wireguard.nix

    # Home config
    ./home.nix
  ];

  nixpkgs.config.allowUnfree = true;

  # Audio Settings
  sound.enable = true;
  sound.mediaKeys.enable = true;
  hardware.pulseaudio = {
    enable = true;
    support32Bit = true;
  };

  # Boot Loader Settings
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Systemd Settings - Workaround to Gnome
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # Console Settings
  console = {
    font = "Lat2-Terminus16";
  };

  # Locale and Timezone
  i18n = {
    defaultLocale = "en_US.UTF-8";
  };
  time.timeZone = "Asia/Singapore";

  # Keyboard Settings
  services.libinput.enable = true;
  services.xserver.enable = true;
  services.xserver.xkb.layout = "us";
  services.xserver.xkb.options = "ctrl:nocaps";
  services.xserver.excludePackages = [ pkgs.xterm ];

  # Services
  services.openssh.enable = true;
  services.printing.enable = true;
  services.udisks2.enable = true;

  # For NFC
  services.pcscd.enable = true;

  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;

  services.syncthing = {
    enable = true;
    user = "chun";
    dataDir = "/home/chun/Documents";
    configDir = "/home/chun/.config/syncthing";
  };

  # For better shebang
  services.envfs.enable = true;

  # The NixOS release to be compatible with for stateful data such as databases
  system.stateVersion = "23.05";
  system.autoUpgrade = {
    enable = true;
    channel = "https://channels.nixos.org/nixos-unstable";
    flags = [
      "-I"
      "nixos-config=/home/chun/dotnix/base.nix"
    ];
  };

  # Nix Settings
  nix = {
    gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 3d";
    };

    # Flakes support
    settings.experimental-features = ["nix-command" "flakes" "recursive-nix"];

    # Modify this if using a different location
    nixPath = [ "nixos-config=/home/chun/dotnix/base.nix" ] ++ options.nix.nixPath.default;

    package = pkgs.nixVersions.latest;

    # Make builds run with low priority so my system stays responsive
    daemonCPUSchedPolicy = "idle";
    daemonIOSchedClass = "idle";

    # Free up to 1GiB whenever there is less than 100MiB left.
    extraOptions = ''
      keep-outputs = true
      warn-dirty = false
      keep-derivations = true
      min-free = ${toString (100 * 1024 * 1024)}
      max-free = ${toString (1024 * 1024 * 1024)}
    '';
    settings = {
      auto-optimise-store = true;
      # allow sudo users to mark the following values as trusted
      allowed-users = ["@wheel"];
      # only allow sudo users to manage the nix store
      trusted-users = ["@wheel"];
      sandbox = true;
      max-jobs = "auto";
      # continue building derivations if one fails
      keep-going = true;
      log-lines = 20;
      extra-experimental-features = ["flakes" "nix-command" "recursive-nix" "ca-derivations"];
    };
  };

  # Docker
  virtualisation.docker.enable = true;

  programs.zsh.enable = true;

  # User
  users.users.chun = {
    isNormalUser = true;
    initialPassword = "NixOS!";
    uid = 1000;
    home = "/home/chun";
    description = "Chun Yu";
    extraGroups = [ "wheel" "networkmanager" "docker" "audio" "video" "input" "disk" "syncthing" "docker" "dialout"];
    shell = pkgs.zsh;
  };

  # Some default programs to be installed in system profile
  environment.systemPackages = with pkgs; [
    home-manager
    vim
    firefox
    powertop
    zsh
  ];
}
