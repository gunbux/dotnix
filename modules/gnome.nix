{ config, pkgs, lib, ... }:
{
  # Enable GDM
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.displayManager.gdm.wayland = true;
  # services.displayManager.autoLogin = {
  #   enable = true;
  #   user = "chun";
  # };
  programs.dconf.enable = true;

  # Gnome Settings
  environment.gnome.excludePackages = (with pkgs; [
    yelp
    gnome-tour
    gnome-characters
    gnome-music
    gnome-contacts
  ]);

  # Add Gnome packages that were in home.nix
  environment.systemPackages = with pkgs; [
    # Gnome Dependencies
    tela-icon-theme
    pop-gtk-theme
    nordzy-cursor-theme

    # Gnome Extensions
    gnome-tweaks
    gnomeExtensions.blur-my-shell
    gnomeExtensions.vitals
    gnomeExtensions.supergfxctl-gex
    gnomeExtensions.user-avatar-in-quick-settings
    gnomeExtensions.just-perfection
    gnomeExtensions.space-bar
    gnomeExtensions.gsconnect
    gnomeExtensions.forge
    gnomeExtensions.unite
    gnomeExtensions.pano
  ];

  services.xserver.desktopManager.gnome = {
    enable = true;
    extraGSettingsOverridePackages = [ pkgs.mutter ];
    extraGSettingsOverrides = ''
     [org.gnome.mutter]
     experimental-features=['scale-monitor-framebuffer']
     # experimental-features=['scale-monitor-framebuffer', 'variable-refresh-rate']
    '';
  };

  # Enable GNOME Keyring daemon
  services.gnome.gnome-keyring.enable = lib.mkForce false;
}
