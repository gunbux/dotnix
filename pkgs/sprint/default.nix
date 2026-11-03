{
  lib,
  buildGoModule,
  makeWrapper,
  gh,
}:
buildGoModule {
  pname = "sprint";
  version = "0.2.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./go.mod
      ./go.sum
      (lib.fileset.fileFilter (f: f.hasExt "go") ./.)
      ./assets
    ];
  };

  vendorHash = "sha256-BF3w5Fi7X0Sl5ozEV98WHjuI92p+8DVXrZKfWXLYtOc=";

  # modernc.org/sqlite is pure Go.
  env.CGO_ENABLED = 0;
  ldflags = ["-s" "-w"];

  nativeBuildInputs = [makeWrapper];

  # `sprint pr add` and `pr sync` ask GitHub through gh.
  postInstall = ''
    wrapProgram $out/bin/sprint --suffix PATH : ${lib.makeBinPath [gh]}
  '';

  meta = {
    description = "Append-only sprint log (goal, subgoals, plan, PRs, benchmarks, context) with local status pages";
    mainProgram = "sprint";
    platforms = lib.platforms.unix;
  };
}
