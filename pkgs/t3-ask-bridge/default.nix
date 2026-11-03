{
  lib,
  stdenvNoCC,
  makeWrapper,
  nodejs,
}:
stdenvNoCC.mkDerivation {
  pname = "t3-ask-bridge";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [./bridge.mjs ./watch-api.mjs ./watch-api.test.mjs];
  };

  nativeBuildInputs = [makeWrapper];
  nativeCheckInputs = [nodejs];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    node --test watch-api.test.mjs
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm444 bridge.mjs watch-api.mjs -t $out/lib/t3-ask-bridge
    makeWrapper ${lib.getExe nodejs} $out/bin/t3-ask-bridge \
      --add-flags $out/lib/t3-ask-bridge/bridge.mjs
    runHook postInstall
  '';

  meta = {
    description = "Lets the T3 Ask Garmin watch app list and answer T3 Code questions";
    mainProgram = "t3-ask-bridge";
    platforms = lib.platforms.unix;
  };
}
