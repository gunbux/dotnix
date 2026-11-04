{
  config,
  lib,
  pkgs,
  ...
}: {
  options.services.t3-ask-map-funnel.enable = lib.mkEnableOption "the public Garmin map bridge on HTTPS port 443";
  # Bridge for the T3 Ask watch app (gunbux/garmin, t3-ask/): the watch lists
  # and answers T3 Code questions through Tailscale Funnel on :8443.
  # Tokens live outside this public repo, in ~/.config/t3-ask/ (mode 600):
  #   t3-token     T3 bearer token, scopes orchestration:read + operate
  #   watch-token  random token compiled into the watch app
  #   t3-mcp-token optional T3 MCP client token (--subject mcp-client, same
  #                scopes); adds questions from machines linked over T3 Connect
  config.systemd.user.services.t3-ask-bridge = {
    Unit = {
      Description = "T3 Ask bridge for the Garmin watch on http://127.0.0.1:8789";
      After = ["network.target"];
    };
    Service = {
      ExecStart = "${pkgs.t3-ask-bridge}/bin/t3-ask-bridge";
      Environment = [
        "T3_ASK_PORT=8789"
        "HELLORIDE_SESSION_FILE=%h/.config/helloride/session.json"
        "HELLORIDE_WATCH_TOKEN_FILE=%h/.config/helloride/watch-token"
      ];
      Restart = "always";
      RestartSec = 5;
      NoNewPrivileges = true;
    };
    Install.WantedBy = ["default.target"];
  };

  # Publishes the bridge at https://legion-nix.<tailnet>.ts.net:8443 with
  # Tailscale Funnel. The optional map listener claims unused port 443 because
  # the FR165 image service times out on 8443. It must not replace a T3 route.
  # Needs HTTPS certificates and the funnel node attribute in the tailnet,
  # and this user as the tailscale operator.
  config.systemd.user.services.t3-ask-funnel = let
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

  config.systemd.user.services.t3-ask-map-funnel = lib.mkIf config.services.t3-ask-map-funnel.enable {
    Unit = {
      Description = "Garmin map bridge on standard HTTPS port 443";
      Requires = ["t3-ask-funnel.service"];
      After = ["t3-ask-funnel.service"];
    };
    Service = {
      # Reuse the tested read-only guard. A foreground Funnel removes only its
      # own route when this service stops; it never resets other listeners.
      ExecStartPre = "${pkgs.python3}/bin/python3 ${pkgs.writeText "garmin-map-funnel-guard.py" (builtins.readFile ../../pkgs/t3-ask-bridge/funnel_probe.py)}";
      Environment = "PATH=${lib.makeBinPath [pkgs.tailscale]}";
      ExecStart = "${pkgs.tailscale}/bin/tailscale funnel --https=443 http://127.0.0.1:8789";
      Restart = "always";
      RestartSec = 30;
    };
    Install.WantedBy = ["default.target"];
  };
}
