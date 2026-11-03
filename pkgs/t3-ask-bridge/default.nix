{
  lib,
  stdenvNoCC,
  makeWrapper,
  nodejs,
  python3,
}: let
  mapPython = python3.withPackages (p: [p.pillow]);
in
  stdenvNoCC.mkDerivation {
    pname = "t3-ask-bridge";
    version = "0.1.0";

    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [./bridge.mjs ./watch-api.mjs ./watch-api.test.mjs ./peers.mjs ./peers.test.mjs ./helloride.mjs ./helloride.test.mjs ./street-map.mjs ./street-map.test.mjs ./street-render.py ./street-render.test.py];
    };

    nativeBuildInputs = [makeWrapper];
    nativeCheckInputs = [nodejs mapPython];

    doCheck = true;
    checkPhase = ''
        runHook preCheck
        node --test watch-api.test.mjs peers.test.mjs helloride.test.mjs street-map.test.mjs
        python3 street-render.test.py
      runHook postCheck
    '';

    installPhase = ''
      runHook preInstall
      install -Dm444 bridge.mjs watch-api.mjs peers.mjs helloride.mjs street-map.mjs street-render.py -t $out/lib/t3-ask-bridge
      makeWrapper ${lib.getExe nodejs} $out/bin/t3-ask-bridge \
        --add-flags $out/lib/t3-ask-bridge/bridge.mjs \
        --set BUS_AUNTY_MAP_PYTHON ${mapPython}/bin/python3
      runHook postInstall
    '';

    meta = {
      description = "Lets the T3 Ask Garmin watch app list and answer T3 Code questions";
      mainProgram = "t3-ask-bridge";
      platforms = lib.platforms.unix;
    };
  }
