package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func updatePins(args []string) error {
	fs := newFlagSet("update-pins")
	repo := repoFlag(fs)
	if err := fs.Parse(args); err != nil {
		return err
	}

	kimakiVersion, err := npmVersion("kimaki")
	if err != nil {
		return err
	}
	edgeURL := "https://go.microsoft.com/fwlink/?linkid=2093504"
	kumospaceURL := "https://downloads.kumospace.com/production/macos/universal/latest/Kumospace.dmg"

	edgePrefetch, err := prefetchFile("MicrosoftEdge.pkg", edgeURL)
	if err != nil {
		return err
	}
	edgeVersion, err := edgePackageVersion(edgePrefetch.StorePath)
	if err != nil {
		return err
	}

	kumospacePrefetch, err := prefetchFile("Kumospace.dmg", kumospaceURL)
	if err != nil {
		return err
	}
	kumospaceVersion, err := kumospacePackageVersion(kumospacePrefetch.StorePath)
	if err != nil {
		return err
	}

	pins := fmt.Sprintf(`{
  kimaki.version = %q;

  microsoftEdge = {
    version = %q;
    url = %q;
    hash = %q;
  };

  kumospace = {
    version = %q;
    url = %q;
    hash = %q;
  };
}
`, kimakiVersion, edgeVersion, edgeURL, edgePrefetch.Hash, kumospaceVersion, kumospaceURL, kumospacePrefetch.Hash)

	if err := os.WriteFile(filepath.Join(*repo, "modules", "pins.nix"), []byte(pins), 0o644); err != nil {
		return err
	}
	fmt.Printf("Updated local pins: kimaki %s, microsoft-edge %s, kumospace %s\n", kimakiVersion, edgeVersion, kumospaceVersion)
	return nil
}

func npmVersion(pkg string) (string, error) {
	out, err := commandOutput("npm", "view", pkg, "version")
	return strings.TrimSpace(out), err
}

type prefetchResult struct {
	Hash      string `json:"hash"`
	StorePath string `json:"storePath"`
}

func prefetchFile(name, url string) (prefetchResult, error) {
	out, err := commandOutput("nix", "--extra-experimental-features", "nix-command flakes", "store", "prefetch-file", "--json", "--name", name, url)
	if err != nil {
		return prefetchResult{}, err
	}
	var result prefetchResult
	if err := json.Unmarshal([]byte(out), &result); err != nil {
		return prefetchResult{}, err
	}
	if result.Hash == "" || result.StorePath == "" {
		return prefetchResult{}, fmt.Errorf("incomplete prefetch result for %s", url)
	}
	return result, nil
}

func edgePackageVersion(storePath string) (string, error) {
	out, err := commandOutput("xar", "-tf", storePath)
	if err != nil {
		return "", err
	}
	version, err := firstSubmatch(out, `(?m)^MicrosoftEdge-([0-9][0-9.]+)\.pkg/?$`)
	if err != nil {
		return "", fmt.Errorf("extract Microsoft Edge version: %w", err)
	}
	return version, nil
}

func kumospacePackageVersion(storePath string) (string, error) {
	cmd7z := exec.Command("7z", "e", "-so", storePath, "Kumospace/Kumospace.app/Contents/Info.plist")
	var stderr7z bytes.Buffer
	cmd7z.Stderr = &stderr7z
	plist, err := cmd7z.Output()
	if err != nil && len(plist) == 0 {
		return "", fmt.Errorf("7z extract Kumospace Info.plist: %w: %s", err, strings.TrimSpace(stderr7z.String()))
	}
	cmd := exec.Command("/usr/bin/plutil", "-extract", "CFBundleShortVersionString", "raw", "-o", "-", "-")
	cmd.Stdin = bytes.NewReader(plist)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("plutil: %w: %s", err, strings.TrimSpace(stderr.String()))
	}
	version := strings.TrimSpace(string(out))
	if version == "" {
		return "", errors.New("extract Kumospace version: empty version")
	}
	return version, nil
}
