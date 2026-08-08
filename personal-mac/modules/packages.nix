{
  sharedPackages,
  antigravity-app ? null,
}:

let
  pins = import ./pins.nix;
in
rec {
  inherit (sharedPackages) ponytail;

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
  # ponytail: nixpkgs' obsidian.sourceRoot assumes the dmg unpacks straight to
  # "Obsidian.app", but this release nests it under "Obsidian <version>-universal/".
  # Drop this override once upstream fixes sourceRoot detection.
  obsidian =
    pkgs:
    pkgs.obsidian.overrideAttrs (old: {
      sourceRoot = "Obsidian ${old.version}-universal/${old.appname}.app";
    });

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
      (epubToMarkdown pkgs)
      (pdfToMarkdown pkgs)
      (transcriber pkgs)
    ];

  system =
    pkgs:
    systemFromNixpkgs pkgs
    ++ [
      (kumospace pkgs)
      (microsoftEdge pkgs)
      (obsidian pkgs)
    ]
    ++ pkgs.lib.optionals (antigravity-app != null) [ antigravity-app ];
}
