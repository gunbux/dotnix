{
  lib,
  buildGoModule,
  fetchFromGitHub,
}: let
  commit = "db0506dc930c"; # short=12, matches upstream Makefile's COMMIT format
in
  buildGoModule (finalAttrs: {
    pname = "herald";
    version = "0.11.0-beta.1";

    src = fetchFromGitHub {
      owner = "herald-email";
      repo = "herald-mail-app";
      tag = "v${finalAttrs.version}";
      hash = "sha256-APnoMEeXfJkKPGMBSO1M8fLuK/j+iuylrtyZOmLfrSY=";
    };

    vendorHash = "sha256-1tlfbGCzH/QzpAknxC5wx071kFOAZtR+u4hGCaJWa4g=";

    # mattn/go-sqlite3 needs cgo
    env.CGO_ENABLED = "1";

    subPackages = [
      "cmd/herald"
      "cmd/herald-mcp-server"
      "cmd/herald-ssh-server"
    ];

    ldflags = let
      v = "github.com/herald-email/herald-mail-app/internal/version";
    in [
      "-s"
      "-w"
      "-X ${v}.Version=v${finalAttrs.version}"
      "-X ${v}.Commit=${commit}"
    ];

    meta = {
      description = "Terminal-based email client with AI-assisted triage, cleanup rules, and semantic search";
      homepage = "https://github.com/herald-email/herald-mail-app";
      changelog = "https://github.com/herald-email/herald-mail-app/releases/tag/v${finalAttrs.version}";
      license = lib.licenses.fsl11Asl20;
      mainProgram = "herald";
      platforms = lib.platforms.unix;
    };
  })
