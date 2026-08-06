{
  homeDirectory,
  harness,
  extraPluginSources ? [ ],
  extraSkillSources ? [ ],
  opencodeConfig,
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

  opencodeAgents = mergeHarnessDir "opencode-agents" (existingSources [
    (harness.shared + "/agents")
    (harness.opencode + "/agents")
  ]);

  opencodeSkills = mergeHarnessDir "opencode-skills" (
    [
      (harness.shared + "/skills")
    ]
    ++ extraSkillSources
  );

  opencodeCommands = mergeHarnessDir "opencode-commands" (
    [
      (harness.shared + "/commands")
    ]
    ++ lib.optionals (ponytailPackage != null) [ (ponytailPackage + "/.opencode/command") ]
  );

  opencodeNodeModules = pkgs.importNpmLock.buildNodeModules {
    npmRoot = harness.opencode;
    nodejs = pkgs.nodejs;
    derivationArgs = {
      pname = "opencode-plugin-dependencies-node-modules";
      version = "1.4.10";
    };
  };

  opencodeAgentsText =
    (builtins.readFile (harness.shared + "/AGENTS.md"))
    + lib.optionalString (builtins.pathExists (harness.opencode + "/AGENTS.md")) (
      "\n" + builtins.readFile (harness.opencode + "/AGENTS.md")
    );
in
{
  home.file.".config/opencode/opencode.json" = managed opencodeConfig;
  home.file.".config/opencode/AGENTS.md" = {
    text = opencodeAgentsText;
    force = true;
  };
  home.file.".config/opencode/package.json" = managed (harness.opencode + "/package.json");
  home.file.".config/opencode/package-lock.json" = managed (harness.opencode + "/package-lock.json");
  home.file.".config/opencode/node_modules" = managed (opencodeNodeModules + "/node_modules");
  home.file.".config/opencode/dcp.jsonc" = managed (harness.opencode + "/dcp.jsonc");
  home.file.".config/opencode/docs" = managed (harness.opencode + "/docs");
  home.file.".config/opencode/scripts" = managed (harness.opencode + "/scripts");
  home.file.".config/opencode/agents" = managed opencodeAgents;
  home.file.".config/opencode/skills" = managed opencodeSkills;
  home.file.".config/opencode/commands" = managed opencodeCommands;

  # ponytail: one-time cleanup of plugins/state removed in 175dca5; drop this
  # block once both machines have switched at least once past that commit.
  home.activation.removeStaleOpencodeState = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    set -eu

    opencode_home="${homeDirectory}/.config/opencode"
    rm -rf "$opencode_home/plugins/openviking" "$opencode_home/plugins/automation" "$opencode_home/services"
    rm -rf "${homeDirectory}/.local/state/opencode/openviking" "${homeDirectory}/.local/state/opencode/context-broker"
  '';

  home.activation.publishOpencodePluginSources = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    set -eu

    opencode_home="${homeDirectory}/.config/opencode"
    install -d -m 0755 "$opencode_home/plugins"

    # opencode loads TypeScript plugins and custom tools by real path.
    # Individual Nix-store symlinks break relative imports and node_modules
    # resolution, so copy these source trees instead of symlinking them.
    ${pkgs.rsync}/bin/rsync -a --delete --chmod=D755,F644 \
      ${harness.opencode}/plugins/ "$opencode_home/plugins/"
    ${lib.concatMapStringsSep "\n" (source: ''
      ${pkgs.rsync}/bin/rsync -a --chmod=D755,F644 \
        ${source}/ "$opencode_home/plugins/"
    '') extraPluginSources}
    ${lib.optionalString (ponytailPackage != null) ''
      ${pkgs.rsync}/bin/rsync -a --delete --chmod=D755,F644 \
        ${ponytailPackage}/ "$opencode_home/plugins/ponytail/"
    ''}
  '';
}
