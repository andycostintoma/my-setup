{ commonPackages }:

let
  pins = import ./pins.nix;
in
rec {
  inherit (commonPackages) openviking;

  userFromNixpkgs =
    pkgs: with pkgs; [
      atlas
      defaultbrowser
      ffmpeg
      graphviz
      mermaid-cli
      mkcert
      msmtp
      mutt
      nextdns
      ollama
      pandoc
      pgcli
      poppler-utils
      p7zip
      tesseract
      yt-dlp
      python3Packages.youtube-transcript-api
    ];

  systemFromNixpkgs =
    pkgs: with pkgs; [
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
      zoom-us
    ];

  # Personal-only local packages.
  microsoftEdge =
    pkgs:
    pkgs.stdenvNoCC.mkDerivation {
      pname = "microsoft-edge";
      version = pins.microsoftEdge.version;

      src = pkgs.fetchurl {
        name = "MicrosoftEdge-${pins.microsoftEdge.version}.pkg";
        inherit (pins.microsoftEdge) url hash;
      };

      nativeBuildInputs = with pkgs; [
        cpio
        gzip
        makeWrapper
        xar
      ];

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

  # OpenClaw's runtime rejects hardlinked bundled plugin public-surface
  # files. nixpkgs currently ships at least some of those files hardlinked,
  # so copy the package into a local output before launching it.
  openclawUnhardlinked =
    pkgs:
    pkgs.runCommand "openclaw-${pkgs.openclaw.version}-unhardlinked" { } ''
      mkdir -p "$out"
      cp -R ${pkgs.openclaw}/. "$out/"
      substituteInPlace "$out/bin/openclaw" \
        --replace-fail "${pkgs.openclaw}" "$out"
    '';

  kumospace =
    pkgs:
    pkgs.stdenvNoCC.mkDerivation {
      pname = "kumospace";
      version = pins.kumospace.version;

      src = pkgs.fetchurl {
        name = "Kumospace-${pins.kumospace.version}.dmg";
        inherit (pins.kumospace) url hash;
      };

      nativeBuildInputs = with pkgs; [
        makeWrapper
        undmg
      ];

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

  # Wrapper for macOS `open` that forces URLs to open in Google Chrome.
  # OpenCode calls Bun.spawn(["open", url]) directly, bypassing the shell, so
  # the system default-browser setting is what matters. On macOS 13+ changing
  # the default browser requires a user-confirmed dialog that cannot be
  # scripted. This wrapper sits earlier in PATH than /usr/bin/open and
  # intercepts http/https URLs, delegating everything else to the real open.
  chromeOpenWrapper =
    pkgs:
    pkgs.runCommand "chrome-open-wrapper" { } ''
      mkdir -p $out/bin

      cat > $out/bin/open <<'EOF'
      #!/bin/sh
      # Redirect http/https URLs to Google Chrome; pass everything else through.
      CHROME_APP="/Applications/Nix Apps/Google Chrome.app"
      REAL_OPEN="/usr/bin/open"

      # Scan args for a URL flag or a bare http(s) argument.
      use_chrome=0
      for arg in "$@"; do
        case "$arg" in
          http://*|https://*)
            use_chrome=1
            break
            ;;
        esac
      done

      if [ "$use_chrome" = "1" ] && [ -d "$CHROME_APP" ]; then
        exec "$REAL_OPEN" -a "$CHROME_APP" "$@"
      else
        exec "$REAL_OPEN" "$@"
      fi
      EOF

      chmod +x $out/bin/open
    '';

  # Kimaki is not packaged in nixpkgs yet. Keep it pinned and invoked through
  # Nix-provided Node/npm tooling; do not install it globally with npm.
  kimaki =
    pkgs:
    let
      version = pins.kimaki.version;
    in
    pkgs.runCommand "kimaki-${version}" { } ''
      mkdir -p $out/bin

      cat > $out/bin/kimaki <<'EOF'
      #!${pkgs.runtimeShell}
      exec ${pkgs.nodejs}/bin/npx -y kimaki@${version} "$@"
      EOF

      chmod +x $out/bin/kimaki
    '';

  # OpenChamber is not packaged in nixpkgs yet. Keep the CLI pinned and run it
  # through Nix-provided Node/npm tooling without a global npm install.
  openchamber =
    pkgs:
    let
      version = pins.openchamber.version;
    in
    pkgs.runCommand "openchamber-${version}" { } ''
      mkdir -p $out/bin

      cat > $out/bin/openchamber <<'EOF'
      #!${pkgs.runtimeShell}
      exec ${pkgs.nodejs}/bin/npx -y @openchamber/web@${version} "$@"
      EOF

      chmod +x $out/bin/openchamber
    '';

  # Local transcription CLI. Python, faster-whisper, and the entrypoint source
  # are all managed by this flake.
  transcriber =
    pkgs:
    let
      python = pkgs.python313.withPackages (ps: [
        ps.faster-whisper
      ]);
      entrypoint = ../tools/transcriber/main.py;
    in
    pkgs.runCommand "transcriber-local" { } ''
      mkdir -p $out/bin

      cat > $out/bin/transcriber <<'EOF'
      #!${pkgs.runtimeShell}
      exec ${python}/bin/python ${entrypoint} "$@"
      EOF

      chmod +x $out/bin/transcriber
    '';

  user =
    pkgs:
    commonPackages.common pkgs
    ++ userFromNixpkgs pkgs
    ++ [
      (chromeOpenWrapper pkgs)
      (kimaki pkgs)
      (openchamber pkgs)
      (openclawUnhardlinked pkgs)
      (transcriber pkgs)
    ];

  system =
    pkgs:
    systemFromNixpkgs pkgs
    ++ [
      (kumospace pkgs)
      (microsoftEdge pkgs)
    ];
}
