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
}
