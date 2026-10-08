{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.noctalia.homeModules.default
  ];

  # v5.2.1 only disables the old .nix path; newer Home Manager uses a directory.
  disabledModules = ["programs/noctalia"];

  # Native Noctalia v5. Settings can be managed through its settings window.
  programs.noctalia = {
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

  # Legacy v4 JSON settings remain in config/noctalia for reference.
  # v5 uses TOML and does not migrate v4 settings or plugins.
}
