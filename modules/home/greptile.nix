# Greptile (greptilia) local development toolchain
{
  lib,
  pkgs,
  ...
}: let
  # greptilia requires an exact bun version; nixpkgs lags behind.
  # Bump alongside greptilia's onboarding requirement.
  bun-greptile = pkgs.bun.overrideAttrs (old: {
    version = "1.4.3";
    src = pkgs.fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v1.4.3/bun-darwin-aarch64.zip";
      hash = "sha256-gK/UwGm0am+o8+xSC+vHUKeEPkqNW5WD0prUNsAKNAM=";
    };
  });
in {
  home.packages = with pkgs; [
    # Takes precedence over the nixpkgs bun from dev.nix
    (lib.hiPrio bun-greptile)
    infisical # Secrets CLI
    postgresql # psql, used by internal/cli/variants.ts

    # Optional
    goose # Local ClickHouse migrations
    process-compose # `bun run stack`
    stripe-cli # Stripe webhook forwarding for billing work
  ];
}
