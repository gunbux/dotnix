{
  lib,
  buildGoModule,
  fetchFromGitHub,
}: let
  commit = "e3a0fa61bcd0"; # short=12, matches upstream Makefile's COMMIT format
in
  buildGoModule (finalAttrs: {
    pname = "herald";
    version = "0.8.0-beta.1";

    src = fetchFromGitHub {
      owner = "herald-email";
      repo = "herald-mail-app";
      tag = "v${finalAttrs.version}";
      hash = "sha256-GKV8r1wf1Z/cyv/dRpGDQ1lry5Kgj5flZqWfpGS6ybE=";
    };

    vendorHash = "sha256-keK9JVcLMriE4/0bi2JKvXcgcM1UH6XqdoQ8chwoPwI=";

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
