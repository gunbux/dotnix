{inputs, ...}: {
  programs.dank-material-shell.enable = true;

  # Niri Config
  home.file.".config/niri" = {
    source = ../../config/niri;
    recursive = true;
  };
}
