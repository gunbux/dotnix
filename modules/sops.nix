{
  lib,
  inputs,
  ...
}: {
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];
  sops.defaultSopsFile = ../secrets/secrets.yaml;
  sops.defaultSopsFormat = "yaml";
  sops.age.sshKeyPaths = ["/home/chun/.ssh/id_ed25519"];

  sops.secrets.openrouter_api_key = {
    path = "/run/secrets/openrouter_api_key";
    owner = "chun";
    mode = "0600";
  };

  sops.secrets.claude_code_oauth_token = {
    path = "/run/secrets/claude_code_oauth_token";
    owner = "chun";
    mode = "0600";
  };

  sops.secrets.mutt_gmail_password = {
    path = "/run/secrets/mutt_gmail_password";
    owner = "chun";
    mode = "0600";
  };

  sops.secrets.mutt_mxroute_password = {
    path = "/run/secrets/mutt_mxroute_password";
    owner = "chun";
    mode = "0600";
  };
}
