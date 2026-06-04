{ agenticPackages }:

rec {
  inherit (agenticPackages) openviking graphify openchamber;

  commonFromNixpkgs =
    pkgs: with pkgs; [
      curl
      docker-compose
      gh
      git
      go
      gopls
      jq
      nil
      nixfmt
      ripgrep
      tmux
      tree
      ty
      watch
      wget
    ];

  common = pkgs: commonFromNixpkgs pkgs ++ agenticPackages.packages pkgs;
}
