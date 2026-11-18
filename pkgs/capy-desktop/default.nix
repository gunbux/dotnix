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
  version = "0.9.2";
  base = "https://downloads.capy.ai/stable";
  # sha512 values from latest-mac.yml, latest-linux.yml and latest-linux-arm64.yml.
  sources = {
    aarch64-darwin = {
      url = "${base}/Capy-${version}-arm64.zip";
      hash = "sha512-SwKTVH5mWNjLTgNQR3rxf3h5qQLB22DbYqCzE4jdPzlHu6EXW5HGHzqGdHIKkr7yFgbMyW7JE6AtXnDI00IM3w==";
    };
    x86_64-darwin = {
      url = "${base}/Capy-${version}-x64.zip";
      hash = "sha512-m7lNO1nSoCSzB9sRYQuekwnsEk3b5vbRKguweVHRJhsEmswcduVGAdvKGfVax2frFhMm/ILWBw69VX27se5xyg==";
    };
    x86_64-linux = {
      url = "${base}/capy-${version}-x86_64.AppImage";
      hash = "sha512-UvrgKTt1kFRbcbMn/jCe5JOuylndopljmXw7UUwZRSJcuC0GN3zAKWSNck6mjWeY8LjA2r8NXGV2lhDAiRebZA==";
    };
    aarch64-linux = {
      url = "${base}/capy-${version}-arm64.AppImage";
      hash = "sha512-jldysLbP8ePaJCSuMEsSVetIIfFI8qLKzVmqCMdeIlvfmG4dgNoh1s/HkJabMjmkpoJkAtRqjm9hyNV9C1qVbA==";
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
    contents = appimageTools.extractType2 {inherit pname version src;};
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
