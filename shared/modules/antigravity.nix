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

  existingSources = builtins.filter builtins.pathExists;

  antigravitySkills = mergeHarnessDir "antigravity-skills" (existingSources (
    [
      (harness.shared + "/skills")
      (harness.antigravity + "/skills")
    ]
    ++ extraSkillSources
    ++ lib.optionals (ponytailPackage != null) [ (ponytailPackage + "/skills") ]
  ));

  antigravityCommands = mergeHarnessDir "antigravity-commands" (existingSources (
    [
      (harness.shared + "/commands")
      (harness.antigravity + "/commands")
    ]
    ++ extraCommandSources
    ++ lib.optionals (ponytailPackage != null) [ (ponytailPackage + "/.opencode/command") ]
  ));

  antigravityAgents =
    (builtins.readFile (harness.shared + "/AGENTS.md"))
    + lib.optionalString (builtins.pathExists (harness.antigravity + "/AGENTS.md")) (
      "\n" + builtins.readFile (harness.antigravity + "/AGENTS.md")
    )
    + lib.optionalString (ponytailPackage != null) (
      "\n\n" + builtins.readFile (ponytailPackage + "/AGENTS.md")
    );
in
{
  home.file.".gemini/antigravity-cli/skills" = managed antigravitySkills;
  home.file.".gemini/antigravity-cli/commands" = managed antigravityCommands;
  home.file.".gemini/antigravity-cli/extensions/ponytail" = lib.mkIf (ponytailPackage != null) (
    managed ponytailPackage
  );
  home.file.".gemini/GEMINI.md" = {
    text = antigravityAgents;
    force = true;
  };
  home.file.".gemini/AGENTS.md" = {
    text = antigravityAgents;
    force = true;
  };
  home.file.".gemini/antigravity/mcp_config.json" = managed (harness.antigravity + "/mcp_config.json");

  home.activation.removeOldAntigravityHarnessDirectories =
    lib.hm.dag.entryBefore [ "linkGeneration" ]
      ''
        set -eu

        for target in \
          ${homeDirectory}/.gemini/antigravity-cli/skills \
          ${homeDirectory}/.gemini/antigravity-cli/commands
        do
          if [ -e "$target" ] || [ -L "$target" ]; then
            rm -rf "$target"
          fi
        done
      '';
}
