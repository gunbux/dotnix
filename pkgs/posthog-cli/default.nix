{
  lib,
  rustPlatform,
  fetchCrate,
  makeBinaryWrapper,
  nodejs,
  pkg-config,
  aws-lc,
  zlib,
  zstd,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "posthog-cli";
  version = "0.19.2";

  # The crates.io tarball ships Cargo.lock and the prebuilt API CLI bundle
  # (lib/posthog-api-cli.mjs) that the monorepo otherwise generates.
  src = fetchCrate {
    inherit (finalAttrs) pname version;
    hash = "sha256-eP8mYP7lgEJZxrGn5vvxRbXfgW/9O52B7auHeP1mM9E=";
  };

  cargoHash = "sha256-Au0eCuQJd04MMXKK/9cz5VPIe69XVRrQMmjeao7gcWM=";

  nativeBuildInputs = [makeBinaryWrapper pkg-config];
  buildInputs = [aws-lc zlib zstd];

  # Upload tests serve a fake object store on a loopback port
  __darwinAllowLocalNetworking = true;

  # `posthog-cli api ...` runs the embedded bundle with `node` from PATH
  postInstall = ''
    wrapProgram $out/bin/posthog-cli \
      --suffix PATH : ${lib.makeBinPath [nodejs]}
  '';

  meta = {
    description = "Command line interface for PostHog";
    homepage = "https://posthog.com/docs/cli";
    license = lib.licenses.mit;
    mainProgram = "posthog-cli";
    platforms = lib.platforms.unix;
  };
})
