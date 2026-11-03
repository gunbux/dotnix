{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  gh,
}:
stdenvNoCC.mkDerivation {
  pname = "sprint";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [./sprint.py ./test_sprint.py];
  };

  nativeBuildInputs = [makeWrapper];
  nativeCheckInputs = [python3];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 -m unittest -v test_sprint
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm444 sprint.py -t $out/lib/sprint
    makeWrapper ${lib.getExe python3} $out/bin/sprint \
      --add-flags "-I $out/lib/sprint/sprint.py" \
      --suffix PATH : ${lib.makeBinPath [gh]}
    runHook postInstall
  '';

  meta = {
    description = "Append-only sprint log (goal versions, plan, PRs, benchmarks) for a local Grafana dashboard";
    mainProgram = "sprint";
    platforms = lib.platforms.unix;
  };
}
