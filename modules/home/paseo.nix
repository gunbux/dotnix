{lib, ...}: {
  # Source is declarative; plugin settings and registration remain daemon-owned.
  home.file.".local/share/paseo/plugins/auto-label".source = lib.cleanSourceWith {
    src = ../../config/paseo/plugins/auto-label;
    filter = path: type: let
      name = baseNameOf path;
    in
      !(builtins.elem name ["node_modules" "tests" ".gitignore" "package-lock.json"]);
  };
}
