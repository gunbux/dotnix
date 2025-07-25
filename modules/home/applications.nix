# Userspace Applications and GUIs
{
  pkgs,
  lib,
  inputs,
  ...
}: {
  home.packages = with pkgs;
    [
      # NOTE: Build failure, remove comments when resolved
      # jetbrains.clion
      # jetbrains.goland
      # jetbrains.idea-ultimate
      # jetbrains.pycharm-professional
      # jetbrains.rust-rover
      # jetbrains.webstorm
      # terminal-typeracer
      # zed-editor
      apostrophe # Markdown Editor
      bitwarden # Password Manager
      blender # Blender
      code-cursor # Cursor
      davinci-resolve # Video Editor
      discord # Discord
      evince # PDF
      ghostty # Terminal
      glow # Markdown Viewer
      kitty # Terminal
      mpv # Video Player
      musescore # Musescore
      neomutt # Email Client
      obs-studio # Recording
      prismlauncher # Minecraft
      postman # Postman
      qbittorrent # Torrent
      solaar # Mouse Utilities
      spotify # Music
      steam # Games
      tailscale # VPN/Wireguard
      telegram-desktop # Telegram
      thunderbird # Email Client
      vivaldi # Browser
      yazi # File Manager
      youtube-music # Music
      yt-dlp # Downloader
    ]
    ++ [
      inputs.zen-browser.packages.${pkgs.system}.default
      inputs.quickshell.packages.${pkgs.system}.default
    ];

  # Ghostty Config
  home.file.".config/ghostty/config" = {
    source = ../../config/ghostty/config;
    force = true;
  };

  # Defaults for browser
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      # Web
      "text/html" = lib.mkForce ["zen-beta.desktop"];
      "x-scheme-handler/http" = lib.mkForce ["zen-beta.desktop"];
      "x-scheme-handler/https" = lib.mkForce ["zen-beta.desktop"];
      "x-scheme-handler/chrome" = lib.mkForce ["zen-beta.desktop"];
      "application/x-extension-htm" = lib.mkForce ["zen-beta.desktop"];
      "application/x-extension-html" = lib.mkForce ["zen-beta.desktop"];
      "application/x-extension-shtml" = lib.mkForce ["zen-beta.desktop"];
      "application/xhtml+xml" = lib.mkForce ["zen-beta.desktop"];
      "application/x-extension-xhtml" = lib.mkForce ["zen-beta.desktop"];
      "application/x-extension-xht" = lib.mkForce ["zen-beta.desktop"];
    };
  };
}
