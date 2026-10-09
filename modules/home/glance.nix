{
  inputs,
  lib,
  pkgs,
  ...
}: {
  # Screenshots, OCR and ask-about-screen (github.com/gunbux/glance). Binds are in
  # config/niri/binds.kdl; the Vicinae extension comes with programs.vicinae.
  imports = [inputs.glance.homeManagerModules.default];

  programs.glance = {
    enable = true;
    # Ask about screen through Paseo: any provider it runs, and chats that can be
    # continued later (from glance or Paseo). The label matches auto-archive's
    # quick chat labels (config/paseo/plugins/auto-archive).
    settings = {
      backend = "paseo";
      model = "opencode/openrouter/openrouter/free";
      paseoBridge = lib.getExe pkgs.paseo-bridge;
      paseoLabel = "Glance";
    };
  };
}
