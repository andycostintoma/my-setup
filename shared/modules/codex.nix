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

  codexSkills = mergeHarnessDir "codex-skills" (
    [
      (harness.shared + "/skills")
    ]
    ++ extraSkillSources
  );
in
{
  home.file.".codex/skills" = managed codexSkills;
  home.file.".codex/commands" = managed (harness.shared + "/commands");
  home.file.".codex/AGENTS.md" = managed (harness.shared + "/AGENTS.md");

  home.activation.removeOldCodexHarnessDirectories = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    set -eu

    for target in \
      ${homeDirectory}/.codex/skills \
      ${homeDirectory}/.codex/commands
    do
      if [ -e "$target" ] || [ -L "$target" ]; then
        rm -rf "$target"
      fi
    done
  '';
}
