{pkgs, ...}: {
  programs.niri.enable = true;

  # Use COSMIC Files for the Open/Save file picker dialog under niri instead
  # of the GNOME/GTK portal default (looks like Nautilus).
  xdg.portal.config.niri."org.freedesktop.impl.portal.FileChooser" = ["cosmic"];
}
