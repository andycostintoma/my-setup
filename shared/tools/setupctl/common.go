package main

import (
	"bytes"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"regexp"
	"strings"
)

func repoFlag(fs *flag.FlagSet) *string {
	wd, err := os.Getwd()
	if err != nil {
		wd = "."
	}
	return fs.String("repo", wd, "path to the setup repository")
}

func newFlagSet(name string) *flag.FlagSet {
	fs := flag.NewFlagSet(name, flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	return fs
}

func firstSubmatch(text, pattern string) (string, error) {
	match := regexp.MustCompile(pattern).FindStringSubmatch(text)
	if len(match) < 2 {
		return "", fmt.Errorf("no match for %s", pattern)
	}
	return match[1], nil
}

func commandOutput(name string, args ...string) (string, error) {
	out, err := commandBytes(name, args...)
	return string(out), err
}

func commandBytes(name string, args ...string) ([]byte, error) {
	cmd := exec.Command(name, args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("%s %s: %w: %s", name, strings.Join(args, " "), err, strings.TrimSpace(stderr.String()))
	}
	return out, nil
}
