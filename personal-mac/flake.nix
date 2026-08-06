{
  description = "Andy Toma's personal Mac setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    antigravity-nix.url = "github:jacopone/antigravity-nix";
    antigravity-nix.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    shared.url = "path:../shared";
  };

  outputs =
    {
      nixpkgs,
      nix-darwin,
      home-manager,
      antigravity-nix,
      nix-homebrew,
      shared,
      ...
    }:
    let
      username = "andytoma";
      host = "Andys-Mac-mini";
      system = "aarch64-darwin";
      sharedRoot = shared.outPath;
      pkgs = import nixpkgs { inherit system; };
      sharedHarness = {
        shared = sharedRoot + "/harness/shared";
        opencode = sharedRoot + "/harness/opencode";
        antigravity = sharedRoot + "/harness/antigravity";
      };
      sharedPackages = import (sharedRoot + "/modules/packages.nix") {
        antigravityCli = antigravity-nix.packages.${system}.google-antigravity-cli;
      };
      packages = import ./modules/packages.nix {
        inherit sharedPackages;
        antigravity-app = antigravity-nix.packages.${system}.google-antigravity;
      };
      homeBaseModule = sharedRoot + "/modules/home-base.nix";
      opencodeModule = sharedRoot + "/modules/opencode.nix";
      claudeModule = sharedRoot + "/modules/claude.nix";
      codexModule = sharedRoot + "/modules/codex.nix";
      antigravityModule = sharedRoot + "/modules/antigravity.nix";
      homeModule = import ./modules/home.nix {
        inherit
          username
          homeBaseModule
          opencodeModule
          claudeModule
          codexModule
          antigravityModule
          ;
        harness = sharedHarness;
        packages = packages.user;
        inherit (packages) ponytail;
      };
      darwinModule = import ./modules/darwin.nix {
        inherit username;
        packages = packages.system;
      };
    in
    {
      packages.${system} = {
        setupctl = sharedPackages.setupctl pkgs;
        epub-to-markdown = packages.epubToMarkdown pkgs;
        pdf-to-markdown = packages.pdfToMarkdown pkgs;
      };

      darwinConfigurations.${host} = nix-darwin.lib.darwinSystem {
        inherit system;
        modules = [
          darwinModule
          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              enableRosetta = true; # documented default for Apple Silicon
              user = username;
            };
          }
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "before-my-setup";
            home-manager.users.${username} = homeModule;
          }
        ];
      };
    };
}
