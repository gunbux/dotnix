{inputs, ...}: {
  # PR review dashboard (github.com/gunbux/prview). Also links the prview skill
  # into ~/.claude/skills and ~/.agents/skills.
  imports = [inputs.prview.homeManagerModules.default];

  programs.prview.enable = true;
}
