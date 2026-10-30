# Greptile (greptilia) local development toolchain
{
  config,
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

  # greptilia's infra/terraform pins these versions in
  # .github/workflows/terraform-check.yml; a newer terraform writes state the
  # pinned one can't read. Bump alongside that workflow.
  terraform-greptile = pkgs.stdenvNoCC.mkDerivation {
    pname = "terraform";
    version = "1.15.8";
    src = pkgs.fetchurl {
      url = "https://releases.hashicorp.com/terraform/1.15.8/terraform_1.15.8_darwin_arm64.zip";
      hash = "sha256-8hARDFaYuU2AOnpjzbAlG1RVwVCEFHiAjiu7ND+V7Wg=";
    };
    nativeBuildInputs = [pkgs.unzip];
    sourceRoot = ".";
    installPhase = "install -Dm755 terraform $out/bin/terraform";
  };
  terragrunt-greptile = pkgs.stdenvNoCC.mkDerivation {
    pname = "terragrunt";
    version = "1.1.1";
    src = pkgs.fetchurl {
      url = "https://github.com/gruntwork-io/terragrunt/releases/download/v1.1.1/terragrunt_darwin_arm64";
      hash = "sha256-M5rAa/FuO0o4I5SmF0SXcAKWzEhaUXLON+unJecgyDw=";
    };
    dontUnpack = true;
    installPhase = "install -Dm755 $src $out/bin/terragrunt";
  };

  # `helmfile apply` shells out to the helm-diff plugin.
  helm-greptile = pkgs.wrapHelm pkgs.kubernetes-helm {
    plugins = [pkgs.kubernetes-helmPlugins.helm-diff];
  };

  # `greptilia-docs <worktree>` switches what the docs agent below serves.
  greptilia-docs = pkgs.writeShellApplication {
    name = "greptilia-docs";
    runtimeInputs = with pkgs; [coreutils git gnugrep];
    text = builtins.readFile ../../config/greptilia-docs/greptilia-docs.sh;
  };
  greptilia-docs-serve = pkgs.writeShellApplication {
    name = "greptilia-docs-serve";
    runtimeInputs = with pkgs; [coreutils];
    text = builtins.readFile ../../config/greptilia-docs/serve.sh;
  };
in {
  home.packages = with pkgs; [
    # Takes precedence over the nixpkgs bun from dev.nix
    (lib.hiPrio bun-greptile)
    infisical # Secrets CLI
    postgresql # psql, used by internal/cli/variants.ts
    posthog-cli # Product analytics; custom package in pkgs/
    greptile-cli # `greptile review` of local changes; custom package in pkgs/
    # The pre-commit hook lints staged .github/workflows changes with these
    # (scripts/lint/workflows.sh), so even merges from main need them.
    actionlint
    shellcheck

    # Optional
    goose # Local ClickHouse migrations
    process-compose # `bun run stack`
    stripe-cli # Stripe webhook forwarding for billing work
    cloudflared # Public tunnel to the local llmproxy for Kubernetes sandboxes

    # Kubernetes
    helm-greptile
    helmfile # infra/helm bootstrap (Cilium, Argo CD)
    stern # Multi-pod log tailing

    # Terraform (infra/terraform)
    terraform-greptile
    terragrunt-greptile

    # AWS / EKS
    eksctl
    aws-iam-authenticator # Legacy EKS kubeconfig auth
    ssm-session-manager-plugin # `aws ssm start-session` into nodes

    greptilia-docs
  ];

  # ~/.aws/config is left unmanaged so `aws configure sso` can write profiles
  programs.awscli.enable = true;
  home.sessionVariables.AWS_PAGER = "";

  # aws plugin: completion, `asp` (switch profile), `acp`, `agp`
  programs.zsh.oh-my-zsh.plugins = ["aws"];

  # Complete greptilia-docs with Git worktree names, described by branch.
  programs.zsh.initContent = ''
    _greptilia-docs() {
      local -a items
      local name branch
      items=("main:~/repo/greptilia")
      while IFS=$'\t' read -r name branch; do
        items+=("$name:''${branch//:/\\:}")
      done < <(greptilia-docs --list)
      _describe 'greptilia worktree' items
    }
    compdef _greptilia-docs greptilia-docs
  '';

  programs.zsh.shellAliases = {
    kx = "kubectx";
    kn = "kubens";
  };

  # Show the current kube context/namespace in the prompt
  # (starship's aws module, on by default, shows the active profile/region)
  programs.starship.settings.kubernetes.disabled = false;

  # greptilia's Fumadocs site (docs/content Obsidian vault) on http://localhost:3333.
  # Serves ~/repo/greptilia unless `greptilia-docs <worktree>` picked a Git
  # worktree. The vault is converted once at startup; `greptilia-docs <current>`
  # restarts it to pick up new pages.
  launchd.agents.greptilia-docs = {
    enable = true;
    config = {
      Program = "${greptilia-docs-serve}/bin/greptilia-docs-serve";
      EnvironmentVariables = {
        PATH = "${config.home.profileDirectory}/bin:/usr/bin:/bin";
        PORT = "3333";
      };
      RunAtLoad = true;
      KeepAlive.SuccessfulExit = false;
      ThrottleInterval = 30;
      ProcessType = "Background";
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/greptilia-docs.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/greptilia-docs.log";
    };
  };
}
