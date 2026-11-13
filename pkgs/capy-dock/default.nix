{
  lib,
  stdenvNoCC,
  fetchurl,
}:
# Capy's headless device daemon (`capy dock`). The release carries a manifest
# signed into the binary, and `capy dock` will not open thread terminals when
# any shipped file differs from it. So the files stay byte-for-byte: no
# patchelf, no strip, no shebang patching. On NixOS the glibc binary and its
# native addons load through nix-ld.
let
  version = "0.8.0";
  # From https://downloads.capy.ai/stable/dock/<version>/SHA256SUMS.
  targets = {
    aarch64-darwin = {
      target = "darwin-arm64";
      hash = "sha256-F4Yz1cdESsRXcX0BpMFwh5fI0IEZMVoTDoyry82tsNo=";
    };
    x86_64-darwin = {
      target = "darwin-x64";
      hash = "sha256-c18aa4DP9pbyfd4mRpe+HcTpLEUMJvR6BfXomYhgsew=";
    };
    aarch64-linux = {
      target = "linux-arm64";
      hash = "sha256-RYumwLiGokkE0QJwcUO8Ew2xAJK0nh0yy1BRwCLP+e0=";
    };
    x86_64-linux = {
      target = "linux-x64";
      hash = "sha256-luyhmtbnswbVlclFvlxSzlKlrVKCFMU7rT7mRana1FQ=";
    };
  };
  platform =
    targets.${stdenvNoCC.hostPlatform.system}
    or (throw "capy-dock: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
  stdenvNoCC.mkDerivation {
    pname = "capy-dock";
    inherit version;

    src = fetchurl {
      url = "https://downloads.capy.ai/stable/dock/${version}/capy-dock-${platform.target}.tar.gz";
      inherit (platform) hash;
    };

    sourceRoot = "capy-dock";
    dontConfigure = true;
    dontBuild = true;
    # Any change to the shipped files breaks the signed manifest (and the
    # macOS code signature).
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/capy-dock $out/bin
      cp -a ./. $out/lib/capy-dock/
      ln -s $out/lib/capy-dock/bin/capy $out/bin/capy
      runHook postInstall
    '';

    meta = {
      description = "Capy Dock: runs Capy cloud-agent threads on this machine";
      homepage = "https://docs.capy.ai/dock";
      license = lib.licenses.unfree;
      mainProgram = "capy";
      platforms = builtins.attrNames targets;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
