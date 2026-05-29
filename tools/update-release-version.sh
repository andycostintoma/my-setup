#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

nixpkgs_versions="$(
  git ls-remote --heads https://github.com/NixOS/nixpkgs.git 'refs/heads/nixpkgs-*-darwin' \
    | perl -ne 'print "$1\n" if m{refs/heads/nixpkgs-([0-9]+\.[0-9]+)-darwin$}'
)"

home_manager_versions="$(
  git ls-remote --heads https://github.com/nix-community/home-manager.git 'refs/heads/release-*' \
    | perl -ne 'print "$1\n" if m{refs/heads/release-([0-9]+\.[0-9]+)$}'
)"

latest_release="$(
  perl -e '
    use strict;
    use warnings;

    my (%nixpkgs, %home_manager);
    my $mode = "nixpkgs";

    while (my $line = <STDIN>) {
      chomp $line;
      if ($line eq "--home-manager--") {
        $mode = "home-manager";
        next;
      }
      next unless $line =~ /^([0-9]+)\.([0-9]+)$/;
      if ($mode eq "nixpkgs") {
        $nixpkgs{$line} = 1;
      } else {
        $home_manager{$line} = 1;
      }
    }

    my @common = grep { $home_manager{$_} } keys %nixpkgs;
    die "No common nixpkgs/Home Manager release branches found\n" unless @common;

    @common = sort {
      my ($ay, $am) = split /\./, $a;
      my ($by, $bm) = split /\./, $b;
      $ay <=> $by || $am <=> $bm;
    } @common;

    print $common[-1], "\n";
  ' <<<"$nixpkgs_versions
--home-manager--
$home_manager_versions"
)"

current_release="$(perl -ne 'print "$1\n" if /releaseVersion = "([0-9]+\.[0-9]+)"/' flake.nix)"

if [ "$current_release" = "$latest_release" ]; then
  printf 'Already using latest compatible Nix/Home Manager release: %s\n' "$latest_release"
  exit 0
fi

LATEST_RELEASE="$latest_release" perl -0pi -e '
  my $release = $ENV{LATEST_RELEASE};
  s{nixpkgs\.url = "github:NixOS/nixpkgs/nixpkgs-[0-9]+\.[0-9]+-darwin";}{nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-$release-darwin";};
  s{home-manager\.url = "github:nix-community/home-manager/release-[0-9]+\.[0-9]+";}{home-manager.url = "github:nix-community/home-manager/release-$release";};
  s{releaseVersion = "[0-9]+\.[0-9]+";}{releaseVersion = "$release";};
' flake.nix

printf 'Updated Nix/Home Manager release: %s -> %s\n' "$current_release" "$latest_release"
