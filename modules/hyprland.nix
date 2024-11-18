{ config, pkgs, lib, ... }:
{
  imports = [
    # ./greetd.nix
  ];

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
    fuzzel
    pamixer # Audio control
    grim # Screenshot
    slurp # Screen selection
    
    # Lock screen and color picker
    hyprlock
    hyprpicker
    
    # System utilities
    nordzy-cursor-theme
    gnome-control-center
    wl-clip-persist
    nautilus
    tesseract
  ];
}

