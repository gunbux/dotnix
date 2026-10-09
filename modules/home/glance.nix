{inputs, ...}: {
  # Screenshots, OCR and ask-about-screen (github.com/gunbux/glance). Binds are in
  # config/niri/binds.kdl; the Vicinae extension comes with programs.vicinae.
  imports = [inputs.glance.homeManagerModules.default];

  programs.glance.enable = true;
}
