# Lazy/Neovim Configs
{...}: {
  # Neovim Configs
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    # Keep legacy defaults (home.stateVersion < 26.05) to silence eval warnings
    withRuby = true;
    withPython3 = true;
  };

  # LazyVim Config
  home.file.".config/nvim" = {
    source = ../../config/lazyvim;
    recursive = true;
  };
}
