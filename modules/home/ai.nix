# AI coding agents
{
  config,
  lib,
  pkgs,
  ...
}: let
  sharedSkills = ../../.agents/skills;
in {
  # Keep one repository-owned skill tree for Codex and Claude Code.
  # Codex discovers user skills in ~/.agents/skills; Claude Code receives the
  # same tree through its Home Manager module below.
  home.file.".agents/skills" = {
    source = sharedSkills;
    recursive = true;
    force = true;
  };

  # Take ownership of the existing imperative configuration on the first
  # activation. Authentication and runtime state live at other paths.
  home.file.".codex/config.toml".force = true;
  home.file."${config.home.homeDirectory}/.claude/settings.json".force = true;
  home.file."${config.home.homeDirectory}/.claude/skills".force = true;

  # Define MCP servers once and transform them for each supported client.
  programs.mcp = {
    enable = true;
    servers = {
      railway = {
        command = lib.getExe pkgs.railway;
        args = ["mcp"];
      };

      trek.url = "https://trek.chunyu.sh/mcp";
    };
  };

  programs.codex = {
    enable = true;
    enableMcpIntegration = true;

    settings.projects = {
      "/home/chun/dotnix".trust_level = "trusted";
      "/home/chun/repo/jkeart".trust_level = "trusted";
    };
  };

  programs.claude-code = {
    enable = true;
    enableMcpIntegration = true;
    skills = sharedSkills;
    settings.theme = "dark";
  };
}
