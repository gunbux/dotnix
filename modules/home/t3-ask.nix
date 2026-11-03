{pkgs, ...}: {
  # Bridge for the T3 Ask watch app (gunbux/garmin, t3-ask/): the watch lists
  # and answers T3 Code questions through Tailscale Funnel on :8443.
  # Tokens live outside this public repo, in ~/.config/t3-ask/ (mode 600):
  #   t3-token     T3 bearer token, scopes orchestration:read + operate
  #   watch-token  random token compiled into the watch app
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
}
