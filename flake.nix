{
  description = "Andy Toma's minimal Nix, Home Manager, nix-darwin, and direnv setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nix-darwin, home-manager, ... }:
    let
      username = "andytoma";
      host = "Andys-Mac-mini";

      # Plain nixpkgs packages: these update with `nix flake update`.
      userPackagesFromNixpkgs = pkgs: with pkgs; [
        claude-code
        curl
        ffmpeg
        graphviz
        mermaid-cli
        mkcert
        msmtp
        mutt
        nextdns
        nodejs
        ollama
        opencode
        pandoc
        pgcli
        poppler-utils
        ripgrep
        rtk
        p7zip
        tesseract
        tmux
        tree
        uv
        watch
        wget
      ];

      systemPackagesFromNixpkgs = pkgs: with pkgs; [
        discord
        ghostty-bin
        google-chrome
        jetbrains-toolbox
        libreoffice-bin
        teams
        obsidian
        orbstack
        postman
        qbittorrent
        rectangle
        slack
        tailscale
        telegram-desktop
        vscode
        whatsapp-for-mac
        zoom-us
      ];

      # Local packages: not available from nixpkgs for this Mac, or need custom wrapping.
      microsoftEdge = pkgs: pkgs.stdenvNoCC.mkDerivation {
        pname = "microsoft-edge";
        version = "148.0.3967.70";

        src = pkgs.fetchurl {
          name = "MicrosoftEdge-148.0.3967.70.pkg";
          url = "https://go.microsoft.com/fwlink/?linkid=2093504";
          hash = "sha256-24Hhs89fxtEVtDrjnBxBGw2GsVUj/OsygSDYGC5QNqU=";
        };

        nativeBuildInputs = with pkgs; [ cpio gzip makeWrapper xar ];

        dontConfigure = true;
        dontBuild = true;
        dontFixup = true;

        unpackPhase = ''
          runHook preUnpack
          xar -xf $src
          gzip -dc MicrosoftEdge-*.pkg/Payload | cpio -idm
          runHook postUnpack
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p $out/Applications $out/bin
          cp -R "Microsoft Edge.app" $out/Applications/
          makeWrapper "$out/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" $out/bin/microsoft-edge

          runHook postInstall
        '';
      };

      kumospace = pkgs: pkgs.stdenvNoCC.mkDerivation {
        pname = "kumospace";
        version = "6.1.0";

        src = pkgs.fetchurl {
          name = "Kumospace-6.1.0.dmg";
          url = "https://downloads.kumospace.com/production/macos/universal/latest/Kumospace.dmg";
          hash = "sha256-wOf4dabEIsJd5yHWXwlA/+lSrvz6ijVvZHLvswNZSas=";
        };

        nativeBuildInputs = with pkgs; [ makeWrapper undmg ];

        sourceRoot = ".";
        dontConfigure = true;
        dontBuild = true;
        dontFixup = true;

        installPhase = ''
          runHook preInstall

          mkdir -p $out/Applications $out/bin
          cp -R "Kumospace.app" $out/Applications/
          makeWrapper "$out/Applications/Kumospace.app/Contents/MacOS/Kumospace" $out/bin/kumospace

          runHook postInstall
        '';
      };

      # OpenViking has a large Python dependency tree, so Nix pins uv and the package version.
      openviking = pkgs:
        let
          version = "0.3.17";
          uvxOpenViking = "${pkgs.uv}/bin/uvx --from openviking==${version}";
        in
        pkgs.runCommand "openviking-${version}" { } ''
          mkdir -p $out/bin $out/hook-bin

          cat > $out/bin/ov <<'EOF'
          #!${pkgs.runtimeShell}
          exec ${uvxOpenViking} ov "$@"
          EOF

          cat > $out/bin/openviking <<'EOF'
          #!${pkgs.runtimeShell}
          exec ${uvxOpenViking} openviking "$@"
          EOF

          cat > $out/bin/openviking-server <<'EOF'
          #!${pkgs.runtimeShell}
          exec ${uvxOpenViking} openviking-server "$@"
          EOF

          cat > $out/hook-bin/python3 <<'EOF'
          #!${pkgs.runtimeShell}
          exec ${uvxOpenViking} python "$@"
          EOF

          chmod +x $out/bin/ov $out/bin/openviking $out/bin/openviking-server $out/hook-bin/python3
        '';

      userPackages = pkgs:
        userPackagesFromNixpkgs pkgs
        ++ [ (openviking pkgs) ];

      systemPackages = pkgs:
        systemPackagesFromNixpkgs pkgs
        ++ [
          (kumospace pkgs)
          (microsoftEdge pkgs)
        ];

      harness = {
        shared = ./harness/shared;
        claude = ./harness/claude;
        opencode = ./harness/opencode;
      };

      homeModule = { pkgs, lib, ... }:
        let
          openvikingPackage = openviking pkgs;

          managed = source: {
            inherit source;
            force = true;
          };

          managedExecutable = source: {
            inherit source;
            executable = true;
            force = true;
          };

          openvikingClaudeHook = hookScript: ''
            #!${pkgs.runtimeShell}
            export PATH="${openvikingPackage}/hook-bin:${openvikingPackage}/bin:$PATH"

            PROJECT_DIR="''${CLAUDE_PROJECT_DIR:-$(pwd)}"
            if [[ ! -f "$PROJECT_DIR/ov.conf" ]]; then
              export CLAUDE_PROJECT_DIR="$HOME/.claude/ov-hooks"
            fi

            exec bash /Users/${username}/openviking_workspace/viking/default/resources/openviking/examples/claude-memory-plugin/hooks/${hookScript}
          '';
        in
        {
          home.username = username;
          home.homeDirectory = "/Users/${username}";
          home.stateVersion = "25.05";
          home.packages = userPackages pkgs;

          home.file.".zprofile".text = ''
            export LANG=en_US.UTF-8
            export LC_ALL=en_US.UTF-8
          '';

          # Secret OpenViking config stays local in ~/.openviking/ov.conf.
          home.file.".openviking/ovcli.conf".text = ''
            {"url":"http://127.0.0.1:1933"}
          '';

          home.file.".config/opencode/opencode.json" = managed (harness.opencode + "/opencode.json");
          home.file.".config/opencode/settings.json" = managed (harness.opencode + "/settings.json");
          home.file.".config/opencode/package.json" = managed (harness.opencode + "/package.json");
          home.file.".config/opencode/package-lock.json" = managed (harness.opencode + "/package-lock.json");
          home.file.".config/opencode/dcp.jsonc" = managed (harness.opencode + "/dcp.jsonc");
          home.file.".config/opencode/agent-ladder.config.json" = managed (harness.opencode + "/agent-ladder.config.json");
          home.file.".config/opencode/SETUP.md" = managed (harness.opencode + "/SETUP.md");
          home.file.".config/opencode/LOCAL-STACK.md" = managed (harness.shared + "/LOCAL-STACK.md");
          home.file.".config/opencode/scripts" = managed (harness.opencode + "/scripts");
          home.file.".config/opencode/agents" = managed (harness.opencode + "/agents");
          home.file.".config/opencode/skills" = managed (harness.opencode + "/skills");
          home.file.".config/opencode/commands" = managed (harness.shared + "/commands");

          home.file.".claude/CLAUDE.md" = managed (harness.claude + "/CLAUDE.md");
          home.file.".claude/RTK.md" = managed (harness.claude + "/RTK.md");
          home.file.".claude/SETUP.md" = managed (harness.claude + "/SETUP.md");
          home.file.".claude/LOCAL-STACK.md" = managed (harness.shared + "/LOCAL-STACK.md");
          home.file.".claude/settings.json" = managed (harness.claude + "/settings.json");
          home.file.".claude/agents" = managed (harness.claude + "/agents");
          home.file.".claude/skills" = managed (harness.claude + "/skills");
          home.file.".claude/commands" = managed (harness.shared + "/commands");
          home.file.".claude/hooks/rtk-rewrite.sh" = managedExecutable (harness.claude + "/hooks/rtk-rewrite.sh");
          home.file.".claude/hooks/pre-compact.sh" = managedExecutable (harness.claude + "/hooks/pre-compact.sh");

          home.activation.removeOldHarnessDirectories = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
            set -eu

            for target in \
              /Users/${username}/.config/opencode/agents \
              /Users/${username}/.config/opencode/commands \
              /Users/${username}/.config/opencode/scripts \
              /Users/${username}/.config/opencode/skills \
              /Users/${username}/.claude/agents \
              /Users/${username}/.claude/commands \
              /Users/${username}/.claude/skills
            do
              if [ -e "$target" ] || [ -L "$target" ]; then
                rm -rf "$target"
              fi
            done
          '';

          home.activation.publishMutableOpencodeAssets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            set -eu

            opencode_home="/Users/${username}/.config/opencode"
            install -d -m 0755 "$opencode_home/plugins" "$opencode_home/vendor"

            ${pkgs.rsync}/bin/rsync -a --delete \
              --exclude openviking-memory.log \
              --exclude openviking-session-map.json \
              ${harness.opencode}/plugins/ "$opencode_home/plugins/"

            ${pkgs.rsync}/bin/rsync -a --delete \
              ${harness.opencode}/vendor/opencode-claude-auth/ \
              "$opencode_home/vendor/opencode-claude-auth/"

            if [ ! -d "$opencode_home/node_modules/@opencode-ai/plugin" ] \
              || [ "$opencode_home/package-lock.json" -nt "$opencode_home/node_modules/.package-lock.json" ] 2>/dev/null; then
              (cd "$opencode_home" && ${pkgs.nodejs}/bin/npm install --silent --no-audit --no-fund)
            fi
          '';

          home.file.".claude/hooks/ov-session-start.sh" = {
            executable = true;
            text = openvikingClaudeHook "session-start.sh";
          };
          home.file.".claude/hooks/ov-user-prompt.sh" = {
            executable = true;
            text = openvikingClaudeHook "user-prompt-submit.sh";
          };
          home.file.".claude/hooks/ov-stop.sh" = {
            executable = true;
            text = openvikingClaudeHook "stop.sh";
          };
          home.file.".claude/hooks/ov-session-end.sh" = {
            executable = true;
            text = openvikingClaudeHook "session-end.sh";
          };

          launchd.agents.openviking = {
            enable = true;
            config = {
              ProgramArguments = [
                "${openvikingPackage}/bin/openviking-server"
                "--config"
                "/Users/${username}/.openviking/ov.conf"
                "--host"
                "127.0.0.1"
                "--port"
                "1933"
              ];
              RunAtLoad = true;
              KeepAlive = true;
              WorkingDirectory = "/Users/${username}";
              StandardOutPath = "/Users/${username}/Library/Logs/openviking-server.log";
              StandardErrorPath = "/Users/${username}/Library/Logs/openviking-server.error.log";
              EnvironmentVariables = {
                HOME = "/Users/${username}";
                PATH = "${pkgs.coreutils}/bin:${pkgs.bash}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
              };
            };
          };

          programs.home-manager.enable = true;

          programs.direnv = {
            enable = true;
            nix-direnv.enable = true;
            enableZshIntegration = true;
          };

          programs.zsh = {
            enable = true;
            autosuggestion.enable = true;
            syntaxHighlighting.enable = true;
            oh-my-zsh = {
              enable = true;
              theme = "robbyrussell";
              plugins = [ "git" ];
            };
            shellAliases = {
              medidrive = "ssh -i ~/.ssh/medidrive_key -o IdentitiesOnly=yes -t andy@35.243.44.225 'cd ~/medidrive && exec $SHELL -l'";
              medidrive-sync = "rsync -az --delete -e 'ssh -i ~/.ssh/medidrive_key -o IdentitiesOnly=yes' andy@35.243.44.225:~/medidrive/ ~/medidrive-local/";
              hm-switch = "home-manager switch --flake ~/.config/nix-darwin";
              nix-switch = "sudo darwin-rebuild switch --flake ~/.config/nix-darwin";
            };
          };

          programs.git.enable = true;
          programs.gh.enable = true;
          programs.jq.enable = true;
        };
    in
    {
      darwinConfigurations.${host} = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          ({ pkgs, ... }: {
            nixpkgs.config.allowUnfree = true;
            nix.settings.experimental-features = [ "nix-command" "flakes" ];
            nix.gc = {
              automatic = true;
              interval = { Weekday = 0; Hour = 3; Minute = 15; };
              options = "--delete-older-than 14d";
            };
            nix.optimise.automatic = true;

            users.users.${username}.home = "/Users/${username}";
            environment.systemPackages = systemPackages pkgs;

            programs.zsh.enable = true;

            system.primaryUser = username;
            system.stateVersion = 5;
          })
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "before-nix-darwin";
            home-manager.users.${username} = homeModule;
          }
        ];
      };
    };
}
