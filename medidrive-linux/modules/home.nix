{
  username,
  harness,
  opencodeModule,
  claudeModule,
  codexModule,
  antigravityModule,
  openviking,
  packages,
}:

{ pkgs, lib, ... }:
let
  homeDirectory = "/home/${username}";
  openvikingPackage = openviking pkgs;
  sharedOpencodeConfig = builtins.fromJSON (builtins.readFile (harness.opencode + "/opencode.json"));
  medidriveOpencodeConfig = builtins.fromJSON (builtins.readFile ../harness/medidrive/opencode.json);
  mergedOpencodeConfig = lib.recursiveUpdate sharedOpencodeConfig medidriveOpencodeConfig // {
    plugin = (sharedOpencodeConfig.plugin or [ ]) ++ (medidriveOpencodeConfig.plugin or [ ]);
  };
  opencodeConfig = pkgs.writeText "opencode-medidrive.json" (builtins.toJSON mergedOpencodeConfig);
in
{
  imports = [
    (import opencodeModule {
      inherit
        homeDirectory
        harness
        opencodeConfig
        ;
      extraPluginSources = [ ../harness/medidrive/plugins ];
      extraSkillSources = [ ../harness/medidrive/skills ];
    })
    (import claudeModule {
      inherit homeDirectory harness;
      extraSkillSources = [ ../harness/medidrive/skills ];
    })
    (import codexModule {
      inherit homeDirectory harness;
      extraSkillSources = [ ../harness/medidrive/skills ];
    })
    (import antigravityModule {
      inherit homeDirectory harness;
      extraSkillSources = [ ../harness/medidrive/skills ];
    })
  ];

  home.username = username;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "25.05";
  home.packages = (packages pkgs) ++ [ pkgs.ghostty.terminfo ];

  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    TERMINFO_DIRS = "${pkgs.ghostty.terminfo}/share/terminfo:${pkgs.ncurses}/share/terminfo:/usr/share/terminfo";
    # Pin GOCACHE so the cleanup unit below knows the single location to manage.
    GOCACHE = "${homeDirectory}/.cache/go-build";
    # gcloud + kubectl: GKE auth plugin opt-in. No ambient CLOUDSDK_CORE_PROJECT;
    # env switching happens through `make kube-sandbox` / `make kube-staging` in
    # ~/medidrive/Makefile (see AGENTS.md "GKE cluster credentials").
    USE_GKE_GCLOUD_AUTH_PLUGIN = "True";
    OPENCODE_NOTIFY_SOUND_COMMAND = "curl -fsS --max-time 2 http://127.0.0.1:14097/ >/dev/null";
  };

  home.file.".local/bin/jetbrains-remote-backend-cleanup" = {
    executable = true;
    text = ''
      #!${pkgs.runtimeShell}
      set -eu

      export PATH="${
        lib.makeBinPath [
          pkgs.bash
          pkgs.coreutils
          pkgs.gawk
          pkgs.gnugrep
          pkgs.iproute2
          pkgs.procps
        ]
      }:/usr/bin:/bin:/usr/sbin:/sbin"

      state_dir="${homeDirectory}/.local/state/jetbrains"
      log_file="$state_dir/remote-backend-cleanup.log"
      install -d -m 0700 "$state_dir"

      log() {
        printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$log_file"
      }

      reap_pid() {
        pid="$1"
        label="$2"
        detail="$3"
        cmd="$4"

        log "reaping stale JetBrains $label pid=$pid $detail cmd=$cmd"
        kill "$pid" || true
        sleep 5
        if kill -0 "$pid" 2>/dev/null; then
          log "forcing stale JetBrains $label pid=$pid"
          kill -KILL "$pid" || true
        fi
      }

      ps -eo pid=,etimes=,args= | while read -r pid etimes cmd; do
        case "$cmd" in
          *"/JetBrains/Toolbox/apps/"*" serverMode "*) ;;
          *) continue ;;
        esac

        if [ "$etimes" -lt 1800 ]; then
          continue
        fi

        pid_pattern="pid=$pid,"
        conn_lines=$(ss -tanp 2>/dev/null | grep "$pid_pattern" || true)
        estab_count=$(printf '%s\n' "$conn_lines" | grep -c ESTAB || true)
        close_wait_count=$(printf '%s\n' "$conn_lines" | grep -c CLOSE-WAIT || true)

        if [ "$estab_count" -ne 0 ] || [ "$close_wait_count" -lt 5 ]; then
          continue
        fi

        reap_pid "$pid" "backend" "age=''${etimes}s close_wait=$close_wait_count" "$cmd"
      done

      ps -eo pid=,etimes=,args= | while read -r pid etimes cmd; do
        case "$cmd" in
          *"/JetBrains/Toolbox-CLI-dist/"*) ;;
          *) continue ;;
        esac

        if [ "$etimes" -lt 21600 ]; then
          continue
        fi

        if pgrep -P "$pid" >/dev/null 2>&1; then
          continue
        fi

        reap_pid "$pid" "toolbox-cli" "age=''${etimes}s childless=true" "$cmd"
      done
    '';
  };

  home.file.".local/bin/jetbrains-sync-medidrive-iml" = {
    executable = true;
    text = lib.concatStringsSep "\n" [
      "#!${pkgs.runtimeShell}"
      "set -eu"
      ""
      "export PATH=\"${
        lib.makeBinPath [
          pkgs.bash
          pkgs.coreutils
          pkgs.findutils
          pkgs.gawk
        ]
      }:/usr/bin:/bin:/usr/sbin:/sbin\""
      ""
      "workspace_root=\"${homeDirectory}/medidrive\""
      "repo_root=\"$workspace_root/repos\""
      "go_work=\"$repo_root/go.work\""
      "idea_dir=\"$workspace_root/.idea\""
      "iml_file=\"$idea_dir/medidrive.iml\""
      ""
      "if [ ! -f \"$go_work\" ]; then"
      "  exit 0"
      "fi"
      ""
      "install -d -m 0700 \"$idea_dir\""
      ""
      "tmp_file=$(mktemp)"
      "tmp_excludes=$(mktemp)"
      "trap 'rm -f \"$tmp_file\" \"$tmp_excludes\"' EXIT"
      ""
      "declare -A keep_repos"
      "while IFS= read -r repo; do"
      "  if [ -n \"$repo\" ]; then"
      "    keep_repos[\"$repo\"]=1"
      "  fi"
      "done < <("
      "  awk '"
      "    /^[[:space:]]*use[[:space:]]*\\(/ { in_use = 1; next }"
      "    in_use && /^[[:space:]]*\\)/ { in_use = 0; next }"
      "    in_use {"
      "      gsub(/^[[:space:]]*\\.\\//, \"\", $0)"
      "      gsub(/[[:space:]]+$/, \"\", $0)"
      "      if ($0 != \"\") print $0"
      "    }"
      "  ' \"$go_work\""
      ")"
      ""
      "while IFS= read -r repo; do"
      "  if ! [[ -v 'keep_repos[$repo]' ]]; then"
      "    printf '      <excludeFolder url=\"file://$MODULE_DIR$/repos/%s\" />\\n' \"$repo\" >> \"$tmp_excludes\""
      "  fi"
      "done < <("
      "  find \"$repo_root\" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%f\\n' | LC_ALL=C sort"
      ")"
      ""
      "cat > \"$tmp_file\" <<EOF"
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
      "<module type=\"WEB_MODULE\" version=\"4\">"
      "  <component name=\"Go\" enabled=\"true\" />"
      "  <component name=\"NewModuleRootManager\">"
      "    <content url=\"file://\\$MODULE_DIR\\$\">"
      "$(cat \"$tmp_excludes\")"
      "    </content>"
      "    <orderEntry type=\"inheritedJdk\" />"
      "    <orderEntry type=\"sourceFolder\" forTests=\"false\" />"
      "  </component>"
      "</module>"
      "EOF"
      ""
      "if [ ! -f \"$iml_file\" ] || ! cmp -s \"$tmp_file\" \"$iml_file\"; then"
      "  mv \"$tmp_file\" \"$iml_file\""
      "fi"
      ""
    ];
  };

  home.activation.removeStaleOpenVikingUnit = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    rm -f "${homeDirectory}/.config/systemd/user/openviking.service"
  '';

  home.activation.jetbrainsMedidriveProjectSync = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [ -x "${homeDirectory}/.local/bin/jetbrains-sync-medidrive-iml" ]; then
      "${homeDirectory}/.local/bin/jetbrains-sync-medidrive-iml"
    fi
  '';

  systemd.user.services.openviking = {
    Unit = {
      Description = "OpenViking server";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = homeDirectory;
      ExecStart = "${openvikingPackage}/bin/openviking-server --config ${homeDirectory}/.openviking/ov.conf --host 127.0.0.1 --port 1933";
      Restart = "on-failure";
      RestartSec = "5s";
      Environment = [
        "HOME=${homeDirectory}"
        "PATH=${
          lib.makeBinPath [
            pkgs.coreutils
            pkgs.bash
          ]
        }:/usr/bin:/bin:/usr/sbin:/sbin"
      ];
      StandardOutput = "append:${homeDirectory}/.local/state/openviking/openviking.log";
      StandardError = "append:${homeDirectory}/.local/state/openviking/openviking.log";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # JetBrains remote backends occasionally wedge after repeated reconnects:
  # the SSH tunnel still works, but the backend accumulates CLOSE_WAIT sockets
  # on its forwarded TLS port and stops accepting new clients. Reap only old,
  # clearly idle serverMode processes with leaked sockets so the next connect
  # starts a fresh backend automatically.
  systemd.user.services.jetbrains-remote-backend-cleanup = {
    Unit = {
      Description = "Reap stale JetBrains remote backends";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${homeDirectory}/.local/bin/jetbrains-remote-backend-cleanup";
      Environment = [
        "HOME=${homeDirectory}"
      ];
    };
  };

  systemd.user.timers.jetbrains-remote-backend-cleanup = {
    Unit = {
      Description = "Periodic cleanup of stale JetBrains remote backends";
    };
    Timer = {
      OnBootSec = "5m";
      OnUnitActiveSec = "10m";
      RandomizedDelaySec = "2m";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  systemd.user.services.jetbrains-medidrive-project-sync = {
    Unit = {
      Description = "Sync medidrive GoLand excludes from go.work";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${homeDirectory}/.local/bin/jetbrains-sync-medidrive-iml";
      Environment = [
        "HOME=${homeDirectory}"
      ];
    };
  };

  systemd.user.timers.jetbrains-medidrive-project-sync = {
    Unit = {
      Description = "Periodic sync of medidrive GoLand excludes";
    };
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "10m";
      RandomizedDelaySec = "2m";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  # Go build artifact cleanup.
  #
  # The VM previously filled the root disk (~/.cache/go-build ~257G,
  # /tmp/go-build* ~177G) because Go build artifacts grew unbounded. Both are
  # transient — the reusable module cache at ~/go/pkg/mod is left alone.
  #
  # Hourly systemd-user timer (daily was too coarse — cache can balloon past
  # the 25 GiB cap within a single workday of heavy builds):
  #   - delete stale /tmp/go-build* trees, including OpenCode-scoped TMPDIRs
  #   - if ~/.cache/go-build or OpenCode-scoped GOCACHE dirs exceed 25 GiB,
  #     blow them away entirely
  #     (Go transparently rebuilds; avoids bounded-trim loops on pathological growth)
  #   - otherwise drop entries inside ~/.cache/go-build untouched for >7 days
  systemd.user.services.go-cache-cleanup = {
    Unit = {
      Description = "Trim Go build cache and /tmp/go-build* artifacts";
    };
    Service = {
      Type = "oneshot";
      ExecStart = toString (
        pkgs.writeShellScript "go-cache-cleanup" ''
          set -u
          export PATH=${
            lib.makeBinPath [
              pkgs.coreutils
              pkgs.findutils
            ]
          }:$PATH

          GOCACHE="${homeDirectory}/.cache/go-build"
          OPENCODE_TMP="/tmp/opencode"
          MAX_KIB=26214400  # 25 GiB; du -sk reports KiB.

          trim_cache_dir() {
            cache_dir="$1"

            if [ -d "$cache_dir" ]; then
              size_kib=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1}')
              size_kib=''${size_kib:-0}
              if [ "$size_kib" -gt "$MAX_KIB" ]; then
                rm -rf -- "$cache_dir"
                mkdir -p -- "$cache_dir"
              else
                find "$cache_dir" -mindepth 1 -type f -atime +7 -delete 2>/dev/null || true
                find "$cache_dir" -mindepth 1 -type d -empty -delete 2>/dev/null || true
              fi
            fi
          }

          # 1) Stale Go temp build trees. OpenCode runs sometimes set TMPDIR to
          # /tmp/opencode/*-tmp, so maxdepth=1 under /tmp is not enough.
          find /tmp -maxdepth 1 -name 'go-build*' -type d -mmin +240 -print0 2>/dev/null \
            | xargs -0 -r rm -rf --
          if [ -d "$OPENCODE_TMP" ]; then
            find "$OPENCODE_TMP" -mindepth 2 -maxdepth 2 -name 'go-build*' -type d -mmin +240 -print0 2>/dev/null \
              | xargs -0 -r rm -rf --
          fi

          # 2) Go build caches: hard reset if oversized, else trim by age.
          trim_cache_dir "$GOCACHE"
          for cache_dir in "$OPENCODE_TMP"/*-cache; do
            trim_cache_dir "$cache_dir"
          done
        ''
      );
    };
  };

  systemd.user.timers.go-cache-cleanup = {
    Unit = {
      Description = "Hourly trim of Go build cache and /tmp/go-build* artifacts";
    };
    Timer = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  systemd.user.services.t3code = {
    Unit = {
      Description = "T3 code server";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.t3code}/bin/t3code serve --port 14096 --base-dir ${homeDirectory}/.t3 ${homeDirectory}/medidrive";
      Restart = "on-failure";
      RestartSec = "5s";
      WorkingDirectory = "${homeDirectory}/medidrive";
      Environment = [
        "HOME=${homeDirectory}"
        "T3CODE_HOME=${homeDirectory}/.t3"
        "PATH=${lib.makeBinPath (packages pkgs)}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
      ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  home.file.".gitconfig" = {
    force = true;
    text = ''
      [user]
          name = Andy Toma
          email = andy.toma@medidrive.com

      [init]
          defaultBranch = main

      [pull]
          rebase = true

      [credential]
          helper =

      [url "ssh://git@github.com/MediDrive-Tech/"]
          insteadOf = https://github.com/MediDrive-Tech/
      [core]
          excludesfile = ${homeDirectory}/.gitignore_global
          editor = vim
    '';
  };

  home.file.".gitignore_global" = {
    force = true;
    text = "";
  };

  home.file.".ssh/config" = {
    force = true;
    text = ''
      Host github.com
        HostName github.com
        User git
        IdentityFile ~/.ssh/medidrive_key
        IdentitiesOnly yes
    '';
  };

  home.file.".zprofile" = {
    force = true;
    text = ''
      if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      elif [ -e /etc/profile.d/nix.sh ]; then
        . /etc/profile.d/nix.sh
      fi

      if [ -e "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
        . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
      fi

      export TERMINFO_DIRS="${pkgs.ghostty.terminfo}/share/terminfo:${pkgs.ncurses}/share/terminfo:/usr/share/terminfo"

      if [ "''${TERM:-}" = "xterm-ghostty" ] && ! infocmp xterm-ghostty >/dev/null 2>&1; then
        export TERM=xterm-256color
      fi

      export PATH="$HOME/.nix-profile/bin:$PATH"
    '';
  };

  programs.home-manager.enable = true;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;
  };

  programs.zsh = {
    enable = true;
    envExtra = ''
      export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin:''${PATH:-}"
    '';
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [ "git" ];
    };
    initContent = lib.mkMerge [
      (lib.mkOrder 500 ''
        if [[ $- != *i* ]]; then
          return
        fi
      '')
      (lib.mkOrder 1000 ''
        export TERMINFO_DIRS="${pkgs.ghostty.terminfo}/share/terminfo:${pkgs.ncurses}/share/terminfo:/usr/share/terminfo"

        if [ "''${TERM:-}" = "xterm-ghostty" ] && ! infocmp xterm-ghostty >/dev/null 2>&1; then
          export TERM=xterm-256color
        fi
      '')
    ];
    shellAliases = {
      hm-switch = "home-manager switch --flake ~/my-setup/medidrive-linux#medidrive";
      ll = "ls -lah";
      opencode = "${pkgs.opencode}/bin/opencode";
      opencode-linear = ''OPENCODE_CONFIG_CONTENT='{"mcp":{"linear":{"enabled":true}}}' ${pkgs.opencode}/bin/opencode'';
      opencode-postman = ''OPENCODE_CONFIG_CONTENT='{"mcp":{"postman":{"enabled":true}}}' ${pkgs.opencode}/bin/opencode'';
      opencode-mcp = ''OPENCODE_CONFIG_CONTENT='{"mcp":{"linear":{"enabled":true},"postman":{"enabled":true}}}' ${pkgs.opencode}/bin/opencode'';
    };
  };

  programs.bash.enable = true;
  programs.git.enable = true;
  programs.gh.enable = true;
  xdg.configFile."gh/config.yml".force = true;
  programs.jq.enable = true;
}
