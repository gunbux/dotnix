{...}: {
  home.file.".config/tmux" = {
    source = ../../config/tmux;
    recursive = true;
  };
}
