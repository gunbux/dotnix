{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  pluginDirectory = "${config.xdg.configHome}/swiftbar/plugins";
  workspaceState = "${config.xdg.cacheHome}/swiftbar/paperwm-spaces.json";
  plugin = widget: title:
    pkgs.writeShellScript "swiftbar-${widget}" ''
      # <xbar.title>${title}</xbar.title>
      # <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
      # <swiftbar.refreshOnOpen>${
        if widget == "usage"
        then "false"
        else "true"
      }</swiftbar.refreshOnOpen>
      ${lib.optionalString (widget == "usage") ''
        export PATH=${lib.makeBinPath [config.programs.codex.package config.programs.claude-code.package]}:"$PATH"
      ''}
      exec ${lib.getExe pkgs.python3} ${../../config/swiftbar/menu.py} ${widget} ${lib.optionalString (widget == "workspaces") "--state-file ${lib.escapeShellArg workspaceState}"}
    '';
in {
  home.file = {
    ".hammerspoon/init.lua".text = lib.replaceStrings ["@state_file@"] [workspaceState] (builtins.readFile ../../config/hammerspoon/init.lua);
    ".hammerspoon/cleanup.lua".source = ../../config/hammerspoon/cleanup.lua;
    ".hammerspoon/Spoons/PaperWM.spoon".source = inputs.paperwm;
  };

  home.packages = [pkgs.swiftbar pkgs.stats];

  xdg.configFile = {
    "swiftbar/plugins/workspaces.2s.sh".source = plugin "workspaces" "PaperWM desktops";
    "swiftbar/plugins/clocks.15s.sh".source = plugin "clock" "Singapore and Los Angeles clocks";
    "swiftbar/plugins/media.10s.sh".source = plugin "media" "Now playing";
    "swiftbar/plugins/ai-usage.5m.sh".source = plugin "usage" "Claude and Codex remaining quota";
  };

  targets.darwin.defaults = {
    "com.ameba.SwiftBar" = {
      PluginDirectory = pluginDirectory;
      MakePluginExecutable = false;
      HideSwiftBarIcon = true;
      SUEnableAutomaticChecks = false;
      SUAutomaticallyUpdate = false;
    };
    "eu.exelban.Stats" = {
      # Stats clears first-run preferences unless a version has been recorded.
      version = pkgs.stats.version;
      setupProcess = true;
      CPU_state = true;
      RAM_state = true;
      Disk_state = true;
      Network_state = true;
      GPU_state = false;
      Battery_state = false;
      Bluetooth_state = false;
      Sensors_state = false;
      Clock_state = false;
      Remote_state = false;
      # Let Nix manage the application rather than its built-in updater.
      update-interval = "Never";
    };
  };

  targets.darwin.currentHostDefaults."com.apple.controlcenter".BatteryShowPercentage = true;

  launchd.agents = {
    hammerspoon = {
      enable = true;
      config = {
        Program = "/Applications/Hammerspoon.app/Contents/MacOS/Hammerspoon";
        RunAtLoad = true;
        KeepAlive.Crashed = true;
        ProcessType = "Interactive";
      };
    };
    swiftbar = {
      enable = true;
      config = {
        Program = lib.getExe pkgs.swiftbar;
        RunAtLoad = true;
        KeepAlive.Crashed = true;
        ProcessType = "Interactive";
      };
    };
    stats = {
      enable = true;
      config = {
        Program = "${pkgs.stats}/bin/stats";
        RunAtLoad = true;
        KeepAlive.Crashed = true;
        ProcessType = "Interactive";
      };
    };
  };

  # Apply app preferences before their launch agents read them.
  home.activation.nativeMenuBarReady = lib.hm.dag.entryBetween ["setupLaunchAgents"] ["setDarwinDefaults" "linkGeneration"] ''
    run mkdir -p "${config.xdg.cacheHome}/swiftbar"
    # HM starts new agents before removing old ones; stop Paneru first.
    paneruService="gui/$(id -u)/com.github.karinushka.paneru"
    if /bin/launchctl print "$paneruService" >/dev/null 2>&1; then
      run /bin/launchctl bootout "$paneruService"
    fi
  '';

  # These apps cache preferences; reload them after applying managed settings.
  home.activation.reloadNativeMenuBar = lib.hm.dag.entryAfter ["setupLaunchAgents"] ''
    for agent in hammerspoon swiftbar stats; do
      run /bin/launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.$agent"
    done
  '';
}
