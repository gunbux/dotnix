# Base nix configs
# Common configurations across all machines go here.
# TODO: Eventually having secure boot support.
{
  config,
  pkgs,
  lib,
  inputs,
  options,
  ...
}: {
  imports = [
    ./modules/nix.nix
    ./modules/boot.nix
    ./modules/fonts.nix
    ./modules/syncthing.nix
  ];

  # Audio Settings
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Hardware Clock Sync
  time.hardwareClockInLocalTime = true;

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
  services.xserver.excludePackages = [pkgs.xterm];

  services.keyd = {
    enable = true;
    keyboards = {
      default = {
        ids = ["*"];
        settings = {
          main = {
            capslock = "escape";
            escape = "capslock";
          };
        };
      };
    };
  };

  # Services
  programs.mosh.enable = true;
  services.openssh.enable = true;
  services.printing.enable = true;
  services.udisks2.enable = true;

  # VPN
  services.tailscale.enable = true;

  # GPG
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;

  # For better shebang
  services.envfs.enable = true;

  # The NixOS release to be compatible with for stateful data such as databases
  system.stateVersion = lib.mkForce "23.05";

  # Enable automatic system upgrades
  system.autoUpgrade = {
    enable = true;
    flake = "github:gunbux/dotnix";
    flags = [
      "--update-input"
      "nixpkgs"
      "-L" # Print build logs
    ];
    dates = "daily";
    randomizedDelaySec = "45min";
    allowReboot = false;
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
    extraGroups = ["wheel" "networkmanager" "docker" "audio" "video" "input" "disk" "syncthing" "dialout"];
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
