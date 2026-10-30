{
  lib,
  rustPlatform,
  fetchCrate,
  makeBinaryWrapper,
  nodejs,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "posthog-cli";
  version = "0.19.0";

  # The crates.io tarball ships Cargo.lock and the prebuilt API CLI bundle
  # (lib/posthog-api-cli.mjs) that the monorepo otherwise generates.
  src = fetchCrate {
    inherit (finalAttrs) pname version;
    hash = "sha256-lF6MyWr7mhNlfaU5hvBQHhJ48EccOVFi3yB0oq4gBkE=";
  };

  cargoHash = "sha256-LecRLbo76DcytbGG1HJpn/aOQrm1ax/9ca9SEOB1cgM=";

  nativeBuildInputs = [makeBinaryWrapper];

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
