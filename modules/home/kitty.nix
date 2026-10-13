{
  lib,
  pkgs,
  ...
}: {
  home.file.".config/kitty/kitty.conf" = lib.mkForce {
    # macOS gets extra bindings that avoid PaperWM's Option hotkeys.
    text =
      builtins.readFile ../../config/kitty/kitty.conf
      + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ("\n" + builtins.readFile ../../config/kitty/macos.conf);
    force = true;
  };
}
