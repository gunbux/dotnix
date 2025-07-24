# Lazy/Neovim Configs
{...}: {
  # Neovim Configs
  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };

  # LazyVim Config
  home.file.".config/nvim" = {
    source = ../../config/lazyvim;
    recursive = true;
  };
}
