{
  config,
  lib,
  pkgs,
  ...
}: let
  # Eevee Chunky Cursor is paid, so it stays out of this public repo. Unzip its
  # Linux theme to ~/.local/share/icons/scm-eevee-c16f477d by hand. Activation
  # points chun-cursor at it, or at Banana when it is missing.
  eeveeTheme = "${config.xdg.dataHome}/icons/scm-eevee-c16f477d";
  bananaTheme = "${pkgs.banana-cursor-dreams}/share/icons/Banana-Catppuccin-Mocha";
  cursorLink = "${config.xdg.stateHome}/chun-cursor";
  chunCursor = pkgs.runCommand "chun-cursor" {} ''
    mkdir -p $out/share/icons
    ln -s ${lib.escapeShellArg cursorLink} $out/share/icons/chun-cursor
  '';
in {
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

  # Eevee when installed, otherwise Banana (see the let block)
  home.pointerCursor = {
    enable = true;
    x11.enable = true;
    gtk.enable = true;
    package = chunCursor;
    size = 64;
    name = "chun-cursor";
  };

  home.activation.selectCursorTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ -f ${lib.escapeShellArg eeveeTheme}/index.theme ]; then
      cursorSource=${lib.escapeShellArg eeveeTheme}
    else
      cursorSource=${lib.escapeShellArg bananaTheme}
    fi
    run mkdir -p ${lib.escapeShellArg (dirOf cursorLink)}
    run ln -sfn "$cursorSource" ${lib.escapeShellArg cursorLink}
  '';

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
