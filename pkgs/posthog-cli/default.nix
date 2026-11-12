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
  version = "0.20.0";

  # The crates.io tarball ships Cargo.lock and the prebuilt API CLI bundle
  # (lib/posthog-api-cli.mjs) that the monorepo otherwise generates.
  src = fetchCrate {
    inherit (finalAttrs) pname version;
    hash = "sha256-VO7K0cwzRZ+qDdB9OKPrYX3qGQDcEJ6s/WW0mY6oqUU=";
  };

  cargoHash = "sha256-Ht9t46CyDQ+tv5g+VlrIJVHpvBJX24x1O2Qkqufj0uk=";

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
