{pkgs, lib, ...}: {
  programs.vscode = lib.mkForce {
    enable = false;
    extensions = [];
  };
}
