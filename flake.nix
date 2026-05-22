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
        atlas
        claude-code
        curl
        docker-compose
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
        ty
        uv
        watch
        wget
        yt-dlp
        python3Packages.youtube-transcript-api
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

          cat > $out/bin/vikingbot <<'EOF'
          #!${pkgs.runtimeShell}
          exec ${uvxOpenViking} vikingbot "$@"
          EOF

          cat > $out/hook-bin/python3 <<'EOF'
          #!${pkgs.runtimeShell}
          exec ${uvxOpenViking} python "$@"
          EOF

          chmod +x $out/bin/ov $out/bin/openviking $out/bin/openviking-server $out/bin/vikingbot $out/hook-bin/python3
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

          mergeHarnessDir = name: sources:
            pkgs.runCommand name { } (
              ''
                mkdir -p $out
              ''
              + lib.concatMapStringsSep "\n" (source: ''
                cp -R ${source}/. $out/
              '') sources
            );

          claudeAgents = mergeHarnessDir "claude-agents" [
            (harness.shared + "/agents")
          ];

          claudeSkills = mergeHarnessDir "claude-skills" [
            (harness.shared + "/skills")
          ];

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

          home.file.".bash_profile" = {
            force = true;
            text = ''
              export LANG=en_US.UTF-8
              export LC_ALL=en_US.UTF-8
            '';
          };

          home.file.".bashrc" = {
            force = true;
            text = ''
              # Bash customizations are managed by Nix/Home Manager.
            '';
          };

          home.file."Library/Application Support/Code/User/settings.json" = {
            force = true;
            text = ''
              {
                "vscode-edge-devtools.mirrorEdits": true,
                "emmet.showSuggestionsAsSnippets": true,
                "emmet.triggerExpansionOnTab": true,
                "terminal.integrated.defaultProfile.windows": "PowerShell",
                "workbench.iconTheme": "vscode-icons",
                "extensions.autoCheckUpdates": false,
                "extensions.autoUpdate": false,
                "files.exclude": {
                  "**/bin": true,
                  "**/obj": true,
                  "**/.classpath": true,
                  "**/.project": true,
                  "**/.settings": true,
                  "**/.factorypath": true
                },
                "explorer.compactFolders": false,
                "editor.suggestSelection": "first",
                "redhat.telemetry.enabled": false,
                "editor.inlineSuggest.enabled": true,
                "git.confirmSync": false,
                "git.enableSmartCommit": true,
                "json.maxItemsComputed": 6000,
                "editor.unicodeHighlight.nonBasicASCII": false,
                "git.autofetch": true,
                "vs-kubernetes": {
                  "vscode-kubernetes.helm-path.windows": "C:\\Users\\andyt\\.vs-kubernetes\\tools\\helm\\windows-amd64\\helm.exe",
                  "vscode-kubernetes.minikube-path.windows": "C:\\Users\\andyt\\.vs-kubernetes\\tools\\minikube\\windows-amd64\\minikube.exe",
                  "vs-kubernetes.crd-code-completion": "enabled"
                },
                "yaml.schemas": {
                  "Kubernetes": "*.yaml"
                },
                "files.associations": {
                  "*.yml": "ansible",
                  "*.j2": "ansible",
                  "*.yaml": "yaml"
                },
                "remote.SSH.remotePlatform": {
                  "10.13.173.144": "linux",
                  "10.13.173.106": "linux",
                  "10.13.79.12": "linux",
                  "10.13.174.205": "windows",
                  "10.13.173.115": "linux"
                },
                "diffEditor.ignoreTrimWhitespace": false,
                "tabnine.experimentalAutoImports": true,
                "[python]": {
                  "editor.formatOnType": true
                },
                "editor.formatOnSave": true,
                "aws.telemetry": false,
                "yaml.customTags": [
                  "!And",
                  "!And sequence",
                  "!If",
                  "!If sequence",
                  "!Not",
                  "!Not sequence",
                  "!Equals",
                  "!Equals sequence",
                  "!Or",
                  "!Or sequence",
                  "!FindInMap",
                  "!FindInMap sequence",
                  "!Base64",
                  "!Join",
                  "!Join sequence",
                  "!Cidr",
                  "!Ref",
                  "!Sub",
                  "!Sub sequence",
                  "!GetAtt",
                  "!GetAZs",
                  "!ImportValue",
                  "!ImportValue sequence",
                  "!Select",
                  "!Select sequence",
                  "!Split",
                  "!Split sequence"
                ],
                "security.workspace.trust.untrustedFiles": "open",
                "quarkus.tools.alwaysShowWelcomePage": false,
                "ansible.lightspeed.enabled": true,
                "ansible.lightspeed.suggestions.enabled": true,
                "[ruby]": {
                  "editor.defaultFormatter": "Shopify.ruby-lsp",
                  "editor.formatOnSave": true,
                  "editor.formatOnType": true,
                  "editor.tabSize": 2,
                  "editor.insertSpaces": true,
                  "editor.semanticHighlighting.enabled": true
                },
                "files.trimTrailingWhitespace": true,
                "files.insertFinalNewline": true,
                "editor.rulers": [120],
                "editor.formatOnPaste": true,
                "cSpell.autoFormatConfigFile": true,
                "editor.formatOnType": true,
                "typescript.preferences.preferTypeOnlyAutoImports": true,
                "notebook.formatOnSave.enabled": true,
                "[html]": {
                  "editor.defaultFormatter": "esbenp.prettier-vscode"
                },
                "[javascriptreact]": {
                  "editor.defaultFormatter": "esbenp.prettier-vscode"
                },
                "[json]": {
                  "editor.defaultFormatter": "esbenp.prettier-vscode"
                },
                "javascript.updateImportsOnFileMove.enabled": "always",
                "github.copilot.editor.enableAutoCompletions": true,
                "settingsSync.ignoredExtensions": [
                  "kevinrose.vsc-python-indent",
                  "redhat.vscode-tekton-pipelines"
                ],
                "[javascript]": {
                  "editor.defaultFormatter": "vscode.typescript-language-features"
                },
                "github.copilot.enable": {
                  "*": true,
                  "plaintext": true,
                  "markdown": false,
                  "scminput": false,
                  "javascript": true
                },
                "files.autoSave": "afterDelay",
                "[typescriptreact]": {
                  "editor.defaultFormatter": "esbenp.prettier-vscode"
                },
                "camelk.integrations.runtimeVersion": "2.3.1",
                "camelk.tools": {
                  "camelk.tools.kamel-path": "/home/andy_toma/.vscode-server/data/User/globalStorage/redhat.vscode-camelk/camelk/tools/kamel/kamel"
                },
                "[yaml]": {
                  "editor.defaultFormatter": "esbenp.prettier-vscode"
                },
                "[css]": {
                  "editor.defaultFormatter": "esbenp.prettier-vscode"
                },
                "go.toolsManagement.autoUpdate": false,
                "claudeCode.preferredLocation": "panel"
              }
            '';
          };

          # Secret OpenViking config stays local in ~/.openviking/ov.conf.
          home.file.".openviking/ovcli.conf".text = ''
            {"url":"http://127.0.0.1:1933"}
          '';

          home.file.".msmtprc" = {
            force = true;
            text = ''
              defaults
              auth on
              tls on
              tls_starttls on
              tls_trust_file /etc/ssl/cert.pem
              logfile ~/.msmtp.log

              account gmail
              host smtp.gmail.com
              port 587
              from toma.andy98@gmail.com
              user toma.andy98@gmail.com
              passwordeval "security find-generic-password -a toma.andy98@gmail.com -s opencode-msmtp-gmail -w"

              account default : gmail
            '';
          };

          home.file.".muttrc" = {
            force = true;
            text = ''
              set realname = "Andy Toma"
              set from = "toma.andy98@gmail.com"
              set use_from = yes
              set envelope_from = yes
              set sendmail = "${pkgs.msmtp}/bin/msmtp"
              set editor = "vi"

              # Gmail IMAP. Passwords are intentionally kept out of this file.
              set imap_user = "toma.andy98@gmail.com"
              set folder = "imaps://toma.andy98%40gmail.com@imap.gmail.com:993"
              set spoolfile = "+INBOX"
              set postponed = "+[Gmail]/Drafts"
              set record = "+[Gmail]/Sent Mail"
              set trash = "+[Gmail]/Trash"

              # Keep IMAP access usable for repeated triage.
              set ssl_force_tls = yes
              set header_cache = "~/.mutt/cache/headers"
              set message_cachedir = "~/.mutt/cache/bodies"
              set certificate_file = "~/.mutt/certificates"
              set mail_check = 60
              set timeout = 15

              # Local/private auth overrides. This file may define `imap_pass` via macOS
              # Keychain or leave it unset so mutt prompts interactively.
              source ~/.mutt/gmail.auth
            '';
          };

          home.file.".gitconfig" = {
            force = true;
            text = ''
              # Git Configuration

              [user]
                  name = Andy Toma
                  email = toma.andy98@gmail.com

              [init]
                  defaultBranch = main

              [pull]
                  rebase = true

              [credential]
                  helper =

              # Force SSH for MediDrive repos (uses special SSH host with medidrive_key)
              [url "git@github.com-medidrive:MediDrive-Tech/"]
                  insteadOf = git@github.com:MediDrive-Tech/
              [url "ssh://git@github.com-medidrive/MediDrive-Tech/"]
                  insteadOf = https://github.com/MediDrive-Tech/

              # Override email for MediDrive repos
              [includeIf "gitdir:~/medidrive/"]
                  path = ~/.gitconfig-medidrive
              [url "ssh://git@github.com/"]
                  insteadOf = https://github.com/
              [core]
                  excludesfile = /Users/${username}/.gitignore_global
                  editor = vim
            '';
          };

          home.file.".gitconfig-medidrive" = {
            force = true;
            text = ''
              [user]
                  email = andy.toma@medidrive.com
            '';
          };

          home.file.".gitignore_global" = {
            force = true;
            text = ''
              .claude/
            '';
          };

          home.file.".ssh/config" = {
            force = true;
            text = ''
              # Added by OrbStack: 'orb' SSH host for Linux machines
              Include ~/.orbstack/ssh/config

              # Global SSH settings
              Host *
                UseKeychain yes
                AddKeysToAgent yes

              # MediDrive GitHub repositories - use work key
              Host github.com-medidrive
                HostName github.com
                User git
                IdentityFile ~/.ssh/medidrive_key
                IdentitiesOnly yes

              # Personal GitHub - use personal key (default)
              Host github.com
                HostName github.com
                User git
                IdentityFile ~/.ssh/personal_key
                IdentitiesOnly yes
            '';
          };

          home.file.".docker/cli-plugins/docker-compose" = managedExecutable "${pkgs.docker-compose}/bin/docker-compose";

          home.file.".config/opencode/opencode.json" = managed (harness.opencode + "/opencode.json");
          home.file.".config/opencode/settings.json" = managed (harness.opencode + "/settings.json");
          home.file.".config/opencode/package.json" = managed (harness.opencode + "/package.json");
          home.file.".config/opencode/package-lock.json" = managed (harness.opencode + "/package-lock.json");
          home.file.".config/opencode/node_modules" = managed (opencodeNodeModules + "/node_modules");
          home.file.".config/opencode/dcp.jsonc" = managed (harness.opencode + "/dcp.jsonc");
          home.file.".config/opencode/agent-ladder.config.json" = managed (harness.opencode + "/agent-ladder.config.json");
          home.file.".config/opencode/SETUP.md" = managed (harness.opencode + "/SETUP.md");
          home.file.".config/opencode/LOCAL-STACK.md" = managed (harness.shared + "/LOCAL-STACK.md");
          home.file.".config/opencode/scripts" = managed (harness.opencode + "/scripts");
          home.file.".config/opencode/agents" = managed opencodeAgents;
          home.file.".config/opencode/skills" = managed opencodeSkills;
          home.file.".config/opencode/commands" = managed (harness.shared + "/commands");

          home.file.".claude/CLAUDE.md" = managed (harness.claude + "/CLAUDE.md");
          home.file.".claude/SETUP.md" = managed (harness.claude + "/SETUP.md");
          home.file.".claude/LOCAL-STACK.md" = managed (harness.shared + "/LOCAL-STACK.md");
          home.file.".claude/settings.json" = managed (harness.claude + "/settings.json");
          home.file.".claude/agents" = managed claudeAgents;
          home.file.".claude/skills" = managed claudeSkills;
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

          launchd.agents."com.jetbrains.toolbox" = {
            enable = true;
            config = {
              ProgramArguments = [
                "/Applications/Nix Apps/JetBrains Toolbox.app/Contents/MacOS/jetbrains-toolbox"
                "--minimize"
              ];
              RunAtLoad = true;
              StandardOutPath = "/Users/${username}/Library/Logs/JetBrains/Toolbox/launchd-stdout.log";
              StandardErrorPath = "/Users/${username}/Library/Logs/JetBrains/Toolbox/launchd-stderr.log";
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
              nix-switch = "make -C ~/.config/nix-darwin switch";
            };
          };

          programs.git.enable = true;
          programs.gh.enable = true;
          programs.jq.enable = true;

          programs.vscode = {
            enable = true;
            package = null;
            mutableExtensionsDir = true;
            profiles.default.extensions = with pkgs.vscode-extensions; [
              anthropic.claude-code
              esbenp.prettier-vscode
              github.copilot-chat
              github.vscode-github-actions
              golang.go
              ms-azuretools.vscode-containers
              ms-azuretools.vscode-docker
              ms-kubernetes-tools.vscode-kubernetes-tools
              ms-python.debugpy
              ms-python.python
              ms-python.vscode-pylance
              ms-vscode-remote.remote-containers
              ms-vscode.live-server
              redhat.vscode-yaml
              streetsidesoftware.code-spell-checker
              tamasfe.even-better-toml
              vscode-icons-team.vscode-icons
              waderyan.gitblame
              yoavbls.pretty-ts-errors
            ];
          };
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
