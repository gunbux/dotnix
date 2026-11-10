{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:
stdenv.mkDerivation {
  pname = "t3-headless";
  version = "0.1.8";

  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v0.1.8/t3-0.1.8-linux-x64.tar.gz";
    hash = "sha256-ucSdwAwj+7xZYb2v8tiOVW2WyNvWOMRQHik3xwZQqeU=";
  };

  nativeBuildInputs = [autoPatchelfHook];
  buildInputs = [stdenv.cc.cc.lib];
  # Upstream ships both GNU and musl optional addons. This glibc runtime
  # selects GNU; retain the unused musl files without adding a second libc.
  autoPatchelfIgnoreMissingDeps = ["libc.musl-x86_64.so.1"];
  dontConfigure = true;
  dontBuild = true;
  # Bun embeds the application in the executable; stripping can damage it.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/t3 $out/bin
    cp -a ./. $out/lib/t3/
    ln -s $out/lib/t3/t3 $out/bin/t3
    runHook postInstall
  '';

  meta = {
    description = "Official T3 Code headless runtime, including its bundled client and native helpers";
    homepage = "https://github.com/pingdotgg/t3code";
    license = lib.licenses.mit;
    mainProgram = "t3";
    platforms = ["x86_64-linux"];
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
  };
}
