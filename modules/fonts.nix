{ config, pkgs, ...}:
{
  fonts = {
    fontDir.enable = true;
    fonts = with pkgs; [
      jetbrains-mono
      source-sans-pro
      source-serif-pro
    ];

    fontconfig = {
      enable = true;
      defaultFonts = {
        monospace = [ "JetBrains Mono" ];
        sansSerif = [ "Source Sans Pro" ];
        serif = [ "Source Serif Pro" ];
      };
    };
  };
}
