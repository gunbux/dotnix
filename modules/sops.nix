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
}
