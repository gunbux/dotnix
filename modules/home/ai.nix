# AI coding agents
{
  config,
  inputs,
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
  # Agent CLIs come from numtide/llm-agents.nix (updated daily, binary cached)
  # rather than nixpkgs. GUI counterparts live in applications.nix.
  llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in {
  home.packages =
    (with llmAgents; [
      crush
      opencode
    ])
    # Not packaged by llm-agents.nix; nixpkgs covers every host platform.
    ++ [pkgs.devin-cli];

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
    package = llmAgents.codex;
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
    package = llmAgents.claude-code;
    enableMcpIntegration = true;
    settings.theme = "dark";
    # Third-party plugins pinned as flake inputs; bump with `nix flake update <input>`.
    # Plugins share ~/.claude/skills with the skill tree above; the attr name is
    # only the directory (the manifest still names it `composio`), so keep it
    # clear of the vendored `composio` skill.
    plugins.composio-plugin-cc = "${inputs.composio-plugin-cc}/plugins/composio";
  };
}
