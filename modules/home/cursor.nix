# Pointer cursor. The chunky themes are paid and come from the private
# `cursors` input; Banana is public. Pick one per host with chun.cursor.theme.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.chun.cursor;
  themes = {
    eevee = {
      package = pkgs.chunky-cursors;
      name = "Eevee-Chunky";
    };
    poliwag = {
      package = pkgs.chunky-cursors;
      name = "Poliwag-Chunky";
    };
    mudkip = {
      package = pkgs.chunky-cursors;
      name = "Mudkip-Chunky";
    };
    banana = {
      package = pkgs.banana-cursor-dreams;
      name = "Banana-Catppuccin-Mocha";
    };
  };
in {
  options.chun.cursor = {
    theme = lib.mkOption {
      type = lib.types.enum (builtins.attrNames themes);
      default = "eevee";
      description = "Pointer cursor theme.";
    };
    size = lib.mkOption {
      type = lib.types.int;
      # The chunky themes are drawn for 64px or 128px.
      default =
        if cfg.theme == "banana"
        then 32
        else 64;
      description = "Pointer cursor size in pixels.";
    };
  };

  config.home.pointerCursor = {
    enable = true;
    x11.enable = true;
    gtk.enable = true;
    inherit (themes.${cfg.theme}) package name;
    inherit (cfg) size;
  };
}
