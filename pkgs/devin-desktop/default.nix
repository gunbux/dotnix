{
  lib,
  stdenv,
  fetchurl,
  upstreamDevin,
}: let
  sources = lib.importJSON ./sources.json;
  source = sources.${stdenv.hostPlatform.system};
in
  # Keep nixpkgs' binary patching while replacing its unavailable release.
  upstreamDevin.overrideAttrs (previous:
    assert previous.passthru.vscodeVersion == source.vscodeVersion; {
      inherit (source) version;
      src = fetchurl {inherit (source) url hash;};
    })
