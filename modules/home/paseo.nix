{lib, ...}: {
  # Source is declarative; group data and plugin registration remain daemon-owned.
  home.file.".local/share/paseo/plugins/thread-groups".source = lib.cleanSourceWith {
    src = ../../config/paseo/plugins/thread-groups;
    filter = path: type: let
      name = baseNameOf path;
    in
      !(builtins.elem name ["node_modules" "tests" ".gitignore" "package-lock.json"]);
  };
}
