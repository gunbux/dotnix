# Kubernetes clients shared by every host.
{pkgs, ...}: {
  home.packages = with pkgs; [
    kubectl
    kubectx # kubectx + kubens
  ];

  programs.k9s.enable = true;

  # kubectl plugin: `k` alias, kubectl completion (also for `k`), and
  # shortcuts like kgp, kgd, kl, kex, kaf
  programs.zsh.oh-my-zsh.plugins = ["kubectl"];
}
