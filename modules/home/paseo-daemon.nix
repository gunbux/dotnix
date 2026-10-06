# Headless Paseo daemon for hosts without the desktop app managing it.
{
  config,
  pkgs,
  ...
}: {
  imports = [./paseo.nix];

  home.packages = [pkgs.paseo-desktop];

  # Same CLI and daemon as the desktop hosts; ~/.paseo stays daemon-owned.
  systemd.user.services.paseo = {
    Unit = {
      Description = "Paseo coding agent server";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
    };
    Service = {
      Type = "simple";
      # Agent CLIs (claude, codex) come from the Home Manager profile.
      Environment = ["PATH=${config.home.profileDirectory}/bin:/usr/local/bin:/usr/bin:/bin"];
      WorkingDirectory = "%h";
      ExecStart = "${pkgs.paseo-desktop}/bin/paseo daemon run";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 30;
    };
    Install.WantedBy = ["default.target"];
  };
}
