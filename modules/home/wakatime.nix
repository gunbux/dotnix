# WakaTime clients (vim-wakatime, the Claude Code plugin, ...) all run
# wakatime-cli, which reads ~/.wakatime.cfg. Heartbeats go to Wakapi at
# wakapi.chunyu.sh (github.com/gunbux/pinfra, k8s/apps/wakapi.yaml), which
# forwards them to wakatime.com.
#
# The file is read-only and holds no key, because this repo is public and the
# Wakapi key reads and writes all coding history. wakatime-cli and vim-wakatime
# run api_key_vault_cmd instead:
# - Linux: the sops secret wakapi_api_key (modules/sops.nix).
# - macOS: the login Keychain. Store the key once with
#     security add-generic-password -U -a "$USER" -s wakapi-api-key -w
#   (it prompts for the key).
#
# The work Mac hides file, project and branch names for every repo, so no
# work detail leaves the machine. Patterns cannot express "all except X".
#
# wakatime-cli also turns Claude Code and Codex transcripts (T3 Code included)
# into AI heartbeats, but only when an editor runs it. A timer runs
# `wakatime-cli --sync-ai-activity` every 5 minutes, so agent work is sent
# while no editor is open. Neovim uses the same pinned CLI (pkgs/wakatime-cli).
#
# That parsing sends a heartbeat only for prompts and file reads and edits, so
# an agent that runs commands or waits on tools looks idle. The same timer then
# runs wakatime-agent-activity (pkgs/wakatime-agent-activity), which sends one
# heartbeat per active agent minute. Backfill: wakatime-agent-activity --since <ISO time>.
{
  lib,
  pkgs,
  ...
}: let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  cli = lib.getExe pkgs.wakatime-cli;
  agentActivity = lib.getExe pkgs.wakatime-agent-activity;
  syncInterval = 300; # seconds

  # Space-separated executable and arguments, no shell syntax (wakatime-cli).
  vaultCmd =
    if isDarwin
    then "/usr/bin/security find-generic-password -s wakapi-api-key -w"
    else "${pkgs.coreutils}/bin/cat /run/secrets/wakapi_api_key";

  # Commit and merge message buffers are not coding.
  ignore = [
    "COMMIT_EDITMSG$"
    "PULLREQ_EDITMSG$"
    "MERGE_MSG$"
    "TAG_EDITMSG$"
  ];

  settings =
    {
      api_url = "https://wakapi.chunyu.sh/api";
      api_key_vault_cmd = vaultCmd;
    }
    // lib.optionalAttrs isDarwin {
      hide_file_names = "true";
      hide_project_names = "true";
      hide_branch_names = "true";
    };
in
  lib.mkMerge [
    {
      home.packages = [pkgs.wakatime-cli];

      home.file.".wakatime.cfg".text = ''
        [settings]
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k} = ${v}") settings)}
        ignore =
        ${lib.concatMapStringsSep "\n" (p: "    ${p}") ignore}
      '';
    }

    (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      systemd.user.services.wakatime-ai-sync = {
        Unit.Description = "Send Claude Code and Codex activity to Wakapi";
        Service = {
          Type = "oneshot";
          # "-": a failed sync must not skip the agent minutes.
          ExecStart = ["-${cli} --sync-ai-activity" agentActivity];
        };
      };
      systemd.user.timers.wakatime-ai-sync = {
        Unit.Description = "Send Claude Code and Codex activity to Wakapi every 5 minutes";
        Timer = {
          OnStartupSec = "2min";
          OnUnitActiveSec = "${toString syncInterval}s";
        };
        Install.WantedBy = ["timers.target"];
      };
    })

    (lib.mkIf isDarwin {
      launchd.agents.wakatime-ai-sync = {
        enable = true;
        config = {
          ProgramArguments = ["/bin/sh" "-c" "${cli} --sync-ai-activity; exec ${agentActivity}"];
          StartInterval = syncInterval;
          RunAtLoad = true;
          ProcessType = "Background";
        };
      };
    })
  ]
