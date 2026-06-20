{
  homeDirectory,
  harness,
  extraSkillSources ? [ ],
}:

{ pkgs, lib, ... }:
let
  managed = source: {
    inherit source;
    force = true;
  };

  mergeHarnessDir =
    name: sources:
    pkgs.runCommand name { } (
      ''
        mkdir -p $out
      ''
      + lib.concatMapStringsSep "\n" (source: ''
        chmod -R u+w $out
        cp -Rf ${source}/. $out/
      '') sources
    );

  claudeSkills = mergeHarnessDir "claude-skills" (
    [
      (harness.shared + "/skills")
    ]
    ++ extraSkillSources
  );
in
{
  home.file.".claude/skills" = managed claudeSkills;
  home.file.".claude/commands" = managed (harness.shared + "/commands");
  home.file.".claude/AGENTS.md" = managed (harness.shared + "/AGENTS.md");

  home.activation.removeOldClaudeHarnessDirectories = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    set -eu

    for target in \
      ${homeDirectory}/.claude/skills \
      ${homeDirectory}/.claude/commands
    do
      if [ -e "$target" ] || [ -L "$target" ]; then
        rm -rf "$target"
      fi
    done
  '';
}
