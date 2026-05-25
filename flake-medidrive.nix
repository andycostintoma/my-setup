{
  home-manager,
  nixpkgs,
  username,
  system,
  harness,
  sharedPackages,
}:

let
  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };

  packages = import ./modules/medidrive/packages.nix { inherit sharedPackages; };

  homeModule = import ./modules/medidrive/home.nix {
    inherit username harness;
    packages = packages.user;
  };
in
{
  medidrive = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [ homeModule ];
  };
}
