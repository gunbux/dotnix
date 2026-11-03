{
  lib,
  buildGoModule,
  makeWrapper,
  gh,
}:
buildGoModule {
  pname = "sprint";
  version = "0.3.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./go.mod
      ./go.sum
      (lib.fileset.fileFilter (f: f.hasExt "go") ./.)
    ];
  };

  vendorHash = "sha256-zafxVNQsomtOwZ3RCyAeIgBg4Aj4Pf6yD3qZt6umd+Y=";

  # modernc.org/sqlite is pure Go.
  env.CGO_ENABLED = 0;
  ldflags = ["-s" "-w"];

  nativeBuildInputs = [makeWrapper];

  # `sprint pr add` and `pr sync` ask GitHub through gh.
  postInstall = ''
    wrapProgram $out/bin/sprint --suffix PATH : ${lib.makeBinPath [gh]}
  '';

  meta = {
    description = "Append-only sprint log (goal, subgoals, plan, PRs, benchmarks, context) shown on a local Grafana dashboard";
    mainProgram = "sprint";
    platforms = lib.platforms.unix;
  };
}
