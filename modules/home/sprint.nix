# Local Grafana for the sprint log (pkgs/sprint). Runs as this user on
# http://127.0.0.1:3001 with anonymous read-only access and no login:
# a systemd user service on Linux, a launchd agent on macOS.
# The log lives in ~/.local/state/sprint/sprint.db and never leaves the
# machine; only the dashboard (./sprint/dashboard.nix) is in this public repo.
# Business Text panels render the goal and the context sections as Markdown.
{
  config,
  lib,
  pkgs,
  ...
}: let
  port = 3001;
  db = "${config.xdg.stateHome}/sprint/sprint.db";
  dataDir = "${config.xdg.stateHome}/sprint-grafana";

  plugins = pkgs.linkFarm "sprint-grafana-plugins" [
    {
      name = "frser-sqlite-datasource";
      path = pkgs.grafanaPlugins.frser-sqlite-datasource;
    }
    {
      name = "marcusolsson-dynamictext-panel";
      path = pkgs.grafanaPlugins.marcusolsson-dynamictext-panel;
    }
  ];

  yaml = pkgs.formats.yaml {};
  dashboard = pkgs.writeText "sprint.json" (builtins.toJSON (import ./sprint/dashboard.nix));
  dashboards = pkgs.linkFarm "sprint-grafana-dashboards" [
    {
      name = "sprint.json";
      path = dashboard;
    }
  ];

  # Grafana expands $SPRINT_DB from the service environment, so a second
  # instance can point the same provisioning at a demo database.
  datasource = yaml.generate "sprint-datasource.yaml" {
    apiVersion = 1;
    datasources = [
      {
        name = "Sprint log";
        type = "frser-sqlite-datasource";
        uid = "sprint-sqlite";
        access = "proxy";
        isDefault = true;
        editable = false;
        jsonData = {
          path = "$SPRINT_DB";
          pathPrefix = "file:";
          # A dashboard runs its panel queries at once. Without a busy
          # timeout some of them fail with SQLITE_BUSY.
          pathOptions = "_pragma=query_only(1)&_pragma=busy_timeout(5000)";
          attachLimit = 0;
        };
      }
    ];
  };
  dashboardProvider = yaml.generate "sprint-dashboards.yaml" {
    apiVersion = 1;
    providers = [
      {
        name = "sprint";
        type = "file";
        disableDeletion = true;
        allowUiUpdates = false;
        options.path = "${dashboards}";
      }
    ];
  };
  # Grafana logs an error for each provisioning folder that is missing.
  provisioning = pkgs.runCommand "sprint-grafana-provisioning" {} ''
    mkdir -p $out/{datasources,dashboards,plugins,alerting}
    ln -s ${datasource} $out/datasources/sprint.yaml
    ln -s ${dashboardProvider} $out/dashboards/sprint.yaml
  '';

  ini = (pkgs.formats.ini {}).generate "sprint-grafana.ini" {
    server = {
      http_addr = "127.0.0.1";
      http_port = port;
      root_url = "http://127.0.0.1:${toString port}/";
    };
    paths = {
      data = dataDir;
      logs = "${dataDir}/log";
      plugins = "${plugins}";
      provisioning = "${provisioning}";
    };
    log.mode = "console";
    auth.disable_login_form = true;
    "auth.basic".enabled = false;
    "auth.anonymous" = {
      enabled = true;
      org_role = "Viewer";
    };
    users.allow_sign_up = false;
    dashboards.default_home_dashboard_path = "${dashboard}";
    plugins.preinstall_disabled = true;
    analytics = {
      reporting_enabled = false;
      check_for_updates = false;
      check_for_plugin_updates = false;
      feedback_links_enabled = false;
    };
    news.news_feed_enabled = false;
  };
  # Shared by systemd and launchd: launchd has no ExecStartPre.
  start = pkgs.writeShellScript "sprint-grafana-start" ''
    set -eu
    export SPRINT_DB=${db}
    ${pkgs.coreutils}/bin/mkdir -p ${dataDir}/log
    ${lib.getExe pkgs.sprint} --db ${db} init
    exec ${lib.getExe' pkgs.grafana "grafana"} server --homepath ${pkgs.grafana}/share/grafana --config ${ini}
  '';
  description = "Grafana sprint dashboard on http://127.0.0.1:${toString port}";
in
  lib.mkMerge [
    {home.packages = [pkgs.sprint];}

    (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      systemd.user.services.sprint-dashboard = {
        Unit.Description = description;
        Service = {
          ExecStart = "${start}";
          Restart = "on-failure";
          RestartSec = 5;
          NoNewPrivileges = true;
        };
        Install.WantedBy = ["default.target"];
      };
    })

    (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      launchd.agents.sprint-dashboard = {
        enable = true;
        config = {
          Program = "${start}";
          RunAtLoad = true;
          KeepAlive.SuccessfulExit = false;
          ThrottleInterval = 30;
          ProcessType = "Background";
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/sprint-dashboard.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/sprint-dashboard.log";
        };
      };
    })
  ]
