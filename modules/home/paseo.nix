{lib, ...}: let
  plugins = ["auto-label" "cloud-agents"];
  pluginSource = name:
    lib.cleanSourceWith {
      src = ../../config/paseo/plugins + "/${name}";
      filter = path: type: let
        file = baseNameOf path;
      in
        !(builtins.elem file ["node_modules" "tests" ".gitignore" "package-lock.json"]);
    };
in {
  # Source is declarative; plugin data, settings, and registration remain daemon-owned.
  home.file = lib.listToAttrs (map (name:
    lib.nameValuePair ".local/share/paseo/plugins/${name}" {source = pluginSource name;})
  plugins);
}
