# Paid cursor themes from the private `cursors` input (github.com/gunbux/cursors).
{
  src,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation {
  pname = "chunky-cursors";
  version = "0-unstable";
  inherit src;

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/share/icons
    for theme in */; do
      if [ -f "$theme/index.theme" ]; then
        cp -R "$theme" $out/share/icons/
      fi
    done
  '';
}
