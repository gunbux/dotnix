{inputs, ...}: {
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
