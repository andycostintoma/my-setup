{
  description = "Andy Toma's personal Mac setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      nix-darwin,
      home-manager,
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
        in
        {
          nixpkgs = lock.nodes.nixpkgs.original.ref or "";
          home-manager = lock.nodes.home-manager.original.ref or "";
        };
      releaseRefsMatch =
        lockedRefs.nixpkgs == releaseRefs.nixpkgs && lockedRefs.home-manager == releaseRefs.home-manager;
      pkgs = import nixpkgs { inherit system; };
      commonPackages = import ./modules/common-packages.nix;
      packages = import ./modules/packages.nix { inherit commonPackages; };
      harness = {
        shared = ./harness/shared;
        openclaw = ./harness/openclaw;
        opencode = ./harness/opencode;
      };
      homeModule = import ./modules/home.nix {
        inherit username harness;
        packages = packages.user;
        inherit (packages)
          kimaki
          openclawUnhardlinked
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
