# Declarative paseo-bots: bots and library MCP servers merged into the
# daemon-owned settings on activation.
{
  config,
  lib,
  osConfig ? null,
  pkgs,
  ...
}: let
  # Upserted by id; fields left out keep the plugin's defaults or what the UI
  # last saved. Edits to these fields in the UI are reverted on the next switch.
  bots = [
    {
      # Keep the id: memory, chats and routines are filed under it.
      id = "bot-mv4nyxty9fxt";
      name = "Voyager";
      title = "Travel";
      description = "Plans trips in TREK and keeps you posted on Telegram.";
      avatar = {
        seed = "voyager-1";
        shape = "circle";
      };
      provider = "claude";
      soul = lib.removeSuffix "\n" (builtins.readFile ../../config/paseo/bots/voyager.md);
      mcpServerIds = ["mcp-trek"];
      # Composio toolkit slugs; the accounts themselves are connected in the UI.
      apps = ["telegram"];
      appRules.telegram.tools = "all";
    }
  ];

  # Library MCP servers.
  mcpServers = [
    {
      id = "mcp-trek";
      name = "trek";
      description = "TREK travel planner (trek.chunyu.sh)";
      # No headers: bots use Claude Code's OAuth login for the server named
      # "trek", keyed on name + sha256 of {type, url, headers}. Log in once:
      #   claude --mcp-config '{"mcpServers":{"trek":{"type":"http","url":"https://trek.chunyu.sh/mcp"}}}'
      # then /mcp -> trek -> Authenticate. Changing name, url or headers needs
      # a new login.
      config = {
        type = "http";
        url = "https://trek.chunyu.sh/mcp";
        headers = {};
      };
    }
  ];

  # Declared in modules/sops.nix on NixOS hosts; elsewhere the daemon's stored
  # key is left alone.
  composioKeyPath = lib.attrByPath ["sops" "secrets" "paseo_bots_composio_api_key" "path"] null (lib.optionalAttrs (osConfig != null) osConfig);

  declared = pkgs.writeText "paseo-bots.json" (builtins.toJSON {inherit bots mcpServers;});

  # Envelope version of paseo-bots' "bots" settings (shared/bot.ts).
  settingsVersion = 3;

  # Shallow-merges declared entries over stored ones by id, keeping fields the
  # daemon owns (createdAt, tool lists, connection checks).
  mergeSettings = pkgs.writeText "paseo-bots-merge.jq" ''
    def upsert($items):
      reduce $items[] as $item (.;
        (map(.id) | index($item.id)) as $at
        | if $at == null then . + [$item + {createdAt: $now, updatedAt: $now}]
          else (.[$at] + $item) as $next
            | .[$at] = (if $next == .[$at] then $next else $next + {updatedAt: $now} end)
          end);

    .version = ${toString settingsVersion}
    | .values.bots = ((.values.bots // []) | upsert($declared[0].bots))
    | .values.library = ({skills: [], mcpServers: []} + (.values.library // {}))
    | .values.library.mcpServers |= upsert($declared[0].mcpServers)
  '';
in {
  home.activation.paseoBots = lib.hm.dag.entryAfter ["writeBoundary"] ''
    paseoBotsJq=${lib.getExe pkgs.jq}
    paseoBotsSettings=${lib.escapeShellArg "${config.home.homeDirectory}/.paseo/plugin-settings/paseo-bots/bots.json"}
    paseoBotsComposio=${lib.escapeShellArg "${config.home.homeDirectory}/.paseo/plugin-data/paseo-bots/composio.json"}

    # Replaces $2 with $1 atomically at mode 0600, unless the JSON is unchanged.
    paseoBotsInstall() {
      chmod 600 "$1"
      if [[ -e $2 ]] && cmp -s <("$paseoBotsJq" -S . "$1") <("$paseoBotsJq" -S . "$2"); then
        rm -f "$1"
      else
        run mv "$1" "$2"
        rm -f "$1"
      fi
    }

    paseoBotsVersion=${toString settingsVersion}
    [[ -e $paseoBotsSettings ]] && paseoBotsVersion=$("$paseoBotsJq" -r '.version' "$paseoBotsSettings")
    if [[ $paseoBotsVersion != ${toString settingsVersion} ]]; then
      warnEcho "paseo-bots: settings are version $paseoBotsVersion, expected ${toString settingsVersion}; update modules/home/paseo-bots.nix. Skipping."
    else
      run mkdir -p "$(dirname "$paseoBotsSettings")"
      paseoBotsTmp=$(mktemp "$paseoBotsSettings.XXXXXX.tmp")
      { [[ -e $paseoBotsSettings ]] && cat "$paseoBotsSettings" || echo '{}'; } \
        | "$paseoBotsJq" -c --slurpfile declared ${declared} \
          --arg now "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" \
          -f ${mergeSettings} >"$paseoBotsTmp"
      paseoBotsInstall "$paseoBotsTmp" "$paseoBotsSettings"
    fi
    ${lib.optionalString (composioKeyPath != null) ''

      # The plugin caches this file in memory: restart Paseo after changing the
      # key. userId owns the connected accounts (Telegram), so it is preserved.
      if [[ -r ${lib.escapeShellArg composioKeyPath} ]]; then
        run mkdir -p "$(dirname "$paseoBotsComposio")"
        paseoBotsTmp=$(mktemp "$paseoBotsComposio.XXXXXX.tmp")
        { [[ -e $paseoBotsComposio ]] && cat "$paseoBotsComposio" || echo '{}'; } \
          | "$paseoBotsJq" --rawfile key ${lib.escapeShellArg composioKeyPath} \
            --arg userId "paseo_bots_$(cat /proc/sys/kernel/random/uuid)" \
            --arg secret "$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')" '
              ($key | rtrimstr("\n")) as $key
              | {userId: $userId, secret: $secret, sessionId: null, mcpUrl: null, port: null} + .
              | if .apiKey == $key then . else . + {apiKey: $key, sessionId: null, mcpUrl: null} end' >"$paseoBotsTmp"
        paseoBotsInstall "$paseoBotsTmp" "$paseoBotsComposio"
      else
        warnEcho "paseo-bots: ${composioKeyPath} is missing; leaving the Composio key alone"
      fi
    ''}
  '';
}
