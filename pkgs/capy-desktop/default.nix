{
  lib,
  stdenvNoCC,
  fetchurl,
  appimageTools,
  unzip,
}:
# Capy's desktop app (Electron). Linux runs the official AppImage in an FHS
# environment; macOS installs the signed app bundle from the release zip. The
# files stay unmodified on both. Self-updates can't write to the Nix store, so
# bump the version and hashes here instead.
let
  pname = "capy-desktop";
  version = "0.10.0";
  base = "https://downloads.capy.ai/stable";
  # sha512 values from latest-mac.yml, latest-linux.yml and latest-linux-arm64.yml.
  sources = {
    aarch64-darwin = {
      url = "${base}/Capy-${version}-arm64.zip";
      hash = "sha512-dcdkti3qHDzJG/6fqYUXTYc0SM7h2xxWEDIrjA4JiQat8K++Oyp9FZwuP7YsGg7jq0ZqZbC0K452cToq2G7YvQ==";
    };
    x86_64-darwin = {
      url = "${base}/Capy-${version}-x64.zip";
      hash = "sha512-0QMcPBReleWcT/2wUeBCF3YdyTqHUpMhQv/92Y0bnKhcErdRt4SfwChRelR9xIcdUTg+cEZFtm3itzWRnjWkfQ==";
    };
    x86_64-linux = {
      url = "${base}/capy-${version}-x86_64.AppImage";
      hash = "sha512-EBwfVB3xY6VsClqrhCCbPHFP6/dAQo/+QRtPhrigyeo4rB2Vod2sXI7qCLgcYRxS2RZPkEdh66eXfj6JmC8xRA==";
    };
    aarch64-linux = {
      url = "${base}/capy-${version}-arm64.AppImage";
      hash = "sha512-tsnSkFH/oWY/k6N1JdjESMBVyeYcoDt+q6beI97mpMwYroJzl2rc/QsmLlt+pocWg/X8fZjBDSWGd89HTxiAKQ==";
    };
  };
  system = stdenvNoCC.hostPlatform.system;
  src = fetchurl (sources.${system} or (throw "capy-desktop: unsupported system ${system}"));

  meta = {
    description = "Capy desktop app: runs Capy cloud-agent threads on this machine";
    homepage = "https://capy.ai";
    license = lib.licenses.unfree;
    # `capy` is the Dock CLI (pkgs/capy-dock).
    mainProgram = "capy-desktop";
    platforms = builtins.attrNames sources;
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
  };

  linux = let
    contents = appimageTools.extract {inherit pname version src;};
  in
    appimageTools.wrapType2 {
      inherit pname version src meta;
      extraInstallCommands = ''
        desktop=$(echo ${contents}/*.desktop)
        install -m 444 -D "$desktop" $out/share/applications/capy.desktop
        sed -i 's|^Exec=[^ ]*|Exec=capy-desktop|' $out/share/applications/capy.desktop
        if [ -d ${contents}/usr/share/icons ]; then
          cp -r ${contents}/usr/share/icons $out/share/
        fi
      '';
    };

  darwin = stdenvNoCC.mkDerivation {
    inherit pname version src meta;
    nativeBuildInputs = [unzip];
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    # Keep the code signature intact.
    dontFixup = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/Applications $out/bin
      cp -a Capy.app $out/Applications/
      ln -s $out/Applications/Capy.app/Contents/MacOS/Capy $out/bin/capy-desktop
      runHook postInstall
    '';
  };
in
  if stdenvNoCC.hostPlatform.isDarwin
  then darwin
  else linux
