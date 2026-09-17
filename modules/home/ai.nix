# AI coding agents
{
  config,
  lib,
  osConfig ? null,
  pkgs,
  ...
}: let
  sharedSkills = ../../.agents/skills;
  skillDirectories = lib.filterAttrs (_: type: type == "directory") (builtins.readDir sharedSkills);
  skillFilesFor = parent:
    lib.mapAttrs' (name: _: {
      name = "${parent}/${name}";
      value = {
        source = sharedSkills + "/${name}";
        force = true;
      };
    })
    skillDirectories;
  globalSkillFiles = skillFilesFor ".agents/skills" // skillFilesFor ".claude/skills";
  mcpServers = import ../mcp-servers.nix {inherit lib pkgs;};
in {
  # Keep one repository-owned skill tree for Codex and Claude Code.
  # Codex discovers user skills in ~/.agents/skills. Claude Code receives the
  # same whole-directory links under ~/.claude/skills.
  home.file =
    globalSkillFiles
    // {
      "${config.home.homeDirectory}/.claude/settings.json".force = true;
    };

  # Migrate the previous recursive installation, whose skill directories were
  # real directories containing per-file links. Later activations see the new
  # directory links and leave them alone.
  home.activation.migrateCodexSkills = lib.hm.dag.entryBetween ["linkGeneration"] ["writeBoundary"] ''
    for rootAndBackup in \
      ${lib.escapeShellArg "${config.home.homeDirectory}/.agents/skills:${config.xdg.stateHome}/home-manager/skill-migration/agents"} \
      ${lib.escapeShellArg "${config.home.homeDirectory}/.claude/skills:${config.xdg.stateHome}/home-manager/skill-migration/claude"}; do
      skillsRoot="''${rootAndBackup%%:*}"
      backupRoot="''${rootAndBackup#*:}"

      for skill in ${lib.escapeShellArgs (builtins.attrNames skillDirectories)}; do
        skillPath=$skillsRoot/$skill
        if [[ -d "$skillPath" && ! -L "$skillPath" ]]; then
          backupPath=$backupRoot/$skill
          if [[ -e "$backupPath" ]]; then
            errorEcho "Cannot migrate $skillPath: backup already exists at $backupPath"
            exit 1
          fi

          run mkdir -p -- "$backupRoot"
          run mv -- "$skillPath" "$backupPath"
        fi
      done
    done
  '';

  # Define MCP servers once and transform them for each supported client.
  programs.mcp = {
    enable = true;
    servers = mcpServers;
  };

  programs.codex = {
    enable = true;
    enableMcpIntegration = osConfig == null;

    settings = lib.mkIf (osConfig == null) {
      projects = {
        "/home/chun/dotnix".trust_level = "trusted";
        "/home/chun/repo/jkeart".trust_level = "trusted";
      };
    };
  };

  programs.claude-code = {
    enable = true;
    enableMcpIntegration = true;
    settings.theme = "dark";
  };
}
