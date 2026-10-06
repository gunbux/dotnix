# Debian server (germaine) running a headless Paseo daemon.
{...}: {
  imports = [
    ../../modules/home/ai.nix
    ../../modules/home/paseo-daemon.nix
  ];

  targets.genericLinux.enable = true;

  programs.home-manager.enable = true;

  home = {
    username = "chunyu";
    homeDirectory = "/home/chunyu";
    stateVersion = "26.11";
  };
}
