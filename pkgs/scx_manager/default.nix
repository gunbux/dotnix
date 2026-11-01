{
  lib,
  stdenv,
  cmake,
  corrosion,
  fetchCrate,
  fetchFromGitHub,
  pkg-config,
  qt6,
  fmt,
  rustPlatform,
  cargo,
  rustc,
  ninja,
  mold ? null,
}: let
  # Corrosion requires the exact cxx version in scx-rustlib/Cargo.lock.
  cxxbridge = rustPlatform.buildRustPackage rec {
    pname = "cxxbridge-cmd";
    version = "1.0.200";
    src = fetchCrate {
      inherit pname version;
      hash = "sha256-yemiwkty83ZWVno4opu1SmSu6DsfMPUi8oNuvjf8Xgc=";
    };
    cargoLock.lockFile = "${src}/Cargo.lock";
    meta.mainProgram = "cxxbridge";
  };
in
  stdenv.mkDerivation rec {
    pname = "scx-manager";
    version = "1.16.0";

    src = fetchFromGitHub {
      owner = "CachyOS";
      repo = "scx-manager";
      tag = "v${version}";
      hash = "sha256-fZJ20cYS/yHD7g25gzrBqGpRlp60ctLgLVTqrYFjiPI=";
    };

    cargoRoot = "scx-rustlib";

    cargoDeps = rustPlatform.importCargoLock {
      lockFile = "${src}/scx-rustlib/Cargo.lock";
    };

    nativeBuildInputs =
      [
        cmake
        cxxbridge
        pkg-config
        qt6.wrapQtAppsHook
        qt6.qttools # For lupdate/lrelease
        cargo
        rustc
        ninja
        rustPlatform.cargoSetupHook
      ]
      ++ lib.optionals (stdenv.hostPlatform.isLinux && mold != null) [mold];

    buildInputs = [
      qt6.qtbase
      fmt
      corrosion
    ];

    cmakeFlags =
      [
        "-DCPM_USE_LOCAL_PACKAGES=ON"
        "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
        "-GNinja"
      ]
      ++ lib.optionals (stdenv.hostPlatform.isLinux && mold != null) [
        "-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=mold"
      ];

    # Ensure we have the required C++23 support
    env.NIX_CFLAGS_COMPILE = "-std=c++23";

    meta = with lib; {
      description = "Simple GUI for managing sched-ext schedulers via scx_loader";
      homepage = "https://github.com/cachyos/scx-manager";
      license = licenses.gpl3Plus;
      maintainers = with maintainers; [];
      platforms = platforms.linux;
      mainProgram = "scx-manager";
    };
  }
