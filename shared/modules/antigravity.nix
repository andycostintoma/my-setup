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

  antigravitySkills = mergeHarnessDir "antigravity-skills" (
    [
      (harness.shared + "/skills")
    ]
    ++ extraSkillSources
  );
in
{
  home.file.".gemini/antigravity-cli/skills" = managed antigravitySkills;
  home.file.".gemini/antigravity-cli/commands" = managed (harness.shared + "/commands");
  home.file.".gemini/GEMINI.md" = managed (harness.shared + "/AGENTS.md");
  home.file.".gemini/AGENTS.md" = managed (harness.shared + "/AGENTS.md");

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
