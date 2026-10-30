# Debian server (germaine) with shared agent CLI configuration.
{...}: {
  imports = [
    ../../modules/home/ai.nix
  ];

  targets.genericLinux.enable = true;

  programs.home-manager.enable = true;

  home = {
    username = "chunyu";
    homeDirectory = "/home/chunyu";
    stateVersion = "26.11";
  };
}
