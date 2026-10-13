# Git Configuration
# TODO: Add signing
{pkgs, ...}: {
  home.packages = with pkgs; [
    gh
    git
    git-filter-repo
    lazygit
  ];
  # Git Configs
  programs.git.settings = {
    enable = true;
    aliases = {lola = "log --graph --decorate --pretty=oneline --abbrev-commit --all";};
    userName = "Chun Yu";
    userEmail = "lamchunyu00@gmail.com";
  };

  # Global gitignore (git reads ~/.config/git/ignore when core.excludesFile is unset)
  xdg.configFile."git/ignore".text = ''
    .wakatime-project
  '';

  # Delta
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };

  # LazyGit Config
  home.file.".config/lazygit/config.yml" = {
    source = ../../config/lazygit/config.yml;
  };
}
