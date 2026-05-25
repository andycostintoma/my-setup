rec {
  # Plain nixpkgs packages: these update with `nix flake update`.
  userPackagesFromNixpkgs =
    pkgs: with pkgs; [
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
      bun
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

  systemPackagesFromNixpkgs =
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

  # Local packages: not available from nixpkgs for this Mac, or need custom wrapping.
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

  # OpenViking's PyPI wheel carries native Rust/C++ artifacts and Python
  # dependencies that are not all packaged in nixpkgs yet. Keep this as the
  # one documented package-manager shim exception: Nix provides uv/uvx and
  # the invoked OpenViking version is pinned here.
  openviking =
    pkgs:
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

  userPackages =
    pkgs:
    userPackagesFromNixpkgs pkgs
    ++ [
      (kimaki pkgs)
      (openclawUnhardlinked pkgs)
      (openviking pkgs)
    ];

  systemPackages =
    pkgs:
    systemPackagesFromNixpkgs pkgs
    ++ [
      (kumospace pkgs)
      (microsoftEdge pkgs)
    ];
}
