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

  antigravitySkills = mergeHarnessDir "antigravity-skills" (
    [
      (harness.shared + "/skills")
    ]
    ++ extraSkillSources
    ++ lib.optionals (ponytailPackage != null) [ (ponytailPackage + "/skills") ]
  );

  antigravityCommands = mergeHarnessDir "antigravity-commands" (
    [
      (harness.shared + "/commands")
    ]
    ++ extraCommandSources
    ++ lib.optionals (ponytailPackage != null) [ (ponytailPackage + "/.opencode/command") ]
  );

  antigravityAgents =
    (builtins.readFile (harness.shared + "/AGENTS.md"))
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
  home.file.".gemini/antigravity/mcp_config.json" = {
    text = builtins.toJSON {
      mcpServers = {
        playwright = {
          command = "npx";
          args = [
            "-y"
            "@playwright/mcp@latest"
            "--isolated"
          ];
        };
      };
    };
    force = true;
  };

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
