{
  lib,
  stdenv,
  fetchurl,
  fetchFromGitHub,
  electron_44-bin,
  upstreamT3code,
  upstreamDesktop,
}: let
  # Keep the release's Electron major and apply its latest patch release.
  electronVersion = "44.10.2";
  electronPlatforms = {
    x86_64-linux = {
      target = "linux-x64";
      hash = "sha256-0vkxncgdZ4bGhKgPY9coQhdh9Vono64703MlDw9A/co=";
    };
    aarch64-linux = {
      target = "linux-arm64";
      hash = "sha256-F8fidAw5eVclXS7aFvj5BCIw+E/7RYQAqcwU+eDdaHk=";
    };
    aarch64-darwin = {
      target = "darwin-arm64";
      hash = "sha256-HvYUJUkWD+hXLKmJISy1/D79X63kRbWsJWOb+pQIqA0=";
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
  # The feed still packages 0.1.6. Reuse upstream once it catches this release.
  version = "0.1.7";
  src = fetchFromGitHub {
    owner = "pingdotgg";
    repo = "t3code";
    tag = "v${version}";
    hash = "sha256-oQLmDCDuJPNBsf8MHMD2xhMq+CF6L836/PQesM91Clw=";
  };
  # native/resource-monitor is byte-identical in both releases.
  releaseBase =
    if lib.versionOlder base.version version
    then
      base.overrideAttrs (previous: {
        inherit version src;
        pnpmDeps = previous.pnpmDeps.overrideAttrs {
          inherit version src;
          outputHash = "sha256-hVpxbHZ5syedAc1Zc20TkxSgB6VA3XQGubQMx6e0njA=";
        };
        preBuild =
          lib.replaceStrings
          ["scripts/update-release-package-versions.ts ${base.version}"]
          ["scripts/update-release-package-versions.ts ${version}"]
          previous.preBuild;
        meta =
          previous.meta
          // {
            changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${version}";
          };
      })
    else base;
  unwrapped = releaseBase.overrideAttrs (previous: {
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
