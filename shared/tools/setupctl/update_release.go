package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
)

func updateRelease(args []string) error {
	fs := newFlagSet("update-release")
	repo := repoFlag(fs)
	if err := fs.Parse(args); err != nil {
		return err
	}

	nixpkgsBranches, err := gitReleaseBranches("https://github.com/NixOS/nixpkgs.git", `refs/heads/nixpkgs-([0-9]+\.[0-9]+)-darwin$`)
	if err != nil {
		return err
	}
	homeManagerBranches, err := gitReleaseBranches("https://github.com/nix-community/home-manager.git", `refs/heads/release-([0-9]+\.[0-9]+)$`)
	if err != nil {
		return err
	}

	common := make([]string, 0)
	for version := range nixpkgsBranches {
		if homeManagerBranches[version] {
			common = append(common, version)
		}
	}
	if len(common) == 0 {
		return errors.New("no common nixpkgs/Home Manager release branches found")
	}
	slices.SortFunc(common, compareReleaseVersions)
	latestRelease := common[len(common)-1]

	flakePath := filepath.Join(*repo, "flake.nix")
	flake, err := os.ReadFile(flakePath)
	if err != nil {
		return err
	}
	currentRelease, err := firstSubmatch(string(flake), `releaseVersion = "([0-9]+\.[0-9]+)"`)
	if err != nil {
		return fmt.Errorf("read current release version: %w", err)
	}
	if currentRelease == latestRelease {
		fmt.Printf("Already using latest compatible Nix/Home Manager release: %s\n", latestRelease)
		return nil
	}

	updated := regexp.MustCompile(`nixpkgs\.url = "github:NixOS/nixpkgs/nixpkgs-[0-9]+\.[0-9]+-darwin";`).ReplaceAllString(string(flake), fmt.Sprintf(`nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-%s-darwin";`, latestRelease))
	updated = regexp.MustCompile(`home-manager\.url = "github:nix-community/home-manager/release-[0-9]+\.[0-9]+";`).ReplaceAllString(updated, fmt.Sprintf(`home-manager.url = "github:nix-community/home-manager/release-%s";`, latestRelease))
	updated = regexp.MustCompile(`releaseVersion = "[0-9]+\.[0-9]+";`).ReplaceAllString(updated, fmt.Sprintf(`releaseVersion = "%s";`, latestRelease))

	if err := os.WriteFile(flakePath, []byte(updated), 0o644); err != nil {
		return err
	}
	fmt.Printf("Updated Nix/Home Manager release: %s -> %s\n", currentRelease, latestRelease)
	return nil
}

func gitReleaseBranches(remote, pattern string) (map[string]bool, error) {
	out, err := commandOutput("git", "ls-remote", "--heads", remote)
	if err != nil {
		return nil, err
	}
	re := regexp.MustCompile(pattern)
	branches := make(map[string]bool)
	for _, line := range strings.Split(out, "\n") {
		match := re.FindStringSubmatch(line)
		if len(match) == 2 {
			branches[match[1]] = true
		}
	}
	return branches, nil
}

func compareReleaseVersions(a, b string) int {
	ay, am := splitReleaseVersion(a)
	by, bm := splitReleaseVersion(b)
	if ay != by {
		return ay - by
	}
	return am - bm
}

func splitReleaseVersion(version string) (int, int) {
	parts := strings.Split(version, ".")
	year, _ := strconv.Atoi(parts[0])
	month, _ := strconv.Atoi(parts[1])
	return year, month
}
