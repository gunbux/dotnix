{
  lib,
  buildGoModule,
  libsecret,
}:
buildGoModule {
  pname = "t3-activity";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [./go.mod ./go.sum ./main.go ./relay.go];
  };

  vendorHash = "sha256-sJn4yiUb227dGjpFF6dw/oXOLQ/2mdSikqymhkDchSM=";

  # modernc.org/sqlite is pure Go
  env.CGO_ENABLED = "0";

  # secret-tool reads the keyring password behind the desktop's Clerk token.
  ldflags = ["-s" "-w" "-X main.secretTool=${libsecret}/bin/secret-tool"];

  meta = {
    description = "T3 Code agent activity as JSON, for the chun/t3-activity Noctalia plugin";
    mainProgram = "t3-activity";
    platforms = lib.platforms.unix;
  };
}
