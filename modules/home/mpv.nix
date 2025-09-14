{pkgs, ...}: {
  programs.mpv = {
    enable = true;

    package = (
      pkgs.mpv-unwrapped.wrapper {
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

        mpv = pkgs.mpv-unwrapped.override {
          waylandSupport = true;
        };
      }
    );
  };

  ## Config Files
  home.file.".config/mpv" = {
    source = ../../config/mpv;
    recursive = true;
  };
}
