{
  antigravityCli ? null,
}:
let
  pins = import ./pins.nix;
in
rec {
  fromNixpkgs =
    pkgs: with pkgs; [
      # Core shell and inspection tools.
      bat
      curl
      delta
      fd
      git
      jq
      ripgrep
      tmux
      tree
      watch
      wget
      yq-go

      # Nix tooling.
      nil
      nixfmt

      # Go and protobuf tooling.
      go
      gopls
      buf
      grpcurl
      protoc-gen-go
      protoc-gen-go-grpc

      # Cloud, containers, and Kubernetes.
      docker-compose
      kubectl

      # JavaScript, Python, and general runtimes.
      bun
      nodejs
      ty
      uv

      # Agentic coding CLIs.
      claude-code
      codex
      opencode
      rtk

      # Repository hosting.
      gh
    ];

  # OpenViking's PyPI wheel carries native Rust/C++ artifacts and Python
  # dependencies that are not all packaged in nixpkgs yet. Keep this as the
  # one documented package-manager shim exception: Nix provides uv/uvx and
  # the invoked OpenViking version is pinned here.
  openviking =
    pkgs:
    let
      version = pins.openviking.version;
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

  graphify =
    pkgs:
    let
      version = pins.graphifyy.version;
      uvxGraphify = "${pkgs.uv}/bin/uvx --python ${pkgs.python3}/bin/python3 --from graphifyy==${version}";
    in
    pkgs.runCommand "graphify-${version}" { } ''
      mkdir -p $out/bin

      cat > $out/bin/graphify <<'EOF'
      #!${pkgs.runtimeShell}
      exec ${uvxGraphify} graphify "$@"
      EOF

      cat > $out/bin/graphify-python <<'EOF'
      #!${pkgs.runtimeShell}
      exec ${uvxGraphify} python "$@"
      EOF

      chmod +x $out/bin/graphify $out/bin/graphify-python
    '';

  ponytail =
    pkgs:
    pkgs.stdenvNoCC.mkDerivation {
      pname = "ponytail";
      version = pins.ponytail.version;

      src = pkgs.fetchFromGitHub {
        owner = "DietrichGebert";
        repo = "ponytail";
        rev = "v${pins.ponytail.version}";
        hash = pins.ponytail.hash;
      };

      dontConfigure = true;
      dontBuild = true;

      installPhase = ''
        runHook preInstall

        mkdir -p $out
        cp -R . $out/

        runHook postInstall
      '';
    };

  setupctl =
    pkgs:
    pkgs.buildGoModule {
      pname = "setupctl";
      version = "0.1.0";
      src = ../tools/setupctl;
      vendorHash = null;
    };

  packages =
    pkgs:
    fromNixpkgs pkgs
    ++ [
      (graphify pkgs)
      (openviking pkgs)
      (setupctl pkgs)
    ]
    ++ pkgs.lib.optionals (antigravityCli != null) [ antigravityCli ];
}
