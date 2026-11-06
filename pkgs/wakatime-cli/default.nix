# wakatime-cli from the upstream release binaries (static Go builds).
# nixpkgs has 2.26.15. 2.28.0 reads T3 Code's Codex sessions as AI activity
# and adds --sync-ai-activity, which modules/home/wakatime.nix runs on a timer.
{
  lib,
  stdenvNoCC,
  fetchzip,
}: let
  version = "2.28.4";
  assets = {
    x86_64-linux = {
      arch = "linux-amd64";
      hash = "sha256-kWcUERKEtz5x3EsT0OIUSb9t91CFpt3e/c5ftNjng60=";
    };
    aarch64-darwin = {
      arch = "darwin-arm64";
      hash = "sha256-+ISg0GWaSZ+qvSZrW2dinJyybfNUpCDqhU1HxxXNikk=";
    };
  };
  asset = assets.${stdenvNoCC.hostPlatform.system} or (throw "wakatime-cli: no release binary for ${stdenvNoCC.hostPlatform.system}");
in
  stdenvNoCC.mkDerivation {
    pname = "wakatime-cli";
    inherit version;

    src = fetchzip {
      url = "https://github.com/wakatime/wakatime-cli/releases/download/v${version}/wakatime-cli-${asset.arch}.zip";
      inherit (asset) hash;
      stripRoot = false;
    };

    installPhase = ''
      runHook preInstall
      install -Dm755 wakatime-cli-${asset.arch} $out/bin/wakatime-cli
      runHook postInstall
    '';

    meta = {
      description = "Command line interface used by all WakaTime text editor plugins";
      homepage = "https://github.com/wakatime/wakatime-cli";
      license = lib.licenses.bsd3;
      mainProgram = "wakatime-cli";
      platforms = lib.attrNames assets;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
