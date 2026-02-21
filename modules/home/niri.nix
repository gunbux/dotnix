{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.noctalia.homeModules.default
  ];

  # Noctalia Shell Systemd Service
  programs.noctalia-shell.systemd = {
    enable = true;
  };

  programs.noctalia-shell = {
    enable = true;
  };

  home.pointerCursor = {
    x11.enable = true;
    gtk.enable = true;
    package = pkgs.banana-cursor-dreams;
    size = 128;
    name = "Banana-Catppuccin-Mocha";
  };

  # Niri Config
  home.file.".config/niri" = {
    source = ../../config/niri;
    recursive = true;
  };

  # Noctalia Config
  home.file.".config/noctalia" = {
    source = ../../config/noctalia;
    recursive = true;
  };
}
