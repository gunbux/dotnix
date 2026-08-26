{
  config,
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

  # Matcha's unread_summary plugin needs the OpenRouter key baked into the
  # plugin file itself (Lua plugins are sandboxed with no file/env access),
  # so render it via a sops template instead of committing the key to git.
  sops.templates."matcha-unread-summary.lua" = {
    path = "/home/chun/.config/matcha/plugins/unread_summary.lua";
    owner = "chun";
    mode = "0400";
    content =
      builtins.replaceStrings
      ["@OPENROUTER_API_KEY@"]
      [config.sops.placeholder.openrouter_api_key]
      (builtins.readFile ../config/matcha/plugins/unread_summary.lua);
  };

  # Herald's config.yaml has no shell-command interpolation like mutt's
  # `set var = "`cat ...`"`, so render the mxroute password via a sops
  # template instead of committing it to git.
  sops.templates."herald-conf.yaml" = {
    path = "/home/chun/.herald/conf.yaml";
    owner = "chun";
    mode = "0600";
    content =
      builtins.replaceStrings
      ["@MUTT_MXROUTE_PASSWORD@"]
      [config.sops.placeholder.mutt_mxroute_password]
      (builtins.readFile ../config/herald/conf.yaml);
  };
}
