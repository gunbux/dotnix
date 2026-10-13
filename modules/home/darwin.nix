# macOS-specific home configuration
# Desktop services live here; other GUI apps use the host's Homebrew casks.
{pkgs, ...}: {
  imports = [./darwin-desktop.nix];

  # The Darwin package wraps wg-quick with wireguard-go on PATH.
  # Keep VPN configs containing private keys outside the Nix store.
  home.packages = [pkgs.wireguard-tools];

  # Ghostty Config
  home.file.".config/ghostty" = {
    source = ../../config/ghostty;
    recursive = true;
    force = true;
  };
}
