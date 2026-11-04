# Sends a WakaTime heartbeat for each minute a Claude Code or Codex session was
# active, which wakatime-cli's own AI parsing misses (see the script's header).
# modules/home/wakatime.nix runs it on the same 5-minute timer.
{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  wakatime-cli,
  zstd,
}:
stdenvNoCC.mkDerivation {
  pname = "wakatime-agent-activity";
  version = "0.1.0";

  src = ./wakatime-agent-activity.py;
  dontUnpack = true;

  nativeBuildInputs = [makeWrapper];

  # zstd reads Codex's compressed .jsonl.zst sessions.
  installPhase = ''
    runHook preInstall
    install -Dm644 $src $out/libexec/wakatime-agent-activity.py
    makeWrapper ${lib.getExe python3} $out/bin/wakatime-agent-activity \
      --add-flags "-I $out/libexec/wakatime-agent-activity.py" \
      --set WAKATIME_CLI ${lib.getExe wakatime-cli} \
      --prefix PATH : ${lib.makeBinPath [zstd]}
    runHook postInstall
  '';

  meta = {
    description = "Send WakaTime heartbeats for the minutes an AI agent was working";
    mainProgram = "wakatime-agent-activity";
    platforms = lib.platforms.unix;
  };
}
