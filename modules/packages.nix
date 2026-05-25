{ commonPackages }:

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
      whatsapp-for-mac
      zoom-us
    ];

  # Personal-only local packages.
  microsoftEdge =
    pkgs:
    pkgs.stdenvNoCC.mkDerivation {
      pname = "microsoft-edge";
      version = "148.0.3967.70";

      src = pkgs.fetchurl {
        name = "MicrosoftEdge-148.0.3967.70.pkg";
        url = "https://go.microsoft.com/fwlink/?linkid=2093504";
        hash = "sha256-24Hhs89fxtEVtDrjnBxBGw2GsVUj/OsygSDYGC5QNqU=";
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
      version = "6.1.0";

      src = pkgs.fetchurl {
        name = "Kumospace-6.1.0.dmg";
        url = "https://downloads.kumospace.com/production/macos/universal/latest/Kumospace.dmg";
        hash = "sha256-wOf4dabEIsJd5yHWXwlA/+lSrvz6ijVvZHLvswNZSas=";
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

  # Kimaki is not packaged in nixpkgs yet. Keep it pinned and invoked through
  # Nix-provided Node/npm tooling; do not install it globally with npm.
  kimaki =
    pkgs:
    let
      version = "0.12.0";
    in
    pkgs.runCommand "kimaki-${version}" { } ''
      mkdir -p $out/bin

      cat > $out/bin/kimaki <<'EOF'
      #!${pkgs.runtimeShell}
      exec ${pkgs.nodejs}/bin/npx -y kimaki@${version} "$@"
      EOF

      chmod +x $out/bin/kimaki
    '';

  user =
    pkgs:
    commonPackages.common pkgs
    ++ userFromNixpkgs pkgs
    ++ [
      (kimaki pkgs)
      (openclawUnhardlinked pkgs)
    ];

  system =
    pkgs:
    systemFromNixpkgs pkgs
    ++ [
      (kumospace pkgs)
      (microsoftEdge pkgs)
    ];
}
