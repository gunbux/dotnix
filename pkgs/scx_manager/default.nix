{
  lib,
  stdenv,
  cmake,
  pkg-config,
  qt6,
  fmt,
  polkit-qt6,
  rustPlatform,
  cargo,
  rustc,
  ninja,
  mold ? null,
}:
stdenv.mkDerivation rec {
  pname = "scx-manager";
  version = "1.15.5";

  src = ./.;

  cargoDeps = rustPlatform.importCargoLock {
    lockFile = ./scx-rustlib/Cargo.lock;
  };

  nativeBuildInputs =
    [
      cmake
      pkg-config
      qt6.wrapQtAppsHook
      qt6.qttools # For lupdate/lrelease
      cargo
      rustc
      ninja
      rustPlatform.cargoSetupHook
    ]
    ++ lib.optionals (stdenv.isLinux && mold != null) [mold];

  buildInputs = [
    qt6.qtbase
    fmt
    polkit-qt6
  ];

  cmakeFlags =
    [
      "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
      "-GNinja"
    ]
    ++ lib.optionals (stdenv.isLinux && mold != null) [
      "-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=mold"
    ];

  # Ensure we have the required C++23 support
  env.NIX_CFLAGS_COMPILE = "-std=c++23";

  # Ensure Rust environment is properly set up
  preConfigure = ''
    export CARGO_HOME=$(mktemp -d)
  '';

  meta = with lib; {
    description = "Simple GUI for managing sched-ext schedulers via scx_loader";
    homepage = "https://github.com/cachyos/scx-manager";
    license = licenses.gpl2Plus;
    maintainers = with maintainers; [];
    platforms = platforms.linux;
    mainProgram = "scx-manager";
  };
}
