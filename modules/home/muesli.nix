{
  inputs,
  pkgs,
  ...
}: let
  packages = inputs.muesli.packages.${pkgs.stdenv.hostPlatform.system};
  muesli = packages.default;
  overlay = packages.overlay;
  # hex, opencode, pw-play, wl-copy, and gdbus come from the user profile
  # and the system.
  path = "PATH=/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin";
in {
  # Granola-style meeting notes on top of Hex (github.com/gunbux/muesli).
  # `muesli app` keeps the notes: it copies each Hex meeting when it ends, and
  # enhances and shares it. `muesli-overlay` is the Hex-style capsule; Alt+M
  # in config/niri/binds.kdl presses it.
  home.packages = [muesli overlay];

  systemd.user.services.muesli = {
    Unit = {
      Description = "muesli meeting notes on http://127.0.0.1:7878";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${muesli}/bin/muesli app";
      Environment = [
        path
        "MUESLI_SERVER=https://notes.chunyu.sh"
        # Enhance and share every meeting the app saw recording; put the
        # link on the clipboard and send a notification.
        "MUESLI_AUTO=share"
        "MUESLI_NOTIFY=1"
      ];
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  # Runs all session long, so a meeting started anywhere (Hex's tray, a call
  # offer, the web page) shows the capsule. --background starts no meeting.
  systemd.user.services.muesli-overlay = {
    Unit = {
      Description = "muesli meeting capsule";
      After = ["graphical-session.target" "muesli.service"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${overlay}/bin/muesli-overlay --background";
      Environment = [path];
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
