{
  homeDirectory,
  harness,
  opencodeConfig ? harness.opencode + "/opencode.json",
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
        cp -R ${source}/. $out/
      '') sources
    );

  opencodeAgents = mergeHarnessDir "opencode-agents" [
    (harness.shared + "/agents")
    (harness.opencode + "/agents")
  ];

  opencodeSkills = mergeHarnessDir "opencode-skills" [
    (harness.shared + "/skills")
  ];

  opencodeNodeModules = pkgs.importNpmLock.buildNodeModules {
    npmRoot = harness.opencode;
    nodejs = pkgs.nodejs;
    derivationArgs = {
      pname = "opencode-plugin-dependencies-node-modules";
      version = "1.4.10";
    };
  };
in
{
  # Secret OpenViking config stays local in ~/.openviking/ov.conf.
  home.file.".openviking/ovcli.conf".text = ''
    {"url":"http://127.0.0.1:1933"}
  '';

  home.file.".config/opencode/opencode.json" = managed opencodeConfig;
  home.file.".config/opencode/settings.json" = managed (harness.opencode + "/settings.json");
  home.file.".config/opencode/package.json" = managed (harness.opencode + "/package.json");
  home.file.".config/opencode/package-lock.json" = managed (harness.opencode + "/package-lock.json");
  home.file.".config/opencode/node_modules" = managed (opencodeNodeModules + "/node_modules");
  home.file.".config/opencode/services" = managed (harness.opencode + "/services");
  home.file.".config/opencode/dcp.jsonc" = managed (harness.opencode + "/dcp.jsonc");
  home.file.".config/opencode/docs" = managed (harness.opencode + "/docs");
  home.file.".config/opencode/LOCAL-STACK.md" = managed (harness.shared + "/LOCAL-STACK.md");
  home.file.".config/opencode/scripts" = managed (harness.opencode + "/scripts");
  home.file.".config/opencode/agents" = managed opencodeAgents;
  home.file.".config/opencode/skills" = managed opencodeSkills;
  home.file.".config/opencode/commands" = managed (harness.shared + "/commands");

  home.activation.removeOldOpencodeHarnessDirectories = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    set -eu

    for target in \
      ${homeDirectory}/.config/opencode/agents \
      ${homeDirectory}/.config/opencode/commands \
      ${homeDirectory}/.config/opencode/scripts \
      ${homeDirectory}/.config/opencode/skills
    do
      if [ -e "$target" ] || [ -L "$target" ]; then
        rm -rf "$target"
      fi
    done
  '';

  home.activation.migrateOpencodePluginState = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    set -eu

    opencode_home="${homeDirectory}/.config/opencode"
    state_dir="${homeDirectory}/.local/state/opencode/openviking"
    install -d -m 0755 "$opencode_home/plugins" "$state_dir"

    for file in openviking-memory.log openviking-session-map.json; do
      if [ -e "$opencode_home/plugins/$file" ] && [ ! -e "$state_dir/$file" ]; then
        mv "$opencode_home/plugins/$file" "$state_dir/$file"
      fi
      rm -f "$opencode_home/plugins/$file"
    done

    for file in \
      auto-explore.ts \
      auto-recall.ts \
      claude-auth.ts \
      graphify.ts \
      openviking-context.ts \
      openviking-config.json \
      openviking-memory.ts \
      rtk.ts \
      sound-notify.ts
    do
      rm -f "$opencode_home/plugins/$file" "$opencode_home/plugins/$file.before-my-setup"
    done

    # The scripts/ directory is managed entirely by home-manager (a Nix-store
    # symlink), so any stale generate-agent-ladder.mjs is replaced atomically by
    # linkGeneration. Do not rm inside that read-only symlinked tree.
    rm -f \
      "$opencode_home/SETUP.md" \
      "$opencode_home/ollama-opencode-proxy.js" \
      "$opencode_home/ollama-opencode-proxy.ts" \
      "$opencode_home/plugins/graphify.js" \
      "$opencode_home/plugins/openviking-context.js"

    if [ -e "$opencode_home/vendor" ] || [ -L "$opencode_home/vendor" ]; then
      chmod -R u+w "$opencode_home/vendor" 2>/dev/null || true
      rm -rf "$opencode_home/vendor"
    fi
  '';

  home.activation.publishOpencodePluginSources = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    set -eu

    opencode_home="${homeDirectory}/.config/opencode"
    install -d -m 0755 "$opencode_home/plugins"

    # opencode loads TypeScript plugins by real path. Individual Nix-store
    # symlinks break relative imports and node_modules resolution, so copy
    # this source tree while keeping plugin state out of it.
    ${pkgs.rsync}/bin/rsync -a --delete --chmod=D755,F644 \
      ${harness.opencode}/plugins/ "$opencode_home/plugins/"
  '';
}
