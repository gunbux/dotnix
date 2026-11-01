{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  agents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  linux = pkgs.stdenv.hostPlatform.isLinux;
  paseo = pkgs.symlinkJoin {
    name = "paseo-${agents.paseo.version}";
    paths = [agents.paseo] ++ lib.optionals linux [agents.paseo-desktop];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      for executable in paseo ${lib.optionalString linux "paseo-desktop"}; do
        wrapProgram "$out/bin/$executable" --prefix PATH : ${lib.makeBinPath [pkgs.nodejs]} \
          ${lib.optionalString linux "--set PASEO_SHARED_BROWSER_CHROMIUM_EXECUTABLE ${lib.getExe pkgs.chromium}"}
      done
    '';
  };
  sharedBrowserVersion = "4.1.3";
  pluginSource = src:
    lib.cleanSourceWith {
      inherit src;
      filter = path: _: !(builtins.elem (baseNameOf path) ["node_modules" "tests" "package-lock.json" ".gitignore"]);
    };
in {
  home.packages = [paseo];
  home.file =
    {
      ".local/share/paseo/plugins/paseo-bots".source = pluginSource inputs.paseo-bots;
    }
    // lib.genAttrs [".local/share/paseo/plugins/auto-archive" ".local/share/paseo/plugins/auto-label"] (path: {
      source = pluginSource (../../config/paseo/plugins + "/${baseNameOf path}");
    });

  home.activation.paseoPlugins = lib.hm.dag.entryAfter ["linkGeneration"] ''
    paseoConfig=${lib.escapeShellArg "${config.home.homeDirectory}/.paseo/config.json"}
    if [[ -f "$paseoConfig" ]] && \
       ${lib.getExe pkgs.jq} -e '.pluginsEnabled == true' "$paseoConfig" >/dev/null && \
       ${paseo}/bin/paseo status --json 2>/dev/null | ${lib.getExe pkgs.jq} -e ' .connectedDaemon == "reachable" ' >/dev/null; then
      pluginPath=$(${lib.getExe pkgs.jq} -r '.plugins["shared-browser"].path // empty' "$paseoConfig")
      pluginVersion=""
      if [[ -f "$pluginPath/package.json" ]]; then
        pluginVersion=$(${lib.getExe pkgs.jq} -r '.version' "$pluginPath/package.json")
      fi
      if [[ "$pluginVersion" != ${lib.escapeShellArg sharedBrowserVersion} ]]; then
        if ${lib.getExe pkgs.jq} -e '.plugins["shared-browser"] != null' "$paseoConfig" >/dev/null; then
          run ${paseo}/bin/paseo plugin update shared-browser --version ${sharedBrowserVersion} --yes || warnEcho "Could not update Shared Browser."
        else
          run ${paseo}/bin/paseo plugin install npm:@omercnet/paseo-shared-browser@${sharedBrowserVersion} --id shared-browser || warnEcho "Could not install Shared Browser."
        fi
      fi
      for plugin in auto-archive auto-label paseo-bots; do
        if ${lib.getExe pkgs.jq} -e --arg id "$plugin" '.plugins[$id] != null' "$paseoConfig" >/dev/null; then
          run ${paseo}/bin/paseo plugin reload "$plugin" || warnEcho "Could not reload Paseo plugin $plugin."
        else
          run ${paseo}/bin/paseo plugin install ${lib.escapeShellArg "${config.home.homeDirectory}/.local/share/paseo/plugins"}/"$plugin" || warnEcho "Could not install Paseo plugin $plugin."
        fi
      done
    fi
  '';
}
