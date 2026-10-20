{
  lib,
  rustPlatform,
  fetchCrate,
  makeBinaryWrapper,
  nodejs,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "posthog-cli";
  version = "0.18.10";

  # The crates.io tarball ships Cargo.lock and the prebuilt API CLI bundle
  # (lib/posthog-api-cli.mjs) that the monorepo otherwise generates.
  src = fetchCrate {
    inherit (finalAttrs) pname version;
    hash = "sha256-BkEaqvrHGX6EDzwWyx0Yhelnz1fS0M/rRmmh1OGOrE8=";
  };

  cargoHash = "sha256-T0hOf8lVedvZFAuWlEsPbcSiaWJOqAfl1dcWRIrL9yE=";

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
