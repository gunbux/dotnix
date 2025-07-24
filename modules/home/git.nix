# Git Configuration
# TODO: Add signing
{pkgs, ...}: {
  home.packages = with pkgs; [
    git
    git-filter-repo
    lazygit
  ];
  # Git Configs
  programs.git = {
    enable = true;
    aliases = {lola = "log --graph --decorate --pretty=oneline --abbrev-commit --all";};
    delta.enable = true;
    userName = "Chun Yu";
    userEmail = "lamchunyu00@gmail.com";
  };

  # LazyGit Config
  home.file.".config/lazygit/config.yml" = {
    source = ../../config/lazygit/config.yml;
  };
}
