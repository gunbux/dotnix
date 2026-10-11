{
  inputs,
  lib,
  ...
}: let
  localPlugins = ["auto-archive" "auto-label" "cloud-agents"];
  # Third-party plugins pinned as flake inputs; bump with `nix flake update <input>`.
  externalPlugins = {paseo-bots = inputs.paseo-bots;};
  pluginSource = src:
    lib.cleanSourceWith {
      inherit src;
      filter = path: type: let
        file = baseNameOf path;
      in
        !(builtins.elem file ["node_modules" "tests" ".gitignore" "package-lock.json"]);
    };
  linkPlugin = name: src:
    lib.nameValuePair ".local/share/paseo/plugins/${name}" {source = pluginSource src;};
in {
  # Source is declarative; plugin data, settings, and registration remain daemon-owned.
  # Register a new plugin once with `paseo plugin install ~/.local/share/paseo/plugins/<name>`.
  home.file =
    lib.listToAttrs (map (name: linkPlugin name (../../config/paseo/plugins + "/${name}")) localPlugins)
    // lib.mapAttrs' linkPlugin externalPlugins;
}
