{
  description = "Deviqon Linux setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    shared.url = "path:../shared";
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      shared,
      ...
    }:
    let
      system = "x86_64-linux";
      username = "atoma";
      homeDirectory = "/home/${username}";
      sharedRoot = shared.outPath;
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      harness = {
        shared = sharedRoot + "/harness/shared";
        opencode = sharedRoot + "/harness/opencode";
        antigravity = sharedRoot + "/harness/antigravity";
      };
      sharedPackages = import (sharedRoot + "/modules/packages.nix") { };
    in
    {
      packages.${system}.home-manager = home-manager.packages.${system}.default;

      homeConfigurations.deviqon = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          (import (sharedRoot + "/modules/home-base.nix") {
            inherit homeDirectory;
            gitEmail = "atoma@deviqon.com";
          })
          (import (sharedRoot + "/modules/opencode.nix") {
            inherit homeDirectory harness;
            opencodeConfig = harness.opencode + "/opencode.json";
          })
          (import (sharedRoot + "/modules/claude.nix") { inherit harness; })
          (import (sharedRoot + "/modules/codex.nix") { inherit harness; })
          (import (sharedRoot + "/modules/antigravity.nix") { inherit harness; })
          {
            home.username = username;
            home.homeDirectory = homeDirectory;
            home.stateVersion = "25.05";
            home.packages = (sharedPackages.packages pkgs) ++ [ pkgs.slack ];
          }
        ];
      };
    };
}
