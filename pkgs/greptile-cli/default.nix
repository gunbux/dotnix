{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  nodejs,
}:
# The npm package is one bundled script with no dependencies, so it runs from the
# registry tarball as-is.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "greptile-cli";
  version = "3.8.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/greptile/-/greptile-${finalAttrs.version}.tgz";
    hash = "sha256-alx3a24SD2IO38Iayxrq/f9gxQZJ6bOCfjQwIkdDIF8=";
  };

  nativeBuildInputs = [makeBinaryWrapper];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/greptile
    cp -r . $out/lib/greptile
    makeWrapper ${lib.getExe nodejs} $out/bin/greptile \
      --add-flags $out/lib/greptile/dist/greptile.js
    runHook postInstall
  '';

  meta = {
    description = "Greptile code review from the command line";
    homepage = "https://www.npmjs.com/package/greptile";
    mainProgram = "greptile";
    platforms = lib.platforms.unix;
  };
})
