{
  lib,
  stdenv,
  stdenvNoCC,
  autoPatchelfHook,
  cacert,
  curl,
  jq,
  libGL,
  llvmPackages,
  libxcb,
  libxkbcommon,
  vulkan-loader,
  wayland,
}: let
  version = "0.17.0";

  # delta.dev only hands out short-lived presigned R2 URLs, so resolve one
  # through the versioned release API inside a fixed-output derivation.
  src = stdenvNoCC.mkDerivation {
    name = "delta-linux-x86_64-${version}.tar.gz";
    nativeBuildInputs = [cacert curl jq];
    buildCommand = ''
      url=$(curl -fsSL "https://delta.dev/api/releases/nightly/${version}/asset?asset=delta&os=linux&arch=x86_64" | jq -r .url)
      curl -fsSL "$url" -o "$out"
    '';
    outputHashMode = "flat";
    outputHashAlgo = "sha256";
    outputHash = "sha256-+AUZre1HCN2hzmF95jY0Xs0n4Fd/yPnfCTG+QGBt6MU=";
  };
in
  stdenv.mkDerivation {
    pname = "delta-editor";
    inherit version src;

    sourceRoot = "Delta";

    nativeBuildInputs = [autoPatchelfHook];

    buildInputs = [
      llvmPackages.libunwind
      libxcb
      libxkbcommon
      stdenv.cc.cc.lib
    ];

    # dlopen'd by the GPU/windowing backends at runtime
    runtimeDependencies = [
      libGL
      vulkan-loader
      wayland
    ];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      # Drop the bundled libraries in favour of the nixpkgs ones
      mkdir -p $out/libexec/delta/bin $out/bin
      install -Dm755 bin/delta $out/libexec/delta/bin/delta
      # Named delta-editor so it doesn't collide with git-delta's `delta`
      ln -s $out/libexec/delta/bin/delta $out/bin/delta-editor

      cp -r share $out/share
      substituteInPlace $out/share/applications/dev.zed.Delta.desktop \
        --replace-fail "Exec=delta " "Exec=$out/bin/delta-editor "

      runHook postInstall
    '';

    meta = {
      description = "AI-native code editor from the makers of Zed";
      homepage = "https://delta.dev";
      license = lib.licenses.unfree;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      mainProgram = "delta-editor";
      platforms = ["x86_64-linux"];
    };
  }
