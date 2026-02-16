{pkgs, ...}: {
  programs.mpv = {
    enable = true;

    package = pkgs.mpv.override {
      scripts = with pkgs.mpvScripts; [
        evafast
        memo
        mpv-webm
        quality-menu
        sponsorblock-minimal
        thumbfast
        uosc
        webtorrent-mpv-hook
      ];
    };
  };

  ## Config Files
  home.file.".config/mpv" = {
    source = ../../config/mpv;
    recursive = true;
  };
}
