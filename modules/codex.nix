{
  lib,
  pkgs,
  ...
}: let
  mcpServers = import ./mcp-servers.nix {inherit lib pkgs;};
  codexConfig = (pkgs.formats.toml {}).generate "codex-config.toml" {
    mcp_servers = mcpServers;
  };
in {
  environment.etc."codex/config.toml".source = codexConfig;
}
