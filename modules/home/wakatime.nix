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
{
  lib,
  pkgs,
  ...
}: let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

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
in {
  home.file.".wakatime.cfg".text = ''
    [settings]
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k} = ${v}") settings)}
    ignore =
    ${lib.concatMapStringsSep "\n" (p: "    ${p}") ignore}
  '';
}
