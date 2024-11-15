{ config, pkgs, lib, ... }:
{
  # Enable GDM
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.displayManager.gdm.wayland = true;
  services.displayManager.autoLogin = {
    enable = true;
    user = "chun";
  };
  programs.dconf.enable = true;

  # Gnome Settings
  environment.gnome.excludePackages = (with pkgs; [
    yelp
    gnome-tour
    gnome-characters
    gnome-music
    gnome-contacts
  ]);

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
  # security.pam.services.sddm.enableGnomeKeyring = false;
  # Enable Chrome GNOME Shell native host connector
  # This is a DBus service allowing to install GNOME Shell extensions from a web browser.
  # services.gnome3.chrome-gnome-shell.enable = tr
}
