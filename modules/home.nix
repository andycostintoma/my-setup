{
  username,
  harness,
  opencodeModule,
  claudeModule,
  codexModule,
  antigravityModule,
  packages,
  kimaki,
  openviking,
}:

{ pkgs, lib, ... }:
let
  homeDirectory = "/Users/${username}";
  kimakiPackage = kimaki pkgs;
  openvikingPackage = openviking pkgs;
  sharedOpencodeConfig = builtins.fromJSON (builtins.readFile (harness.opencode + "/opencode.json"));
  localOpencodeConfig = builtins.fromJSON (builtins.readFile ./opencode.local.json);
  sharedOpencodePlugins = sharedOpencodeConfig.plugin or [ ];
  mergedOpencodeConfig = lib.recursiveUpdate sharedOpencodeConfig localOpencodeConfig // {
    plugin = sharedOpencodePlugins ++ (localOpencodeConfig.plugin or [ ]);
  };
  opencodeConfig = pkgs.writeText "opencode-my-setup.json" (
    builtins.toJSON mergedOpencodeConfig
  );
  opencodePlaywrightConfig = builtins.toJSON {
    mcp.playwright = {
      type = "local";
      command = [
        "npx"
        "-y"
        "@playwright/mcp@latest"
        "--isolated"
      ];
      enabled = true;
    };
  };

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
    (import opencodeModule {
      inherit homeDirectory harness opencodeConfig;
      extraDocSources = [ ../harness/opencode/docs ];
      extraPluginSources = [ ../harness/opencode/plugins ];
      extraSkillSources = [ ../harness/shared/skills ];
    })
    (import claudeModule {
      inherit homeDirectory harness;
      extraSkillSources = [ ../harness/shared/skills ];
    })
    (import codexModule {
      inherit homeDirectory harness;
      extraSkillSources = [ ../harness/shared/skills ];
    })
    (import antigravityModule {
      inherit homeDirectory harness;
      extraSkillSources = [ ../harness/shared/skills ];
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
        # macOS 15 /usr/bin/ssh ships with a broken compiled-in default of
        # UserKnownHostsFile=/var/root/.ssh/known_hosts; pin it back to the user's known_hosts.
        UserKnownHostsFile /Users/${username}/.ssh/known_hosts

      # MediDrive GitHub repositories - use work key
      Host github.com-medidrive
        HostName github.com
        User git
        IdentityFile /Users/${username}/.ssh/medidrive_key
        IdentitiesOnly yes

      # MediDrive development VM
      Host medidrive-vm
        HostName 35.243.44.225
        User andy
        IdentityFile /Users/${username}/.ssh/medidrive_key
        IdentitiesOnly yes
        UserKnownHostsFile /Users/${username}/.ssh/known_hosts
        ServerAliveInterval 30
        ServerAliveCountMax 4
        ExitOnForwardFailure yes
        TCPKeepAlive yes
        LocalForward 14096 127.0.0.1:14096
        ControlMaster auto
        ControlPath /Users/${username}/.ssh/controlmasters/%r@%h:%p
        ControlPersist 10m

      # Personal GitHub - use personal key (default)
      Host github.com
        HostName github.com
        User git
        IdentityFile /Users/${username}/.ssh/personal_key
        IdentitiesOnly yes
    '';
  };

  home.file.".ssh/controlmasters/.keep" = {
    force = true;
    text = "";
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

      heretic_source="hf.co/mradermacher/Qwen2.5-Coder-7B-Instruct-heretic-i1-GGUF:Q4_K_M"
      heretic_alias="qwen2.5-coder-7b-heretic"

      if ! ${pkgs.ollama}/bin/ollama show "$heretic_source" >/dev/null 2>&1; then
        ${pkgs.ollama}/bin/ollama pull "$heretic_source"
      fi

      if ! ${pkgs.ollama}/bin/ollama show "$heretic_alias" >/dev/null 2>&1; then
        ${pkgs.ollama}/bin/ollama cp "$heretic_source" "$heretic_alias"
      fi
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

  home.file.".local/bin/opencode-askpass" = {
    executable = true;
    text = ''
      #!${pkgs.runtimeShell}
      exec /usr/bin/osascript \
        -e 'with timeout of 3600 seconds' \
        -e 'Tell application "System Events" to display dialog "Administrator password required" default answer "" with hidden answer buttons {"OK"} default button "OK"' \
        -e 'text returned of result' \
        -e 'end timeout'
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

  home.file.".local/bin/jetbrains-toolbox-watchdog" = {
    executable = true;
    text = ''
      #!${pkgs.runtimeShell}
      set -eu

      export HOME="/Users/${username}"
      export PATH="${
        lib.makeBinPath [
          pkgs.coreutils
          pkgs.gnugrep
        ]
      }:/usr/bin:/bin:/usr/sbin:/sbin"

      log_file="$HOME/Library/Logs/JetBrains/Toolbox/toolbox.latest.log"
      state_dir="$HOME/.local/state/jetbrains"
      state_file="$state_dir/toolbox-watchdog.state"

      [ -f "$log_file" ] || exit 0
      mkdir -p "$state_dir"

      inode="$(/usr/bin/stat -f '%i' "$log_file")"
      size="$(/usr/bin/stat -f '%z' "$log_file")"
      last_inode=""
      last_offset="$size"

      if [ -f "$state_file" ]; then
        read -r last_inode last_offset < "$state_file" || true
      fi

      case "$last_offset" in
        ""|*[!0-9]*) last_offset=0 ;;
      esac

      if [ "$inode" != "$last_inode" ] || [ "$last_offset" -gt "$size" ]; then
        printf '%s %s\n' "$inode" "$size" > "$state_file"
        exit 0
      fi

      if [ "$last_offset" -eq "$size" ]; then
        exit 0
      fi

      new_log="$(tail -c +$((last_offset + 1)) "$log_file")"
      printf '%s %s\n' "$inode" "$size" > "$state_file"

      if ! printf '%s\n' "$new_log" | grep -Eq 'RejectedExecutionException: event executor terminated|Event loop shut down'; then
        exit 0
      fi

      # The Toolbox Station server is wedged; only terminate remote thin clients, not local IDE windows.
      /usr/bin/pkill -f 'goland thinClient stuw://ssh/' 2>/dev/null || true
      launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.com.jetbrains.toolbox"
    '';
  };

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

  home.activation.setDefaultBrowser = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -eu

    # Set Google Chrome as the default browser for http/https if it is not already.
    # `defaultbrowser` identifies Chrome by the short token "chrome".
    if ${pkgs.defaultbrowser}/bin/defaultbrowser | ${pkgs.ripgrep}/bin/rg -q '^\* chrome$'; then
      : # Chrome is already the default; nothing to do.
    else
      ${pkgs.defaultbrowser}/bin/defaultbrowser chrome
    fi
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
        "--experimental-strip-types"
        "${./ollama-opencode-proxy.my-setup.ts}"
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
    enable = false;
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

  launchd.agents."jetbrains-toolbox-watchdog" = {
    enable = true;
    config = {
      ProgramArguments = [
        "/Users/${username}/.local/bin/jetbrains-toolbox-watchdog"
      ];
      RunAtLoad = true;
      StartInterval = 60;
      StandardOutPath = "/Users/${username}/Library/Logs/JetBrains/Toolbox/watchdog.log";
      StandardErrorPath = "/Users/${username}/Library/Logs/JetBrains/Toolbox/watchdog.error.log";
      EnvironmentVariables = {
        HOME = "/Users/${username}";
      };
    };
  };

  launchd.agents.medidrive-tunnel = {
    enable = true;
    config = {
      ProgramArguments = [
        "/usr/bin/ssh"
        "-N"
        "medidrive-vm"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      WorkingDirectory = "/Users/${username}";
      StandardOutPath = "/Users/${username}/Library/Logs/medidrive-tunnel.log";
      StandardErrorPath = "/Users/${username}/Library/Logs/medidrive-tunnel.error.log";
      EnvironmentVariables = {
        HOME = "/Users/${username}";
        PATH = "/usr/bin:/bin:/usr/sbin:/sbin";
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
      code = "codium";
      medidrive = "ssh -t medidrive-vm 'cd ~/medidrive && exec $SHELL -l'";
      medidrive-sync = "rsync -az --delete --exclude='.direnv/' --exclude='node_modules/' --exclude='.next/' --exclude='dist/' --exclude='build/' --exclude='target/' --exclude='coverage/' --exclude='.cache/' -e 'ssh' medidrive-vm:~/medidrive/ ~/medidrive-local/";
      medidrive-tunnel-status = "ssh -O check medidrive-vm";
      medidrive-tunnel-exit = "ssh -O exit medidrive-vm";
      hm-switch = "home-manager switch --flake ~/personal/my-setup";
      nix-switch = "make -C ~/personal/my-setup switch";
      opencode-playwright = "OPENCODE_CONFIG_CONTENT=${lib.escapeShellArg opencodePlaywrightConfig} ${pkgs.opencode}/bin/opencode";
    };
    initContent = ''
      path=("${homeDirectory}/Library/Application Support/JetBrains/Toolbox/scripts" $path)

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

}
