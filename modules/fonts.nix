{ config, pkgs, ...}:
{
  fonts = {
    fontDir.enable = true;
    packages = with pkgs; [
      (nerdfonts.override { fonts = [ "JetBrainsMono" ]; })
      source-sans-pro
      source-serif-pro
    ];

    fontconfig = {
      enable = true;
      defaultFonts = {
        monospace = [ "JetBrainsMono" ];
        sansSerif = [ "Source Sans Pro" ];
        serif = [ "Source Serif Pro" ];
      };
    };
  };
}
