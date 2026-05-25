{
  description = "Andy Toma's minimal Nix, Home Manager, nix-darwin, and direnv setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nix-darwin, home-manager, ... }:
    let
      username = "andytoma";
      host = "Andys-Mac-mini";
      packages = import ./modules/packages.nix;
      harness = {
        shared = ./harness/shared;
        openclaw = ./harness/openclaw;
        opencode = ./harness/opencode;
      };

      homeModule = import ./modules/home.nix {
        inherit username harness;
        inherit (packages)
          kimaki
          openclawUnhardlinked
          openviking
          userPackages
          ;
      };

      darwinModule = import ./modules/darwin.nix {
        inherit username;
        inherit (packages) systemPackages;
      };

    in
    {
      darwinConfigurations.${host} = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          darwinModule
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "before-nix-darwin";
            home-manager.users.${username} = homeModule;
          }
        ];
      };
    };
}
