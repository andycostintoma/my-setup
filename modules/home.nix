{
  username,
  harness,
  packages,
  kimaki,
  openclawUnhardlinked,
  openviking,
}:

{ pkgs, lib, ... }:
let
  homeDirectory = "/Users/${username}";
  openclawPackage = openclawUnhardlinked pkgs;
  kimakiPackage = kimaki pkgs;
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

in
{
  imports = [
    (import ./opencode.nix {
      inherit homeDirectory harness;
    })
  ];

  home.username = username;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "25.05";
  home.packages = packages pkgs;

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
        "go.toolsManagement.autoUpdate": false
      }
    '';
  };

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
    text = "";
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

  home.file.".docker/cli-plugins/docker-compose" =
    managedExecutable "${pkgs.docker-compose}/bin/docker-compose";

  home.file.".local/bin/ollama-ensure-models" = {
    executable = true;
    text = ''
      #!${pkgs.runtimeShell}
      set -eu

      export HOME="/Users/${username}"
      export OLLAMA_HOST="''${OLLAMA_HOST:-127.0.0.1:11434}"
      export PATH="${
        lib.makeBinPath [
          pkgs.ollama
          pkgs.coreutils
        ]
      }:/usr/bin:/bin:/usr/sbin:/sbin"

      for _ in $(${pkgs.coreutils}/bin/seq 1 60); do
        if ${pkgs.ollama}/bin/ollama list >/dev/null 2>&1; then
          break
        fi
        ${pkgs.coreutils}/bin/sleep 2
      done

      if ! ${pkgs.ollama}/bin/ollama list >/dev/null 2>&1; then
        printf 'Ollama server is not available at %s; skipping model install for now.\n' "$OLLAMA_HOST" >&2
        exit 0
      fi

      for model in qwen3.5:9b qwen3.5:4b; do
        if ! ${pkgs.ollama}/bin/ollama show "$model" >/dev/null 2>&1; then
          ${pkgs.ollama}/bin/ollama pull "$model"
        fi
      done
    '';
  };

  home.file.".local/bin/opencode-web-server" = {
    executable = true;
    text = ''
      #!${pkgs.runtimeShell}
      set -eu

      password_file="$HOME/.secrets/opencode/web-password"
      if [ ! -s "$password_file" ]; then
        printf 'Missing opencode web password file: %s\n' "$password_file" >&2
        exit 1
      fi

      export HOME="/Users/${username}"
      export OPENCODE_SERVER_USERNAME="opencode"
      export OPENCODE_SERVER_PASSWORD="$(cat "$password_file")"
      export PATH="${
        lib.makeBinPath (
          packages pkgs
          ++ [
            pkgs.bash
            pkgs.coreutils
            pkgs.git
            pkgs.nodejs
            pkgs.bun
          ]
        )
      }:/usr/bin:/bin:/usr/sbin:/sbin"

      exec ${pkgs.opencode}/bin/opencode web \
        --port 4096 \
        --hostname 0.0.0.0 \
        --mdns \
        --mdns-domain opencode.local
    '';
  };

  home.file.".local/bin/kimaki-server" = {
    executable = true;
    text = ''
      #!${pkgs.runtimeShell}
      set -eu

      export HOME="/Users/${username}"
      data_dir="$HOME/.kimaki"
      db_file="$data_dir/discord-sessions.db"

      if [ ! -s "$db_file" ]; then
        printf 'Kimaki is not configured yet. Run: kimaki --data-dir %s\n' "$data_dir" >&2
        exit 0
      fi

      export KIMAKI_LOCK_PORT="''${KIMAKI_LOCK_PORT:-31000}"
      export PATH="${
        lib.makeBinPath (
          packages pkgs
          ++ [
            pkgs.bash
            pkgs.coreutils
            pkgs.git
            pkgs.nodejs
            pkgs.bun
          ]
        )
      }:/usr/bin:/bin:/usr/sbin:/sbin"

      exec ${kimakiPackage}/bin/kimaki --data-dir "$data_dir"
    '';
  };

  home.activation.removeOldHarnessDirectories = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    set -eu

    for target in \
      /Users/${username}/.openclaw/skills
    do
      if [ -e "$target" ] || [ -L "$target" ]; then
        rm -rf "$target"
      fi
    done
  '';

  home.activation.opencodeWebSecrets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -eu

    secret_dir="/Users/${username}/.secrets/opencode"
    password_file="$secret_dir/web-password"

    install -d -m 0700 "$secret_dir" /Users/${username}/.kimaki /Users/${username}/Library/Logs
    if [ ! -s "$password_file" ]; then
      umask 077
      ${pkgs.openssl}/bin/openssl rand -base64 32 > "$password_file"
    fi
    chmod 0600 "$password_file"
  '';

  launchd.agents.ollama = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.ollama}/bin/ollama"
        "serve"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      WorkingDirectory = "/Users/${username}";
      StandardOutPath = "/Users/${username}/Library/Logs/ollama.log";
      StandardErrorPath = "/Users/${username}/Library/Logs/ollama.error.log";
      EnvironmentVariables = {
        HOME = "/Users/${username}";
        OLLAMA_HOST = "127.0.0.1:11434";
        OLLAMA_CONTEXT_LENGTH = "32768";
        OLLAMA_KEEP_ALIVE = "1m";
        OLLAMA_MAX_LOADED_MODELS = "1";
        PATH = "${pkgs.coreutils}/bin:${pkgs.bash}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };
  };

  launchd.agents.ollama-ensure-models = {
    enable = true;
    config = {
      ProgramArguments = [
        "/Users/${username}/.local/bin/ollama-ensure-models"
      ];
      RunAtLoad = true;
      StartInterval = 3600;
      WorkingDirectory = "/Users/${username}";
      StandardOutPath = "/Users/${username}/Library/Logs/ollama-ensure-models.log";
      StandardErrorPath = "/Users/${username}/Library/Logs/ollama-ensure-models.error.log";
      EnvironmentVariables = {
        HOME = "/Users/${username}";
        OLLAMA_HOST = "127.0.0.1:11434";
      };
    };
  };

  launchd.agents.ollama-opencode-proxy = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.nodejs}/bin/node"
        "/Users/${username}/.config/opencode/ollama-opencode-proxy.js"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      WorkingDirectory = "/Users/${username}";
      StandardOutPath = "/Users/${username}/Library/Logs/ollama-opencode-proxy.log";
      StandardErrorPath = "/Users/${username}/Library/Logs/ollama-opencode-proxy.error.log";
      EnvironmentVariables = {
        HOME = "/Users/${username}";
        OLLAMA_UPSTREAM = "http://127.0.0.1:11434";
        OLLAMA_OPENCODE_PROXY_HOST = "127.0.0.1";
        OLLAMA_OPENCODE_PROXY_PORT = "11435";
        PATH = "${pkgs.nodejs}/bin:${pkgs.coreutils}/bin:${pkgs.bash}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };
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

  launchd.agents.opencode-web = {
    enable = true;
    config = {
      ProgramArguments = [
        "/Users/${username}/.local/bin/opencode-web-server"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      WorkingDirectory = "/Users/${username}";
      StandardOutPath = "/Users/${username}/Library/Logs/opencode-web.log";
      StandardErrorPath = "/Users/${username}/Library/Logs/opencode-web.error.log";
      EnvironmentVariables = {
        HOME = "/Users/${username}";
      };
    };
  };

  launchd.agents.kimaki = {
    enable = true;
    config = {
      ProgramArguments = [
        "/Users/${username}/.local/bin/kimaki-server"
      ];
      RunAtLoad = true;
      KeepAlive = {
        SuccessfulExit = false;
      };
      WorkingDirectory = "/Users/${username}";
      StandardOutPath = "/Users/${username}/Library/Logs/kimaki.log";
      StandardErrorPath = "/Users/${username}/Library/Logs/kimaki.error.log";
      EnvironmentVariables = {
        HOME = "/Users/${username}";
      };
    };
  };

  home.file.".openclaw/openclaw.json" = managed (harness.openclaw + "/openclaw.json");
  home.file.".openclaw/skills" = managed (harness.shared + "/skills");
  home.file.".openclaw/workspace/AGENTS.md" = managed (harness.openclaw + "/workspace/AGENTS.md");
  home.file.".openclaw/workspace/HEARTBEAT.md" = managed (
    harness.openclaw + "/workspace/HEARTBEAT.md"
  );
  home.file.".openclaw/workspace/IDENTITY.md" = managed (harness.openclaw + "/workspace/IDENTITY.md");
  home.file.".openclaw/workspace/SOUL.md" = managed (harness.openclaw + "/workspace/SOUL.md");
  home.file.".openclaw/workspace/TOOLS.md" = managed (harness.openclaw + "/workspace/TOOLS.md");
  home.file.".openclaw/workspace/USER.md" = managed (harness.openclaw + "/workspace/USER.md");

  home.activation.openclawDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run --quiet ${pkgs.coreutils}/bin/mkdir -p \
      /Users/${username}/.openclaw/workspace \
      /Users/${username}/.openclaw/workspace/memory \
      /Users/${username}/Library/Logs
  '';

  launchd.agents.openclaw = {
    enable = true;
    config = {
      ProgramArguments = [
        "${openclawPackage}/bin/openclaw"
        "gateway"
        "--port"
        "18789"
        "run"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      WorkingDirectory = "/Users/${username}/.openclaw";
      StandardOutPath = "/Users/${username}/Library/Logs/openclaw-gateway.log";
      StandardErrorPath = "/Users/${username}/Library/Logs/openclaw-gateway.error.log";
      EnvironmentVariables = {
        HOME = "/Users/${username}";
        OPENCLAW_CONFIG_PATH = "/Users/${username}/.openclaw/openclaw.json";
        OPENCLAW_STATE_DIR = "/Users/${username}/.openclaw";
        OPENCLAW_NIX_MODE = "1";
        PATH =
          lib.makeBinPath (
            packages pkgs
            ++ [
              pkgs.bash
              pkgs.coreutils
            ]
          )
          + ":/usr/bin:/bin:/usr/sbin:/sbin";
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
      hm-switch = "home-manager switch --flake ~/.config/my-setup";
      nix-switch = "make -C ~/.config/my-setup switch";
      opencode = "sudo -E ${pkgs.opencode}/bin/opencode";
    };
    initContent = ''
      medidrive-upload() {
        if [ "$#" -ne 2 ]; then
          printf 'usage: medidrive-upload SOURCE DEST\n' >&2
          return 2
        fi

        local source="$1"
        local dest="$2"
        local remote_host="andy@35.243.44.225"
        local remote_base="/home/andy/medidrive"
        local remote_path="$remote_base/$dest"
        local remote_dir="''${remote_path:h}"

        if [[ "$dest" = /* ]]; then
          printf 'DEST must be relative to ~/medidrive on the VM\n' >&2
          return 2
        fi

        ssh -i "$HOME/.ssh/medidrive_key" -o IdentitiesOnly=yes "$remote_host" "mkdir -p -- ''${(q)remote_dir}" || return
        rsync -az -e "ssh -i $HOME/.ssh/medidrive_key -o IdentitiesOnly=yes" "$source" "$remote_host:$remote_path"
      }
    '';
  };

  programs.git.enable = true;
  programs.gh.enable = true;
  programs.jq.enable = true;

  programs.vscode = {
    enable = true;
    package = null;
    mutableExtensionsDir = true;
    profiles.default.extensions = with pkgs.vscode-extensions; [
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
}
