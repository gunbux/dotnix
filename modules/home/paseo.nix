{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  # Plugin name -> enabled. Applied to registered plugins on activation.
  localPlugins = {
    auto-archive = true;
    auto-label = true;
    cloud-agents = true;
    # Disabled for now: too buggy.
    telegram-bridge = false;
  };
  # Third-party plugins pinned as flake inputs; bump with `nix flake update <input>`.
  externalPlugins = {paseo-bots = inputs.paseo-bots;};
  pluginSource = src:
    lib.cleanSourceWith {
      inherit src;
      filter = path: type: let
        file = baseNameOf path;
      in
        !(builtins.elem file ["node_modules" "tests" ".gitignore" "package-lock.json"]);
    };
  linkPlugin = name: src:
    lib.nameValuePair ".local/share/paseo/plugins/${name}" {source = pluginSource src;};
  pluginStates = localPlugins // lib.mapAttrs (_: _: true) externalPlugins;
in {
  imports = [./paseo-bots.nix];

  # Source is declarative; plugin data, settings, and registration remain daemon-owned.
  # Register a new plugin once with `paseo plugin install ~/.local/share/paseo/plugins/<name>`.
  home.file =
    lib.mapAttrs' (name: _: linkPlugin name (../../config/paseo/plugins + "/${name}")) localPlugins
    // lib.mapAttrs' linkPlugin externalPlugins;

  # Toggles through the running daemon when reachable, since it rewrites
  # config.json from memory; otherwise edits config.json for the next start.
  home.activation.paseoPlugins = lib.hm.dag.entryAfter ["writeBoundary"] ''
    paseoPluginsJq=${lib.getExe pkgs.jq}
    paseoPluginsConfig=${lib.escapeShellArg "${config.home.homeDirectory}/.paseo/config.json"}
    if [[ -e $paseoPluginsConfig ]]; then
      ${lib.concatStrings (lib.mapAttrsToList (name: enabled: let
        action =
          if enabled
          then "enable"
          else "disable";
      in ''
        if [[ $("$paseoPluginsJq" -r --arg id ${name} '.plugins[$id] | if . == null then "unregistered" else .enabled end' "$paseoPluginsConfig") == ${lib.boolToString (!enabled)} ]]; then
          if ! run ${pkgs.paseo-desktop}/bin/paseo plugin ${action} ${name} >/dev/null 2>&1; then
            paseoPluginsTmp=$(mktemp "$paseoPluginsConfig.XXXXXX.tmp")
            "$paseoPluginsJq" --arg id ${name} '.plugins[$id].enabled = ${lib.boolToString enabled}' "$paseoPluginsConfig" >"$paseoPluginsTmp"
            chmod 600 "$paseoPluginsTmp"
            run mv "$paseoPluginsTmp" "$paseoPluginsConfig"
            rm -f "$paseoPluginsTmp"
          fi
        fi
      '')
      pluginStates)}
    fi
  '';
}
