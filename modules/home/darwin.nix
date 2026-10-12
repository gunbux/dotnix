# macOS-specific home configuration
# GUI apps are installed as Homebrew casks by the nix-darwin host config.
{...}: {
  # Ghostty Config
  home.file.".config/ghostty" = {
    source = ../../config/ghostty;
    recursive = true;
    force = true;
  };
}
