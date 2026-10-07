# Headless Paseo daemon for hosts without the desktop app managing it.
{
  config,
  pkgs,
  ...
}: {
  imports = [./paseo.nix];

  # Plain-node build of the desktop hosts' version. The AppImage's FHS sandbox
  # hides the host's /usr/bin (git, ps, docker) from the daemon and its agents
  # outside NixOS. ~/.paseo stays daemon-owned.
  home.packages = [pkgs.paseo];

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
      ExecStart = "${pkgs.paseo}/bin/paseo-server";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 30;
    };
    Install.WantedBy = ["default.target"];
  };
}
