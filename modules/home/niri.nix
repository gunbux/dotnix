{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./noctalia.nix
    ./vicinae.nix
    ./glance.nix
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

  # adw-gtk3 is the base Noctalia's gtk3/gtk4 templates recolor. Each gtk.css
  # imports noctalia.css first: Noctalia's apply.sh leaves a gtk.css that
  # already has the import alone, so it never replaces these HM symlinks.
  gtk = {
    enable = true;
    colorScheme = "dark";
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    gtk3.extraCss = ''
      @import url("noctalia.css");
    '';
    gtk4.theme = null;
    gtk4.extraCss = ''
      @import url("noctalia.css");
    '';
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    font = {
      name = "Source Sans Pro";
      size = 11;
    };
  };

  # Fusion recolored by the palette Noctalia's qt template renders.
  qt = {
    enable = true;
    platformTheme.name = "qtct";
    qt5ctSettings.Appearance = {
      style = "Fusion";
      custom_palette = true;
      color_scheme_path = "${config.xdg.configHome}/qt5ct/colors/noctalia.conf";
      icon_theme = "Papirus-Dark";
      standard_dialogs = "xdgdesktopportal";
    };
    qt6ctSettings.Appearance = {
      style = "Fusion";
      custom_palette = true;
      color_scheme_path = "${config.xdg.configHome}/qt6ct/colors/noctalia.conf";
      icon_theme = "Papirus-Dark";
      standard_dialogs = "xdgdesktopportal";
    };
  };

  # Niri Config
  home.file.".config/niri" = {
    source = ../../config/niri;
    recursive = true;
  };
}
