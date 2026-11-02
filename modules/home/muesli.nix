{
  inputs,
  pkgs,
  ...
}: let
  muesli = inputs.muesli.packages.${pkgs.stdenv.hostPlatform.system}.default;
in {
  # Granola-style meeting notes on top of Hex (github.com/gunbux/muesli).
  # It must keep running: Hex deletes meetings 24 hours after they end, and
  # only a running muesli copies them into its own store.
  home.packages = [muesli];

  systemd.user.services.muesli = {
    Unit = {
      Description = "muesli meeting notes on http://127.0.0.1:7878";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${muesli}/bin/muesli app";
      # hex and opencode come from the user profile.
      Environment = [
        "PATH=/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin"
        "MUESLI_SERVER=https://notes.chunyu.sh"
      ];
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
