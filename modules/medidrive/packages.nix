{ sharedPackages }:

{
  user = pkgs: sharedPackages.common pkgs;
}
