{
  description = "MediDrive Linux VM setup";

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
      username = "andy";
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        # ponytail: t3code (SSH pairing shim) still pins an EOL electron build;
        # drop this once nixpkgs updates t3code's electron version.
        config.permittedInsecurePackages = [ "electron-40.10.5" ];
      };
      sharedRoot = shared.outPath;
      sharedHarness = {
        shared = sharedRoot + "/harness/shared";
        opencode = sharedRoot + "/harness/opencode";
        antigravity = sharedRoot + "/harness/antigravity";
      };
      sharedPackages = import (sharedRoot + "/modules/packages.nix") { };
      packages = import ./modules/packages.nix { inherit sharedPackages; };
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
      };
    in
    {
      packages.${system} = {
        setupctl = sharedPackages.setupctl pkgs;
        home-manager = home-manager.packages.${system}.default;
      };

      homeConfigurations.medidrive = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ homeModule ];
      };
    };
}
