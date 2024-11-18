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
  
  # Session variables
  environment.variables = {
    NIXOS_OZONE_WL = "1";
    NIXPKGS_ALLOW_UNFREE = "1";
    XDG_CURRENT_DESKTOP = "Hyprland";
    XDG_SESSION_TYPE = "wayland";
    XDG_SESSION_DESKTOP = "Hyprland";
    GDK_BACKEND = "wayland";
    CLUTTER_BACKEND = "wayland";
    QT_QPA_PLATFORM = "wayland";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
    MOZ_ENABLE_WAYLAND = "1";
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

