{
  harness,
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

  codexSkills = mergeHarnessDir "codex-skills" (
    [
      (harness.shared + "/skills")
    ]
    ++ extraSkillSources
    ++ lib.optionals (ponytailPackage != null) [ (ponytailPackage + "/skills") ]
  );

  codexCommands = mergeHarnessDir "codex-commands" (
    [
      (harness.shared + "/commands")
    ]
    ++ lib.optionals (ponytailPackage != null) [ (ponytailPackage + "/.opencode/command") ]
  );

  codexAgents =
    (builtins.readFile (harness.shared + "/AGENTS.md"))
    + lib.optionalString (ponytailPackage != null) (
      "\n\n" + builtins.readFile (ponytailPackage + "/AGENTS.md")
    );
in
{
  home.file.".codex/skills" = managed codexSkills;
  home.file.".codex/commands" = managed codexCommands;
  home.file.".codex/AGENTS.md" = {
    text = codexAgents;
    force = true;
  };
  home.file.".codex/plugins/ponytail" = lib.mkIf (ponytailPackage != null) (managed ponytailPackage);
}
