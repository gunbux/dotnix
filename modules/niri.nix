{pkgs, ...}: {
  programs.niri.enable = true;

  # Use COSMIC Files for the Open/Save file picker dialog under niri instead
  # of the GNOME/GTK portal default (looks like Nautilus).
  xdg.portal.config.niri."org.freedesktop.impl.portal.FileChooser" = ["cosmic"];

  # The GNOME portal advertises GlobalShortcuts under niri but can't bind any
  # (no GNOME Shell), so Hex waits on it forever. Without the interface, Hex
  # follows `hex dictation` commands bound in config/niri/binds.kdl.
  xdg.portal.config.niri."org.freedesktop.impl.portal.GlobalShortcuts" = ["none"];
}
