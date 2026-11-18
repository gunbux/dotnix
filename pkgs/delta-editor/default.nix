{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  libGL,
  llvmPackages,
  libxcb,
  libxkbcommon,
  vulkan-loader,
  wayland,
}: let
  version = "0.27.2";

  # The release API (delta.dev/api/releases/stable/<version>/asset) now
  # resolves to this fixed, unsigned URL.
  src = fetchurl {
    url = "https://releases.delta.dev/releases/stable/${version}/delta-linux-x86_64.tar.gz";
    hash = "sha256-s8/5ZZvnXUnWLE7ATzlFMS8z3RDpboCr2BywH/Iss9w=";
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
