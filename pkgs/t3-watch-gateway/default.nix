{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  t3-headless,
}:
stdenvNoCC.mkDerivation {
  pname = "t3-watch-gateway";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [./gateway.py ./gateway_test.py];
  };
  nativeBuildInputs = [makeWrapper];
  dontConfigure = true;
  dontBuild = true;
  nativeCheckInputs = [python3];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 -m unittest -v gateway_test.py
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm444 gateway.py $out/lib/t3-watch-gateway/gateway.py
    makeWrapper ${python3}/bin/python3 $out/bin/t3-watch-gateway \
      --add-flags $out/lib/t3-watch-gateway/gateway.py \
      --set-default T3_BIN ${lib.getExe t3-headless}
    runHook postInstall
  '';
  meta = {
    description = "Supervises a headless T3 watch gateway and provisions scoped bridge tokens";
    mainProgram = "t3-watch-gateway";
    platforms = ["x86_64-linux"];
  };
}
