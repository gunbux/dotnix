{
  paseo,
  fetchFromGitHub,
  fetchNpmDeps,
}:
# nixpkgs' plain-node CLI and daemon, bumped to match paseo-desktop until
# nixpkgs catches up. Drop this override once nixpkgs ships the same version.
paseo.overrideAttrs (finalAttrs: _: {
  version = "0.13.0";

  src = fetchFromGitHub {
    owner = "getpaseo";
    repo = "paseo";
    tag = "v${finalAttrs.version}";
    hash = "sha256-f3hXjwjenlXr8c8FmXMnz6PZ8QGyeyouJ/CtRwO8OdM=";
  };

  npmDeps = fetchNpmDeps {
    inherit (finalAttrs) src;
    name = "paseo-${finalAttrs.version}-npm-deps";
    hash = "sha256-DZOPOf81PkUxdD65BrfkTZhs6/DkfDWCFZ/SU+QrZbg=";
  };
})
