# Nix OS Configs
# TODO:
# Switch to unstable
# Add power management
# Add font configs
# Add Pipewire configs
# Add btrfs configs
# Add secure boot support with lanzaboote
{ config, pkgs, ...}:

{
  imports = [
    # Include the results of the hardware scan.
    /etc/nixos/hardware-configuration.nix

    # Include host specific configs
    ./hosts/g14/default.nix

    # Include modular configs here
    ./modules/gnome.nix
    ./modules/fonts.nix

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
  services.xserver.enable = true;
  services.xserver.layout = "us";
  services.xserver.xkbOptions = "ctrl:nocaps";
  services.xserver.libinput.enable = true;

  # Services
  services.openssh.enable = true;
  services.printing.enable = true;
  services.udisks2.enable = true;
  security.sudo.enable = true;
  # security.sudo.wheelNeedsPassword = false;

  # The NixOS release to be compatible with for stateful data such as databases
  system.stateVersion = "23.05";
  system.autoUpgrade = {
    enable = true;
    channel = "https://channels.nixos.org/nixos-unstable";
  };

  # Docker
  virtualisation.docker.enable = true;

  # User
  users.users.chun = {
    isNormalUser = true;
    initialPassword = "NixOS!";
    uid = 1000;
    home = "/home/chun";
    description = "Chun Yu";
    extraGroups = [ "wheel" "networkmanager" "docker" "audio" "video" "input" "disk" ];
  };

  # Some default programs to be installed in system profile
  environment.systemPackages = with pkgs; [
    home-manager
    vim
    firefox
  ];
}
