# nixpkgs ships 0.10.2; plugins here require >=0.10.3, matching paseo-desktop.
{
  fetchFromGitHub,
  fetchNpmDeps,
  paseo,
}:
paseo.overrideAttrs (finalAttrs: _: {
  version = "0.10.3";

  src = fetchFromGitHub {
    owner = "getpaseo";
    repo = "paseo";
    tag = "v${finalAttrs.version}";
    hash = "sha256-yI/H8XPC0lLdmokePJ4qyVxaV+/PsgePzQupumm5LPQ=";
  };

  npmDeps = fetchNpmDeps {
    name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
    inherit (finalAttrs) src;
    hash = "sha256-uG7EkoQMVLk5CzDEbJbR5aPxeq59x4vjF21JGatxD7k=";
  };

  # node-pty's build config records the npm cache and python paths, pulling
  # ~2.7 GiB of build inputs into the runtime closure.
  postInstall = ''
    rm $out/lib/paseo/packages/server/node_modules/node-pty/build/config.gypi
  '';
})
