{ agenticPackages }:

rec {
  inherit (agenticPackages) openviking graphify;

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
      tmux
      tree
      ty
      watch
      wget
    ];

  common = pkgs: commonFromNixpkgs pkgs ++ agenticPackages.packages pkgs;
}
