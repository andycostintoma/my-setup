{
  homeDirectory,
  harness,
  extraCommandSources ? [ ],
  extraSkillSources ? [ ],
  ponytailPackage ? null,
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
    ++ lib.optionals (ponytailPackage != null) [ (ponytailPackage + "/skills") ]
  );

  claudeCommands = mergeHarnessDir "claude-commands" (
    [
      (harness.shared + "/commands")
    ]
    ++ extraCommandSources
    ++ lib.optionals (ponytailPackage != null) [ (ponytailPackage + "/.opencode/command") ]
  );

  claudeAgents =
    (builtins.readFile (harness.shared + "/AGENTS.md"))
    + lib.optionalString (ponytailPackage != null) (
      "\n\n" + builtins.readFile (ponytailPackage + "/AGENTS.md")
    );
in
{
  home.file.".claude/skills" = managed claudeSkills;
  home.file.".claude/commands" = managed claudeCommands;
  home.file.".claude/AGENTS.md" = {
    text = claudeAgents;
    force = true;
  };
  home.file.".claude/plugins/ponytail" = lib.mkIf (ponytailPackage != null) (managed ponytailPackage);

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
