# Capy Dock: makes this machine a device that Capy cloud-agent threads run on.
# Pair once per machine by running `capy dock` in a terminal and approving the
# code at https://capy.ai/settings/devices, then stop it and restart the
# service (`systemctl --user restart capy-dock` or
# `launchctl kickstart -k gui/$UID/org.nix-community.home.capy-dock`).
# Until then the service sees "not paired" and exits cleanly.
{
  config,
  lib,
  pkgs,
  ...
}: let
  capy = lib.getExe pkgs.capy-dock;
  home = config.home.homeDirectory;
  # Threads run commands as this user, so give the daemon the login PATH
  # rather than the bare service PATH. git and gh are Dock's own requirements.
  path = lib.concatStringsSep ":" (
    lib.optionals pkgs.stdenv.hostPlatform.isLinux ["/run/wrappers/bin"]
    ++ [
      "${config.home.profileDirectory}/bin"
      "/etc/profiles/per-user/${config.home.username}/bin"
      "/run/current-system/sw/bin"
      "/nix/var/nix/profiles/default/bin"
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin ["/opt/homebrew/bin"]
    ++ [
      "/usr/local/bin"
      "/usr/bin"
      "/bin"
      "/usr/sbin"
      "/sbin"
      "${pkgs.git}/bin"
      "${pkgs.gh}/bin"
    ]
  );
  start = pkgs.writeShellScript "capy-dock-start" ''
    export PATH=${lib.escapeShellArg path}
    if ${capy} dock status 2>&1 | ${pkgs.gnugrep}/bin/grep -q 'not paired'; then
      echo "capy dock: not paired; run 'capy dock' in a terminal once" >&2
      exit 0
    fi
    exec ${capy} dock
  '';
in
  lib.mkMerge [
    {home.packages = [pkgs.capy-dock];}

    (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      systemd.user.services.capy-dock = {
        Unit.Description = "Capy Dock device daemon";
        Service = {
          ExecStart = "${start}";
          Restart = "on-failure";
          RestartSec = 30;
        };
        Install.WantedBy = ["default.target"];
      };
    })

    (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      launchd.agents.capy-dock = {
        enable = true;
        config = {
          Program = "${start}";
          RunAtLoad = true;
          KeepAlive.SuccessfulExit = false;
          ThrottleInterval = 30;
          ProcessType = "Background";
          StandardOutPath = "${home}/Library/Logs/capy-dock.log";
          StandardErrorPath = "${home}/Library/Logs/capy-dock.log";
        };
      };
    })
  ]
