{pkgs, ...}: {
  # Bridge for the T3 Ask watch app (gunbux/garmin, t3-ask/): the watch lists
  # and answers T3 Code questions through Tailscale Funnel on :8443.
  # Tokens live outside this public repo, in ~/.config/t3-ask/ (mode 600):
  #   t3-token     T3 bearer token, scopes orchestration:read + operate
  #   watch-token  random token compiled into the watch app
  #   t3-mcp-token optional T3 MCP client token (--subject mcp-client, same
  #                scopes); adds questions from machines linked over T3 Connect
  systemd.user.services.t3-ask-bridge = {
    Unit = {
      Description = "T3 Ask bridge for the Garmin watch on http://127.0.0.1:8789";
      After = ["network.target"];
    };
    Service = {
      ExecStart = "${pkgs.t3-ask-bridge}/bin/t3-ask-bridge";
      Environment = ["T3_ASK_PORT=8789"];
      Restart = "always";
      RestartSec = 5;
      NoNewPrivileges = true;
    };
    Install.WantedBy = ["default.target"];
  };

  # Publishes the bridge at https://legion-nix.<tailnet>.ts.net:8443 with
  # Tailscale Funnel. Port 443 stays with T3's own Tailscale serve setting.
  # Needs HTTPS certificates and the funnel node attribute in the tailnet,
  # and this user as the tailscale operator.
  systemd.user.services.t3-ask-funnel = let
    tailscale = "${pkgs.tailscale}/bin/tailscale";
  in {
    Unit = {
      Description = "Tailscale Funnel :8443 to the T3 Ask bridge";
      After = ["t3-ask-bridge.service"];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${tailscale} funnel --bg --https=8443 http://127.0.0.1:8789";
      ExecStop = "${tailscale} funnel --https=8443 off";
    };
    Install.WantedBy = ["default.target"];
  };
}
