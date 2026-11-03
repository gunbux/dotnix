# Status pages for the sprint log (pkgs/sprint), served by `sprint serve` on
# http://127.0.0.1:3001 as this user: a systemd user service on Linux, a
# launchd agent on macOS. The log lives in ~/.local/state/sprint/sprint.db and
# never leaves the machine.
{
  config,
  lib,
  pkgs,
  ...
}: let
  port = 3001;
  db = "${config.xdg.stateHome}/sprint/sprint.db";
  serve = [(lib.getExe pkgs.sprint) "--db" db "serve" "--host" "127.0.0.1" "--port" (toString port)];
  description = "Sprint status pages on http://127.0.0.1:${toString port}";
in
  lib.mkMerge [
    {home.packages = [pkgs.sprint];}

    (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      systemd.user.services.sprint-page = {
        Unit.Description = description;
        Service = {
          ExecStart = lib.escapeShellArgs serve;
          Restart = "on-failure";
          RestartSec = 5;
          NoNewPrivileges = true;
        };
        Install.WantedBy = ["default.target"];
      };
    })

    (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      launchd.agents.sprint-page = {
        enable = true;
        config = {
          ProgramArguments = serve;
          RunAtLoad = true;
          KeepAlive.SuccessfulExit = false;
          ThrottleInterval = 30;
          ProcessType = "Background";
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/sprint-page.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/sprint-page.log";
        };
      };
    })
  ]
