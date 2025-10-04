# Userspace Applications and GUIs
{
  pkgs,
  lib,
  inputs,
  ...
}: {
  home.packages = with pkgs;
    [
      apostrophe # Markdown Editor
      audacity # Audio Editor
      bitwarden # Password Manager
      blender # Blender
      code-cursor # Cursor
      davinci-resolve # Video Editor
      discord # Discord
      evince # PDF
      gdtoolkit_4 # Godot Toolkit
      ghostty # Terminal
      glow # Markdown Viewer
      godot # Godot Game Engine
      jetbrains.clion # Jetbrains
      jetbrains.goland # Jetbrains
      jetbrains.idea-ultimate # Jetbrains
      jetbrains.pycharm-professional # Jetbrains
      jetbrains.rust-rover # Jetbrains
      jetbrains.webstorm # Jetbrains
      kitty # Terminal
      localsend # Global Airdrop
      loupe # GTK Image Viewer
      miraclecast # Open Source Miracast
      musescore # Musescore
      neomutt # Email Client
      obs-studio # Recording
      postman # Postman
      prismlauncher # Minecraft
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
      zed-editor # Zed
    ]
    ++ [
      inputs.zen-browser.packages.${pkgs.system}.default
      ## inputs.quickshell.packages.${pkgs.system}.default
    ];

  # Ghostty Config
  home.file.".config/ghostty/config" = {
    source = ../../config/ghostty/config;
    force = true;
  };

  # Defaults for applications
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

      # Terminal
      "application/x-terminal-emulator" = ["kitty.desktop"];
      "x-scheme-handler/terminal" = ["kitty.desktop"];

      # File Manager
      "inode/directory" = ["com.system76.CosmicFiles.desktop"];
      "x-scheme-handler/file" = ["com.system76.CosmicFiles.desktop"];
      "x-scheme-handler/about" = ["com.system76.CosmicFiles.desktop"];

      # Text
      "text/plain" = ["nvim.desktop"];

      # Image
      "image/x-jpeg" = ["loupe.desktop"];

      # Video
      "video/3gpp" = ["mpv.desktop"];
      "video/3gpp2" = ["mpv.desktop"];
      "video/annodex" = ["mpv.desktop"];
      "video/dv" = ["mpv.desktop"];
      "video/isivideo" = ["mpv.desktop"];
      "video/mj2" = ["mpv.desktop"];
      "video/mp2t" = ["mpv.desktop"];
      "video/mp4" = ["mpv.desktop"];
      "video/mpeg" = ["mpv.desktop"];
      "video/ogg" = ["mpv.desktop"];
      "video/quicktime" = ["mpv.desktop"];
      "video/vnd.avi" = ["mpv.desktop"];
      "video/vnd.mpegurl" = ["mpv.desktop"];
      "video/vnd.radgamettools.bink" = ["mpv.desktop"];
      "video/vnd.radgamettools.smacker" = ["mpv.desktop"];
      "video/vnd.rn-realvideo" = ["mpv.desktop"];
      "video/vnd.vivo" = ["mpv.desktop"];
      "video/vnd.youtube.yt" = ["mpv.desktop"];
      "video/wavelet" = ["mpv.desktop"];
      "video/webm" = ["mpv.desktop"];
      "video/x-anim" = ["mpv.desktop"];
      "video/x-flic" = ["mpv.desktop"];
      "video/x-flv" = ["mpv.desktop"];
      "video/x-javafx" = ["mpv.desktop"];
      "video/x-matroska" = ["mpv.desktop"];
      "video/x-matroska-3d" = ["mpv.desktop"];
      "video/x-mjpeg" = ["mpv.desktop"];
      "video/x-mng" = ["mpv.desktop"];
      "video/x-ms-wmv" = ["mpv.desktop"];
      "video/x-nsv" = ["mpv.desktop"];
      "video/x-ogm+ogg" = ["mpv.desktop"];
      "video/x-sgi-movie" = ["mpv.desktop"];
      "video/x-theora+ogg" = ["mpv.desktop"];
    };
  };
}
