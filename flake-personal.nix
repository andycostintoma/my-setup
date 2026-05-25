{
  nix-darwin,
  home-manager,
  username,
  host,
  harness,
  sharedPackages,
}:

let
  packages = import ./modules/personal/packages.nix { inherit sharedPackages; };

  homeModule = import ./modules/personal/home.nix {
    inherit username harness;
    packages = packages.user;
    inherit (packages)
      kimaki
      openclawUnhardlinked
      openviking
      ;
  };

  darwinModule = import ./modules/personal/darwin.nix {
    inherit username;
    packages = packages.system;
  };
in
{
  ${host} = nix-darwin.lib.darwinSystem {
    system = "aarch64-darwin";
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
}
