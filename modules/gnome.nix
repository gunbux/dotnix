{ config, pkgs, ... }:
{
  # Enable GDM
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.displayManager.gdm.wayland = true;
  programs.dconf.enable = true;

  # Gnome Settings
  environment.gnome.excludePackages = (with pkgs; [
    gnome-tour
    gnome.gnome-characters
    gnome.yelp
  ]) ++ (with pkgs.gnome; [
    gnome-music
    gnome-contacts
    # gnome-terminal
  ]);

  services.xserver.desktopManager.gnome = {
    enable = true;
    extraGSettingsOverridePackages = [ pkgs.gnome.mutter ];
    extraGSettingsOverrides = ''
     [org.gnome.mutter]
     experimental-features=['scale-monitor-framebuffer']
    '';
  };

  # Enable GNOME Keyring daemon
  # services.gnome3.gnome-keyring.enable = true;
  # Enable Chrome GNOME Shell native host connector
  # This is a DBus service allowing to install GNOME Shell extensions from a web browser.
  # services.gnome3.chrome-gnome-shell.enable = tr
}
