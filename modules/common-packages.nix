let
  pins = import ./pins.nix;
in
rec {
  commonFromNixpkgs =
    pkgs: with pkgs; [
      claude-code
      curl
      docker-compose
      gh
      git
      go
      gopls
      jq
      nil
      nixfmt
      nodejs
      bun
      opencode
      ripgrep
      rtk
      tmux
      tree
      ty
      uv
      watch
      wget
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
      uvxGraphify = "${pkgs.uv}/bin/uvx --from graphifyy==${version}";
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

  common =
    pkgs:
    commonFromNixpkgs pkgs
    ++ [
      (graphify pkgs)
      (openviking pkgs)
    ];
}
