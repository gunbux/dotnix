{ config, pkgs, lib, ... }:
{
  # Enable Hyprland
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # Enable XDG Portal
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
  };

  # Required services for proper Hyprland functionality
  services = {
    # Authentication agent
    gnome.gnome-keyring.enable = true;

    # Display manager
    greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd Hyprland";
          user = "greeter";
        };
      };
    };
  };
  
  # Session variables
  environment.variables = {
    NIXOS_OZONE_WL = "1";
  };

  # System packages needed for Hyprland
  environment.systemPackages = with pkgs; [
    # Status bar
    waybar

    # Notifications
    dunst
    libnotify

    # Wallpaper
    swww

    # Launcher
    rofi-wayland
    wl-clipboard
    wlr-randr
    brightnessctl
    pamixer # Audio control
    grim # Screenshot
    slurp # Screen selection
  ];
}

