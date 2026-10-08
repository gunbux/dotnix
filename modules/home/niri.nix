{pkgs, ...}: {
  imports = [
    ./noctalia.nix
    ./vicinae.nix
  ];

  ## Packages for plugins and stuff
  home.packages = with pkgs; [
    mpvpaper
    kdePackages.qttools
    xwayland-satellite
  ];

  # Banana Cursor
  home.pointerCursor = {
    enable = true;
    x11.enable = true;
    gtk.enable = true;
    package = pkgs.banana-cursor-dreams;
    size = 32;
    name = "Banana-Catppuccin-Mocha";
  };

  # Niri Config
  home.file.".config/niri" = {
    source = ../../config/niri;
    recursive = true;
  };
}
