{
  description = "MediDrive Linux VM setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
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
      username = "andy";
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      sharedRoot = shared.outPath;
      sharedHarness = {
        shared = sharedRoot + "/harness/shared";
        opencode = sharedRoot + "/harness/opencode";
      };
      sharedPackages = import (sharedRoot + "/modules/packages.nix") { };
      packages = import ./modules/packages.nix { inherit sharedPackages; };
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
        openviking = sharedPackages.openviking;
        packages = packages.user;
      };
    in
    {
      packages.${system}.setupctl = sharedPackages.setupctl pkgs;

      homeConfigurations.medidrive = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ homeModule ];
      };
    };
}
