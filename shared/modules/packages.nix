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
      ffmpeg
      git
      jq
      ripgrep
      rsync
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
      (setupctl pkgs)
    ]
    ++ pkgs.lib.optionals (antigravityCli != null) [ antigravityCli ];
}
