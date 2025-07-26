# WSL-specific nix configs
{pkgs, ...}: {
  imports = [
    ./syncthing.nix
  ];

  networking.hostName = "wsl";
  system.stateVersion = "24.11";
  wsl.enable = true;
  wsl.defaultUser = "chun";
  programs.zsh.enable = true;
  users.users.chun = {
    isNormalUser = true;
    uid = 1000;
    home = "/home/chun";
    description = "Chun Yu";
    extraGroups = ["wheel" "networkmanager" "docker" "audio" "video" "input" "disk" "syncthing" "dialout"];
    shell = pkgs.zsh;
  };
  environment.systemPackages = with pkgs; [
    pokego
  ];
}
