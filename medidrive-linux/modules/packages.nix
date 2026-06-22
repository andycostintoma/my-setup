{ sharedPackages }:

rec {
  inherit (sharedPackages) openviking graphify setupctl;

  # google-cloud-sdk with the GKE auth plugin so `kubectl` can pull credentials
  # via `gcloud container clusters get-credentials`. Kept as a custom expression
  # because the plugin must be wired through `withExtraComponents`.
  gcloud =
    pkgs:
    pkgs.google-cloud-sdk.withExtraComponents [
      pkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin
    ];

  # spanner-cli is not packaged in nixpkgs; vendored via buildGoModule.
  spanner-cli =
    pkgs:
    pkgs.buildGoModule rec {
      pname = "spanner-cli";
      version = "0.11.2";
      src = pkgs.fetchFromGitHub {
        owner = "cloudspannerecosystem";
        repo = "spanner-cli";
        rev = "v${version}";
        hash = "sha256-msKNZvrvvYCxFRMTdUUpfRx26KRE7a7FO91/0sifd6M=";
      };
      vendorHash = "sha256-Qi3nBaoL/Px8ujRW2H2fXoJHc9CQ+BeGMpPl/XI7gCE=";
    };

  # Shim so t3code desktop-app SSH pairing finds `t3` on PATH without
  # trying to `npm install -g t3@<electron-version>`.
  t3 =
    pkgs:
    pkgs.runCommand "t3-shim" { } ''
      mkdir -p $out/bin
      ln -s ${pkgs.t3code}/bin/t3code $out/bin/t3
    '';

  coderabbit =
    pkgs:
    pkgs.stdenv.mkDerivation rec {
      pname = "coderabbit";
      version = "0.4.5";

      src = pkgs.fetchurl {
        url = "https://cli.coderabbit.ai/releases/${version}/coderabbit-linux-x64.zip";
        hash = "sha256-2burC25B/3CFlt5HwmBt84IMz2xltbFfDkeO8HawW6A=";
      };

      nativeBuildInputs = [
        pkgs.autoPatchelfHook
        pkgs.unzip
      ];

      buildInputs = [ pkgs.stdenv.cc.cc.lib ];

      dontStrip = true;

      unpackPhase = ''
        runHook preUnpack
        unzip $src
        runHook postUnpack
      '';

      installPhase = ''
        runHook preInstall
        install -Dm755 coderabbit $out/bin/coderabbit
        ln -s coderabbit $out/bin/cr
        runHook postInstall
      '';

      meta = with pkgs.lib; {
        description = "CodeRabbit CLI - AI code review from the terminal";
        homepage = "https://www.coderabbit.ai/cli";
        license = licenses.unfree;
        mainProgram = "coderabbit";
        platforms = [ "x86_64-linux" ];
      };
    };

  user =
    pkgs:
    sharedPackages.packages pkgs
    ++ [
      (coderabbit pkgs)
      (gcloud pkgs)
      (spanner-cli pkgs)
      (t3 pkgs)
    ];
}
