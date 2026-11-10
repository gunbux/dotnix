{
  lib,
  stdenv,
  fetchurl,
  electron_44-bin,
  upstreamT3code,
  upstreamDesktop,
}: let
  # Keep the release's Electron major and use its latest stable release.
  electronVersion = "44.11.0";
  electronPlatforms = {
    x86_64-linux = {
      target = "linux-x64";
      hash = "sha256-ULiwmiBkL774dEuD7d+IdPJCuETlFnqRDaEwb0HCLTo=";
    };
    aarch64-linux = {
      target = "linux-arm64";
      hash = "sha256-cIHLpjRoiBAEzRhQjH/636Z8ENVRHfHZoKnvhMvchjg=";
    };
    aarch64-darwin = {
      target = "darwin-arm64";
      hash = "sha256-7X6XWHjpdn3kjXt7wG/dPTM9TVdHFVySuHRHfq97/sM=";
    };
  };
  electronPlatform = electronPlatforms.${stdenv.hostPlatform.system};
  electron = electron_44-bin.overrideAttrs {
    version = electronVersion;
    src = fetchurl {
      url = "https://github.com/electron/electron/releases/download/v${electronVersion}/electron-v${electronVersion}-${electronPlatform.target}.zip";
      inherit (electronPlatform) hash;
    };
  };

  base = upstreamT3code.unwrapped.override {electron_44 = electron;};
  unwrapped = base.overrideAttrs (previous: {
    env = previous.env // {T3CODE_CLERK_JWT_TEMPLATE = "t3-relay";};
    # Chromium draws Electron's native menus on Linux with tall fixed rows.
    # The web UI's in-page menu matches the app theme instead.
    patches =
      (previous.patches or [])
      ++ lib.optionals stdenv.hostPlatform.isLinux [./in-page-context-menus.patch];
  });
  t3code = (upstreamT3code.override {t3code-unwrapped = unwrapped;}).overrideAttrs (previous:
    assert lib.hasInfix "--inherit-argv0" previous.installPhase; {
      installPhase =
        lib.replaceStrings
        ["--inherit-argv0"]
        [''--set T3CODE_DESKTOP_LAUNCHER_PATH "$desktop/bin/t3code-desktop" --inherit-argv0'']
        previous.installPhase;
    });
in
  (upstreamDesktop.override {inherit t3code;}).overrideAttrs (previous: {
    passthru = previous.passthru // {inherit t3code;};
  })
