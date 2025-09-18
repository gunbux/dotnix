{
  lib,
  pkgs,
  config,
  utils,
  ...
}: let
  cfg = config.gunbux.services.scx_loader;
in {
  options.gunbux.services.scx_loader = {
    enable = lib.mkEnableOption "Enable scx_loader";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.scx.full;
      defaultText = lib.literalExpression "pkgs.scx.full";
      example = lib.literalExpression "pkgs.scx.rustscheds";
      description = ''
        `scx` package to use. `scx.full`, which includes all schedulers, is the default.
        You may choose a minimal package, such as `pkgs.scx.rustscheds`.

        ::: {.note}
        Overriding this does not change the default scheduler; you should set `services.scx.scheduler` for it.
        :::
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.singleLineStr;
      default = [];
      example = [
        "--slice-us 5000"
        "--verbose"
      ];
      description = ''
        Parameters passed to the chosen scheduler at runtime.

        ::: {.note}
        Run `chosen-scx-scheduler --help` to see the available options. Generally,
        each scheduler has its own set of options, and they are incompatible with each other.
        :::
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.scx_loader = {
      description = "DBUS on-demand loader of sched_ext schedulers";

      # SCX service should be started only if the kernel supports sched-ext
      unitConfig.ConditionPathIsDirectory = "/sys/kernel/sched_ext";

      serviceConfig = {
        Type = "dbus";
        BusName = "org.scx.Loader";
        Environment = "RUST_LOG=trace";
        ExecStart = utils.escapeSystemdExecArgs (
          [
            (lib.getExe' cfg.package "scx_loader")
          ]
          ++ cfg.extraArgs
        );
        KillSignal = "SIGINT";
      };

      wantedBy = ["graphical.target"];
    };

    # D-Bus service configuration
    services.dbus = {
      enable = true;
      packages = [
        (pkgs.writeTextFile {
          name = "scx-loader-dbus-service";
          destination = "/share/dbus-1/system-services/org.scx.Loader.service";
          text = ''
            [D-BUS Service]
            Name=org.scx.Loader
            Exec=${utils.escapeSystemdExecArgs (
              [
                (lib.getExe' cfg.package "scx_loader")
              ]
              ++ cfg.extraArgs
            )}
            User=root
            SystemdService=scx_loader.service
          '';
        })
        (pkgs.writeTextFile {
          name = "scx-loader-dbus-conf";
          destination = "/share/dbus-1/system.d/org.scx.Loader.conf";
          text = ''
            <!DOCTYPE busconfig PUBLIC
             "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
             "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
            <busconfig>
            <!-- why do we allow receive_sender here?? -->
                <policy user="root">
                    <allow own="org.scx.Loader"/>
                    <allow send_destination="org.scx.Loader"/>
                    <allow receive_sender="org.scx.Loader"/>
                </policy>
                <policy context="default">
                    <allow send_destination="org.scx.Loader"/>
                    <allow receive_sender="org.scx.Loader"/>
                </policy>
            </busconfig>
          '';
        })
      ];
    };
  };
}
