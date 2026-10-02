{
  lib,
  appimageTools,
  fetchurl,
}: let
  pname = "paseo-desktop";
  version = "0.10.3";

  src = fetchurl {
    url = "https://github.com/getpaseo/paseo/releases/download/v${version}/Paseo-x86_64.AppImage";
    hash = "sha256-SRu25gTSEDiex2KwemLqifgmvqFfmV2DpnA3pZDzmhM=";
  };

  appimageContents = appimageTools.extractType2 {inherit pname version src;};
  resources = "${appimageContents}/resources";

  # Run a bundled node script the way resources/bin/paseo does, but through
  # the FHS wrapper so Electron-as-node finds its libraries
  mkNodeEntry = name: script: ''
    cat > $out/bin/${name} <<EOF
    #!/bin/sh
    exec env ELECTRON_RUN_AS_NODE=1 PASEO_NODE_ENV=production PASEO_CLI="$out/bin/paseo" \
      $out/bin/paseo-desktop --disable-warning=DEP0040 \
      ${resources}/app.asar.unpacked/dist/daemon/node-entrypoint-runner.js \
      node-script ${resources}/app.asar/node_modules/@getpaseo/${script} "\$@"
    EOF
    chmod +x $out/bin/${name}
  '';
in
  appimageTools.wrapType2 {
    inherit pname version src;

    extraInstallCommands = ''
      install -Dm644 ${appimageContents}/Paseo.desktop $out/share/applications/Paseo.desktop
      substituteInPlace $out/share/applications/Paseo.desktop \
        --replace-fail "Exec=AppRun" "Exec=paseo-desktop"
      cp -r ${appimageContents}/usr/share/icons $out/share/icons

      # Bundled CLI and daemon, matching nixpkgs' paseo/paseo-server
      ${mkNodeEntry "paseo" "cli/dist/index.js"}
      ${mkNodeEntry "paseo-server" "server/dist/scripts/supervisor-entrypoint.js"}
    '';

    meta = {
      description = "Orchestrate multiple coding agents from desktop and mobile";
      homepage = "https://github.com/getpaseo/paseo";
      changelog = "https://github.com/getpaseo/paseo/releases/tag/v${version}";
      license = lib.licenses.asl20;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      mainProgram = "paseo-desktop";
      platforms = ["x86_64-linux"];
    };
  }
