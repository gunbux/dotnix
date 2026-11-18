{
  lib,
  stdenvNoCC,
  fetchurl,
  upstreamDevin,
}: let
  sources = lib.importJSON ./sources.json;
  source = sources.platforms.${stdenvNoCC.hostPlatform.system};
in
  # nixpkgs' older archive returns HTTP 403; use the official current manifest.
  upstreamDevin.overrideAttrs {
    inherit (sources) version;
    src = fetchurl {inherit (source) url hash;};
  }
