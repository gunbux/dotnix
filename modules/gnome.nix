{ config, pkgs, ... }:
{
  # Enable Gnome
  services.xserver.enable = true;
  services.xserver.gdm.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gdm.wayland = true;

  # Gnome Settings
  services.xserver.desktopManager.gnome3 = {
    enable = true;
    # extraGSettingsOverrides = ''
    #   [ org/gnome/desktop/peripherals/mouse ]
    #   natural-scroll=true
    #
    #   [org.gnome.desktop.peripherals.touchpad]
    #   tap-to-click=true
    #   click-method='default'
    #   [org/gnome/shell]
    #   disable-user-extensions=false
    # '';
  };

  # Enable GNOME Keyring daemon
  # services.gnome3.gnome-keyring.enable = true;
  # Enable Chrome GNOME Shell native host connector
  # This is a DBus service allowing to install GNOME Shell extensions from a web browser.
  # services.gnome3.chrome-gnome-shell.enable = tr
}
