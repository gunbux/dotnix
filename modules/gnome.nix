{ config, pkgs, ... }:
{
  # Enable GDM
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.displayManager.gdm.wayland = true;

  # Gnome Settings
  services.xserver.desktopManager.gnome = {
    enable = true;
    extraGSettingsOverridePackages = [ pkgs.gnome.mutter ];
    extraGSettingsOverrides = ''
     [org.gnome.mutter]
     experimental-features=['scale-monitor-framebuffer']
     [ org/gnome/desktop/peripherals/mouse ]
      natural-scroll=true

     [org.gnome.desktop.peripherals.touchpad]
     click-method='default'

     [org/gnome/shell]
     disable-user-extensions=false
    '';
  };

  # Enable GNOME Keyring daemon
  # services.gnome3.gnome-keyring.enable = true;
  # Enable Chrome GNOME Shell native host connector
  # This is a DBus service allowing to install GNOME Shell extensions from a web browser.
  # services.gnome3.chrome-gnome-shell.enable = tr
}
