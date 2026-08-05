{
  sharedPackages,
  antigravity-app ? null,
}:

let
  pins = import ./pins.nix;
in
rec {
  inherit (sharedPackages)
    ponytail
    setupctl
    ;

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
      t3code
      tailscale
      telegram-desktop
      vscodium
      wireshark
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

  epubToMarkdown =
    pkgs:
    pkgs.buildGoModule {
      pname = "epub-to-markdown";
      version = "0.1.0";
      src = ../tools/epub-to-markdown;
      vendorHash = null;
    };

  pdfToMarkdown =
    pkgs:
    pkgs.buildGoModule {
      pname = "pdf-to-markdown";
      version = "0.1.0";
      src = ../tools/pdf-to-markdown;
      vendorHash = null;
    };

  user =
    pkgs:
    sharedPackages.packages pkgs
    ++ userFromNixpkgs pkgs
    ++ [
      (chromeOpenWrapper pkgs)
      (epubToMarkdown pkgs)
      (setupctl pkgs)
      (pdfToMarkdown pkgs)
      (transcriber pkgs)
    ];

  system =
    pkgs:
    systemFromNixpkgs pkgs
    ++ [
      (kumospace pkgs)
      (microsoftEdge pkgs)
    ]
    ++ pkgs.lib.optionals (antigravity-app != null) [ antigravity-app ];
}
