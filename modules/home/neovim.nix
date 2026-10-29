# Lazy/Neovim Configs
{
  lib,
  pkgs,
  ...
}: {
  # Neovim Configs
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    # Keep legacy defaults (home.stateVersion < 26.05) to silence eval warnings
    withRuby = true;
    withPython3 = true;
    # Home Manager's provider bootstrap must run before our own LazyVim init.lua.
    sideloadInitLua = true;
    extraPackages =
      [pkgs.imagemagick pkgs.tectonic pkgs.mermaid-cli]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
        (pkgs.writeShellScriptBin "ghostty" ''
          exec /Applications/Ghostty.app/Contents/MacOS/ghostty "$@"
        '')
      ];
    # Nix's Mermaid package uses Chromium on Linux; use the installed Chrome on macOS.
    extraWrapperArgs = lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
      "--set-default"
      "PUPPETEER_EXECUTABLE_PATH"
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
      # CodeSnap's macOS binary links PCRE2 at a Homebrew path; let dyld find Nix's copy.
      "--prefix"
      "DYLD_FALLBACK_LIBRARY_PATH"
      ":"
      (lib.makeLibraryPath [pkgs.pcre2])
    ];
  };

  # LazyVim Config
  # lazy.nvim rewrites its lockfile, so leave it writable outside the store.
  home.file.".config/nvim" = {
    source = lib.cleanSourceWith {
      src = ../../config/lazyvim;
      filter = path: _type: baseNameOf path != "lazy-lock.json";
    };
    recursive = true;
  };
}
