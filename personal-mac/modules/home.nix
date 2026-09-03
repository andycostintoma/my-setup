{
  username,
  harness,
  homeBaseModule,
  opencodeModule,
  claudeModule,
  codexModule,
  antigravityModule,
  packages,
  ponytail,
}:

{ pkgs, lib, ... }:
let
  homeDirectory = "/Users/${username}";
  ponytailPackage = ponytail pkgs;
  sharedOpencodeConfig = builtins.fromJSON (builtins.readFile (harness.opencode + "/opencode.json"));
  mergedOpencodeConfig = sharedOpencodeConfig // {
    plugin = (sharedOpencodeConfig.plugin or [ ]) ++ [
      "./plugins/ponytail/.opencode/plugins/ponytail.mjs"
    ];
  };
  opencodeConfig = pkgs.writeText "opencode-my-setup.json" (builtins.toJSON mergedOpencodeConfig);
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

  managedExecutable = source: {
    inherit source;
    executable = true;
    force = true;
  };

in
{
  imports = [
    (import homeBaseModule {
      inherit homeDirectory;
      gitEmail = "toma.andy98@gmail.com";
      extraGitConfig = ''
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
      '';
    })
    (import opencodeModule {
      inherit
        homeDirectory
        harness
        opencodeConfig
        ponytailPackage
        ;
      extraSkillSources = [ ../harness/shared/skills ];
    })
  ]
  ++
    map
      (
        module:
        import module {
          inherit harness ponytailPackage;
          extraSkillSources = [ ../harness/shared/skills ];
        }
      )
      [
        claudeModule
        codexModule
        antigravityModule
      ];

  home.username = username;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "25.05";
  home.packages = packages pkgs;
  home.sessionVariables.T3CODE_HOME = "${homeDirectory}/.t3";

  home.file.".zprofile".text = ''
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    export T3CODE_HOME=${homeDirectory}/.t3
  '';

  home.file.".bash_profile" = {
    force = true;
    text = ''
      export LANG=en_US.UTF-8
      export LC_ALL=en_US.UTF-8
      export T3CODE_HOME=${homeDirectory}/.t3
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

  home.file.".gitconfig-medidrive" = {
    force = true;
    text = ''
      [user]
          email = andy.toma@medidrive.com
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
        # Required for MediDrive OpenCode notifications: route VM requests to the Mac sound listener.
        RemoteForward 127.0.0.1:14097 127.0.0.1:14097
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

  home.file.".local/bin/opencode-sound-listener" = {
    executable = true;
    text = ''
      #!${pkgs.runtimeShell}
      while true; do
        printf 'HTTP/1.1 200 OK\r\n\r\n' | /usr/bin/nc -l 127.0.0.1 14097
        afplay /System/Library/Sounds/Glass.aiff &
      done
    '';
  };

  home.file.".docker/cli-plugins/docker-compose" =
    managedExecutable "${pkgs.docker-compose}/bin/docker-compose";

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

  launchd.agents.opencode-sound-listener = {
    enable = true;
    config = {
      ProgramArguments = [
        "/Users/${username}/.local/bin/opencode-sound-listener"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      WorkingDirectory = "/Users/${username}";
      StandardOutPath = "/Users/${username}/Library/Logs/opencode-sound-listener.log";
      StandardErrorPath = "/Users/${username}/Library/Logs/opencode-sound-listener.error.log";
      EnvironmentVariables = {
        HOME = "/Users/${username}";
        PATH = "/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };
  };

  # Required for MediDrive OpenCode notifications; do not remove unless their transport is replaced.
  # This keeps the reverse SSH route alive for detached and IDE-hosted sessions.
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

  programs.zsh = {
    shellAliases = {
      code = "codium";
      medidrive = "ssh -t medidrive-vm 'cd ~/medidrive && exec $SHELL -l'";
      medidrive-sync = "rsync -a --delete --exclude='.direnv/' --exclude='node_modules/' --exclude='.next/' --exclude='dist/' --exclude='build/' --exclude='target/' --exclude='coverage/' --exclude='.cache/' --exclude='worktrees/' -e 'ssh -o ControlPath=none -o ClearAllForwardings=yes' medidrive-vm:~/medidrive/ ~/medidrive-local/";
      hm-switch = "home-manager switch --flake ~/my-setup/personal-mac";
      nix-switch = "make -C ~/my-setup/personal-mac switch";
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
}
