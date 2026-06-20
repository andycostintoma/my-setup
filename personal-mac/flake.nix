{
  description = "Andy Toma's personal Mac setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    antigravity-nix.url = "github:jacopone/antigravity-nix";
    antigravity-nix.inputs.nixpkgs.follows = "nixpkgs";
    shared.url = "path:../shared";
  };

  outputs =
    {
      nixpkgs,
      nix-darwin,
      home-manager,
      antigravity-nix,
      shared,
      ...
    }:
    let
      releaseVersion = "26.05";
      username = "andytoma";
      host = "Andys-Mac-mini";
      system = "aarch64-darwin";
      sharedRoot = shared.outPath;
      releaseRefs = {
        nixpkgs = "nixpkgs-${releaseVersion}-darwin";
        home-manager = "release-${releaseVersion}";
      };
      lockedRefs =
        let
          lock = builtins.fromJSON (builtins.readFile ./flake.lock);
          rootInputs = lock.nodes.root.inputs;
          rootNixpkgs = rootInputs.nixpkgs;
          rootHomeManager = rootInputs.home-manager;
        in
        {
          nixpkgs = lock.nodes.${rootNixpkgs}.original.ref or "";
          home-manager = lock.nodes.${rootHomeManager}.original.ref or "";
        };
      releaseRefsMatch =
        lockedRefs.nixpkgs == releaseRefs.nixpkgs && lockedRefs.home-manager == releaseRefs.home-manager;
      pkgs = import nixpkgs { inherit system; };
      sharedHarness = {
        shared = sharedRoot + "/harness/shared";
        opencode = sharedRoot + "/harness/opencode";
      };
      sharedPackages = import (sharedRoot + "/modules/packages.nix") {
        antigravityCli = antigravity-nix.packages.${system}.google-antigravity-cli;
      };
      packages = import ./modules/packages.nix {
        inherit sharedPackages;
        antigravity-app = antigravity-nix.packages.${system}.google-antigravity;
      };
      opencodeModule = sharedRoot + "/modules/opencode.nix";
      claudeModule = sharedRoot + "/modules/claude.nix";
      codexModule = sharedRoot + "/modules/codex.nix";
      antigravityModule = sharedRoot + "/modules/antigravity.nix";
      homeModule = import ./modules/home.nix {
        inherit
          username
          opencodeModule
          claudeModule
          codexModule
          antigravityModule
          ;
        harness = sharedHarness;
        packages = packages.user;
        inherit (packages)
          openviking
          ;
      };
      darwinModule = import ./modules/darwin.nix {
        inherit username;
        packages = packages.system;
      };
    in
    {
      checks.${system}.release-refs-match =
        if releaseRefsMatch then
          pkgs.runCommand "release-refs-match" { } ''
            touch "$out"
          ''
        else
          throw ''
            flake.lock release refs must match releaseVersion ${releaseVersion}.
            nixpkgs: expected ${releaseRefs.nixpkgs}, got ${lockedRefs.nixpkgs}
            home-manager: expected ${releaseRefs.home-manager}, got ${lockedRefs.home-manager}
          '';

      packages.${system} = {
        setupctl = sharedPackages.setupctl pkgs;
        epub-to-markdown = packages.epubToMarkdown pkgs;
        pdf-to-markdown = packages.pdfToMarkdown pkgs;
      };

      darwinConfigurations.${host} = nix-darwin.lib.darwinSystem {
        inherit system;
        modules = [
          darwinModule
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
