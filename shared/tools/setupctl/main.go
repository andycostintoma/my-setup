package main

import (
	"errors"
	"fmt"
	"os"
	"strings"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) == 0 {
		return usageError()
	}

	switch args[0] {
	case "update-release":
		return updateRelease(args[1:])
	case "update-pins":
		return updatePins(args[1:])
	case "help", "-h", "--help":
		fmt.Println(usageText())
		return nil
	default:
		return fmt.Errorf("unknown command %q\n\n%s", args[0], usageText())
	}
}

func usageError() error {
	return errors.New(usageText())
}

func usageText() string {
	return strings.TrimSpace(`Usage: setupctl <command> [options]

Commands:
  update-release  Update flake.nix to the latest compatible Nix/Home Manager release
  update-pins     Update local-only package versions and hashes`)
}
