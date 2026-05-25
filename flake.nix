{
  description = "Andy Toma's personal and work machine setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nix-darwin,
      home-manager,
      nixpkgs,
      ...
    }:
    let
      username = "andytoma";
      host = "Andys-Mac-mini";
      medidriveUsername = "andy";
      medidriveSystem = "x86_64-linux";
      sharedPackages = import ./modules/shared/packages.nix;
      harness = {
        shared = ./harness/shared;
        openclaw = ./harness/openclaw;
        opencode = ./harness/opencode;
      };
    in
    {
      darwinConfigurations = import ./flake-personal.nix {
        inherit
          nix-darwin
          home-manager
          username
          host
          harness
          sharedPackages
          ;
      };

      homeConfigurations = import ./flake-medidrive.nix {
        inherit
          home-manager
          nixpkgs
          harness
          sharedPackages
          ;
        username = medidriveUsername;
        system = medidriveSystem;
      };
    };
}
