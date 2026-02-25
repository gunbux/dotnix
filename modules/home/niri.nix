{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.noctalia.homeModules.default
  ];

  # Noctalia Shell
  programs.noctalia-shell.systemd = {
    enable = true;
  };

  programs.noctalia-shell = {
    enable = true;
  };

  services.kdeconnect.enable = true;

  ## Packages for plugins and stuff
  home.packages = with pkgs; [
    mpvpaper
    kdePackages.qttools
    xwayland-satellite
  ];

  # Banana Cursor
  home.pointerCursor = {
    x11.enable = true;
    gtk.enable = true;
    package = pkgs.banana-cursor-dreams;
    size = 48;
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
