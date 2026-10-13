{
  inputs,
  lib,
  pkgs,
  ...
}: {
  home.file = {
    ".hammerspoon/init.lua".source = ../../config/hammerspoon/init.lua;
    ".hammerspoon/cleanup.lua".source = ../../config/hammerspoon/cleanup.lua;
    ".hammerspoon/Spoons/PaperWM.spoon".source = inputs.paperwm;
  };

  home.packages = [pkgs.stats];

  targets.darwin.defaults = {
    "eu.exelban.Stats" = {
      # Stats clears first-run preferences unless a version has been recorded.
      version = pkgs.stats.version;
      setupProcess = true;
      CPU_state = true;
      RAM_state = false;
      Disk_state = false;
      Network_state = false;
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
    codexbar = {
      enable = true;
      config = {
        Program = "/Applications/CodexBar.app/Contents/MacOS/CodexBar";
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
    # HM starts new agents before removing old ones; stop Paneru first.
    paneruService="gui/$(id -u)/com.github.karinushka.paneru"
    if /bin/launchctl print "$paneruService" >/dev/null 2>&1; then
      run /bin/launchctl bootout "$paneruService"
    fi
  '';

  # These apps cache preferences; reload them after applying managed settings.
  home.activation.reloadNativeMenuBar = lib.hm.dag.entryAfter ["setupLaunchAgents"] ''
    for agent in hammerspoon codexbar stats; do
      run /bin/launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.$agent"
    done
  '';
}
