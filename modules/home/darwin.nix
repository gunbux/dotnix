# macOS-specific home configuration
# Desktop services live here; other GUI apps use the host's Homebrew casks.
{pkgs, ...}: {
  imports = [./darwin-desktop.nix];

  # No Homebrew cask exists; the Nix package is the signed release bundle
  # (modules/home/capy.nix).
  capy.app.enable = true;

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
