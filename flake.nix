{
  description = "Andy Toma's personal Mac setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    agentic-setup.url = "github:andycostintoma/agentic-setup";
    antigravity-nix.url = "github:jacopone/antigravity-nix";
    antigravity-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      nix-darwin,
      home-manager,
      agentic-setup,
      antigravity-nix,
      ...
    }:
    let
      releaseVersion = "26.05";
      username = "andytoma";
      host = "Andys-Mac-mini";
      system = "aarch64-darwin";
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
      agenticRoot = agentic-setup.outPath;
      agenticPackages = import (agenticRoot + "/modules/packages.nix") {
        antigravityCli = antigravity-nix.packages.${system}.google-antigravity-cli;
      };
      commonPackages = import ./modules/common-packages.nix { inherit agenticPackages; };
      packages = import ./modules/packages.nix {
        inherit commonPackages;
        antigravity-app = antigravity-nix.packages.${system}.google-antigravity;
      };
      harness = {
        shared = agenticRoot + "/harness/shared";
        opencode = agenticRoot + "/harness/opencode";
      };
      opencodeModule = agenticRoot + "/modules/opencode.nix";
      claudeModule = agenticRoot + "/modules/claude.nix";
      codexModule = agenticRoot + "/modules/codex.nix";
      antigravityModule = agenticRoot + "/modules/antigravity.nix";
      homeModule = import ./modules/home.nix {
        inherit username harness opencodeModule claudeModule codexModule antigravityModule;
        packages = packages.user;
        inherit (packages)
          kimaki
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
        setupctl = packages.setupctl pkgs;
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
