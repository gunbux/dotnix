{
  lib,
  pkgs,
}: {
  railway = {
    command = lib.getExe pkgs.railway;
    args = ["mcp"];
  };

  trek.url = "https://trek.chunyu.sh/mcp";

  sure.url = "https://sure.chunyu.sh/mcp";

  openbnb.url = "https://mcp.openbnb.ai/mcp";

  # Cognition's public repo-docs server; no auth. The authenticated Devin MCP
  # server (mcp.devin.ai) needs a cog_ API key, so it is not configured here.
  deepwiki.url = "https://mcp.deepwiki.com/mcp";
}
