package main

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(args []string) error {
	fs := flag.NewFlagSet("epub-to-markdown", flag.ContinueOnError)
	src := fs.String("src", "", "source EPUB file")
	destDir := fs.String("dest-dir", "", "destination folder for markdown and media")
	outputName := fs.String("output-name", "", "markdown filename to write inside dest dir")
	startMarker := fs.String("start-marker", "", "trim leading matter before this marker")
	unwrapBlockquotes := fs.Bool("unwrap-blockquotes", false, "unwrap top-level blockquotes during cleanup")
	if err := fs.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}
	if strings.TrimSpace(*src) == "" || strings.TrimSpace(*destDir) == "" {
		return errors.New("usage: epub-to-markdown --src PATH --dest-dir PATH [options]")
	}

	absSrc, err := filepath.Abs(*src)
	if err != nil {
		return err
	}
	absDestDir, err := filepath.Abs(*destDir)
	if err != nil {
		return err
	}
	if _, err := os.Stat(absSrc); err != nil {
		return fmt.Errorf("source EPUB not found: %s", absSrc)
	}
	if *outputName == "" {
		base := filepath.Base(absSrc)
		*outputName = strings.TrimSuffix(base, filepath.Ext(base)) + ".md"
	}

	if err := os.RemoveAll(absDestDir); err != nil {
		return err
	}
	if err := os.MkdirAll(absDestDir, 0o755); err != nil {
		return err
	}
	if err := runInDir(absDestDir, "pandoc", absSrc, "-f", "epub", "-t", "gfm", "--wrap=none", "--extract-media=media", "-o", *outputName); err != nil {
		return err
	}

	outputPath := filepath.Join(absDestDir, *outputName)
	data, err := os.ReadFile(outputPath)
	if err != nil {
		return err
	}
	text := cleanInlineMarkup(string(data))
	if *startMarker != "" {
		text, err = trimToMarker(text, *startMarker)
		if err != nil {
			return err
		}
	}
	text = rewriteBlocks(text, *unwrapBlockquotes)
	if err := verifyOutput(text); err != nil {
		return err
	}
	if err := os.WriteFile(outputPath, []byte(text), 0o644); err != nil {
		return err
	}
	fmt.Println(outputPath)
	return nil
}

func runInDir(dir, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("command failed in %s: %s %s: %w", dir, name, strings.Join(args, " "), err)
	}
	return nil
}

func cleanInlineMarkup(text string) string {
	replacements := []struct {
		pattern string
		repl    string
	}{
		{`\r`, ``},
		{`<svg\b.*?</svg>`, ``},
		{`<img\s+[^>]*src="([^"]+)"[^>]*>`, `![]($1)`},
		{`<a\b[^>]*>(.*?)</a>`, `$1`},
		{`<strong>(.*?)</strong>`, `**$1**`},
		{`<samp\b[^>]*>(.*?)</samp>`, "`$1`"},
		{`<figcaption><p>(.*?)</p></figcaption>`, `$1`},
		{`(?i)<br\s*/?>`, ` / `},
		{`<td\b[^>]*>`, ``},
		{`<span class="calibre10"><span class="bold">Chapter (\d+)\.\s+(.+?)</span></span>`, `## Chapter $1: $2`},
		{`<span class="calibre27"><span class="bold">(.+?)</span></span>`, `### $1`},
		{`<span class="calibre49"><span class="bold">(.+?)</span></span>`, `#### $1`},
		{`<span class="bold">(.+?)</span>`, `**$1**`},
		{`<span class="italic">(.+?)</span>`, `*$1*`},
		{`\*\*\*([^*]+)\*{5}:\*\*`, `**$1:**`},
		{`\*{5}([^*]+)\*{5}`, `*$1*`},
		{`<span\b[^>]*>`, ``},
		{`<div\b[^>]*>`, ``},
		{`<nav\b[^>]*>`, ``},
		{`\]\(#(?:[^)]+\.html[^)]*|c\d+\.xhtml[^)]*)\)`, `]`},
	}

	text = strings.ReplaceAll(text, "\u00a0", " ")
	for _, r := range replacements {
		text = regexp.MustCompile(r.pattern).ReplaceAllString(text, r.repl)
	}
	for _, tag := range []string{"</td>", "<p>", "</p>", "<sup>", "</sup>", "</span>", "</div>", "</nav>"} {
		text = strings.ReplaceAll(text, tag, "")
	}
	return text
}

func trimToMarker(text, marker string) (string, error) {
	idx := strings.Index(text, marker)
	if idx == -1 {
		return "", fmt.Errorf("missing start marker: %s", marker)
	}
	return text[idx:], nil
}

