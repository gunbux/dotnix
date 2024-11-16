# Nix OS Configs
# TODO:
# Add secure boot support with lanzaboote
{ config, pkgs, lib, inputs, options, ... }:

{
  imports = [
    # Include the results of the hardware scan.
    # /etc/nixos/hardware-configuration.nix

    # Include host specific configs
    # ./hosts/g14/default.nix
    # ./hosts/legion/default.nix

    # Include modular configs here
    ./modules/gnome.nix
    # ./modules/hyprland.nix
    ./modules/fonts.nix
    # ./modules/wireguard.nix
  ];

  nixpkgs.config.allowUnfree = true;

  # Audio Settings
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
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

  # GPG
  programs.gnupg.agent = {
     enable = true;
     enableSSHSupport = true;
  };

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

  # Enable automatic system upgrades
  system.autoUpgrade = {
    enable = true;
    flake = "github:gunbux/dotnix";
    flags = [
      "--update-input" "nixpkgs"
      "-L" # Print build logs
    ];
    dates = "daily";
    randomizedDelaySec = "45min";
    allowReboot = false;
  };

  # Nix Settings
  nix = {
    gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 3d";
      persistent = true;
      randomizedDelaySec = "45min";
    };

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
      allowed-users = ["@wheel"];
      trusted-users = ["@wheel"];
      sandbox = true;
      max-jobs = "auto";
      keep-going = true;
      log-lines = 20;
      experimental-features = [
        "flakes"
        "nix-command"
        "recursive-nix"
        "ca-derivations"
      ];
      keep-derivations = true;
      keep-outputs = true;
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://nixpkgs-unfree.cachix.org"
        "https://hyprland.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
    };

    optimise = {
      automatic = true;
      dates = [ "weekly" ];
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
    extraGroups = [ "wheel" "networkmanager" "docker" "audio" "video" "input" "disk" "syncthing" "dialout"];
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
