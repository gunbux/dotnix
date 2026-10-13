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

    # Kubernetes
    kubectl
    kubectx # kubectx + kubens
    kubernetes-helm
    stern # Multi-pod log tailing

    # AWS / EKS
    eksctl
    aws-iam-authenticator # Legacy EKS kubeconfig auth
    ssm-session-manager-plugin # `aws ssm start-session` into nodes
  ];

  # ~/.aws/config is left unmanaged so `aws configure sso` can write profiles
  programs.awscli.enable = true;
  home.sessionVariables.AWS_PAGER = "";

  programs.k9s.enable = true;

  # kubectl plugin: `k` alias, kubectl completion (also for `k`), and
  # shortcuts like kgp, kgd, kl, kex, kaf
  # aws plugin: completion, `asp` (switch profile), `acp`, `agp`
  programs.zsh.oh-my-zsh.plugins = ["kubectl" "aws"];

  programs.zsh.shellAliases = {
    kx = "kubectx";
    kn = "kubens";
  };

  # Show the current kube context/namespace in the prompt
  # (starship's aws module, on by default, shows the active profile/region)
  programs.starship.settings.kubernetes.disabled = false;
}