func rewriteBlocks(text string, unwrapBlockquotes bool) string {
	out := make([]string, 0)
	lines := strings.Split(strings.ReplaceAll(text, "\r", ""), "\n")
	codeBlockLine := regexp.MustCompile("^> > `.*`\\\\?$")

	for i := 0; i < len(lines); {
		line := lines[i]
		if codeBlockLine.MatchString(line) {
			block := make([]string, 0)
			for i < len(lines) && codeBlockLine.MatchString(lines[i]) {
				code := strings.TrimPrefix(lines[i], "> > ")
				code = strings.TrimPrefix(code, "`")
				code = strings.TrimSuffix(code, "`\\")
				code = strings.TrimSuffix(code, "`")
				block = append(block, code)
				i++
			}
			out = append(out, "```")
			out = append(out, block...)
			out = append(out, "```")
			continue
		}

		if strings.TrimSpace(line) == "" {
			line = ""
		}
		if line != "" {
			line = strings.TrimSuffix(line, "\\")
		}
		line = regexp.MustCompile(`^> > •\s+`).ReplaceAllString(line, "- ")
		line = regexp.MustCompile(`^> •\s+`).ReplaceAllString(line, "- ")
		if strings.HasPrefix(line, ">") {
			line = regexp.MustCompile(`^(?:>\s*)+`).ReplaceAllString(line, "> ")
		}
		if unwrapBlockquotes {
			line = strings.TrimPrefix(line, "> ")
		}
		if line == ">" || line == "> " || line == "\\" {
			line = ""
		}
		if !hasAnyPrefix(line, "#", "##", "###", "####", "-", ">", "![", "[", "|", "```") && regexp.MustCompile(`^Chapter \d+[.:] `).MatchString(line) {
			line = regexp.MustCompile(`^Chapter (\d+)\.\s+`).ReplaceAllString(line, `## Chapter $1: `)
		}

		out = append(out, line)
		i++
	}

	cleaned := strings.Join(out, "\n")
	cleaned = regexp.MustCompile(`(?m)^\[\*\*Click here to view code image\*\*\]\([^\n]+\)\n?`).ReplaceAllString(cleaned, "")
	cleaned = regexp.MustCompile(`(?m)^<[^>]+>\s*$`).ReplaceAllString(cleaned, "")
	cleaned = normalizeSetextHeadings(cleaned)
	cleaned = normalizeFigureCaptions(cleaned)
	cleaned = regexp.MustCompile(`\n{3,}`).ReplaceAllString(cleaned, "\n\n")
	return strings.TrimSpace(cleaned) + "\n"
}

func hasAnyPrefix(text string, prefixes ...string) bool {
	for _, prefix := range prefixes {
		if strings.HasPrefix(text, prefix) {
			return true
		}
	}
	return false
}

func normalizeSetextHeadings(text string) string {
	text = regexp.MustCompile(`(?m)^PART\s+([IVX]+)\\?\n\\?\n([^\n]+)\n=+\n`).ReplaceAllString(text, "# Part $1\n\n## $2\n")
	return regexp.MustCompile(`(?m)^(\d+)\\?\n([^\n]+)\n=+\n`).ReplaceAllString(text, "## Chapter $1: $2\n")
}

func normalizeFigureCaptions(text string) string {
	return regexp.MustCompile(`(?m)^#{1,6}\s+(Figure\s+[^\n]+|FIGURE\s+[^\n]+)`).ReplaceAllString(text, "**$1**")
}

func verifyOutput(text string) error {
	failures := make([]string, 0)
	checks := []struct {
		pattern string
		failure string
	}{
		{`\]\(#(?:[^)]+\.html[^)]*|c\d+\.xhtml[^)]*)\)`, "found internal EPUB fragment links"},
		{`\.calibre|\{=html\}|\[\]\{#|:::`, "found raw calibre markers"},
		{`</?(?:span|div|nav)\b`, "found raw span/div/nav tags"},
		{`(?m)^#{1,6}\s+(?:Figure|FIGURE)\b`, "found figure rendered as heading"},
	}
	for _, check := range checks {
		if regexp.MustCompile(check.pattern).MatchString(text) {
			failures = append(failures, check.failure)
		}
	}

	imageRe := regexp.MustCompile(`!\[[^\]]*\]\(([^)]+)\)`)
	badImagePaths := make([]string, 0)
	for _, match := range imageRe.FindAllStringSubmatch(text, -1) {
		path := match[1]
		if !hasAnyPrefix(path, "media/", "http://", "https://") {
			badImagePaths = append(badImagePaths, path)
		}
	}
	if len(badImagePaths) > 0 {
		slices.Sort(badImagePaths)
		badImagePaths = slices.Compact(badImagePaths)
		failures = append(failures, fmt.Sprintf("found non-local media image paths: %s", strings.Join(badImagePaths, ", ")))
	}
	if len(failures) > 0 {
		return fmt.Errorf("verification failed: %s", strings.Join(failures, "; "))
	}
	return nil
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
