package main

import (
	"bytes"
	"encoding/xml"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"unicode"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(args []string) error {
	fs := flag.NewFlagSet("pdf-to-markdown", flag.ContinueOnError)
	src := fs.String("src", "", "source PDF file")
	destDir := fs.String("dest-dir", "", "destination folder for markdown")
	outputName := fs.String("output-name", "", "markdown filename to write inside dest dir")
	startMarker := fs.String("start-marker", "", "trim leading matter before this marker")
	startAtChapter1 := fs.Bool("start-at-chapter-1", false, "start at Chapter 1 using the PDF outline when available")
	backend := fs.String("backend", "pdftohtml-xml", "backend: pdftohtml-xml or pdftotext")
	if err := fs.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}
	if strings.TrimSpace(*src) == "" || strings.TrimSpace(*destDir) == "" {
		return errors.New("usage: pdf-to-markdown --src PATH --dest-dir PATH [options]")
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
		return fmt.Errorf("source PDF not found: %s", absSrc)
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

	var text string

	switch strings.TrimSpace(*backend) {
	case "pdftohtml-xml":
		text, err = convertViaPdftohtmlXML(absSrc, absDestDir, *startAtChapter1)
		if err != nil {
			return err
		}
	case "pdftotext":
		rawText, err := extractText(absSrc)
		if err != nil {
			return err
		}
		text = convertToMarkdown(rawText)
	default:
		return fmt.Errorf("unknown backend: %s", *backend)
	}

	if *startMarker != "" {
		text, err = trimToMarker(text, *startMarker)
		if err != nil {
			return err
		}
	}
	if err := verifyOutput(text); err != nil {
		return err
	}

	outputPath := filepath.Join(absDestDir, *outputName)
	if err := os.WriteFile(outputPath, []byte(text), 0o644); err != nil {
		return err
	}
	fmt.Println(outputPath)
	return nil
}

var (
	pageNumRX      = regexp.MustCompile(`^(?:\d+|[ivxlcdmIVXLCDM]+)$`)
	sentenceEndRX  = regexp.MustCompile(`[.!?]["')\]]*\s*$`)
	sectionHeading = regexp.MustCompile(`^(\d+(?:\.\d+){1,3})\s+(.+)$`)
	captionStartRX = regexp.MustCompile(`^(Figure|FIGURE|Table|TABLE)\b`)
	continuationRX = regexp.MustCompile(`^(including|and|or|but|with|which|that|where|when|while|because|since|as|such)\b`)
)

type xmlFontSpec struct {
	ID   string `xml:"id,attr"`
	Size string `xml:"size,attr"`
}

type xmlImage struct {
	Top    string `xml:"top,attr"`
	Left   string `xml:"left,attr"`
	Width  string `xml:"width,attr"`
	Height string `xml:"height,attr"`
	Src    string `xml:"src,attr"`
}

type xmlText struct {
	Top  string `xml:"top,attr"`
	Left string `xml:"left,attr"`
	Font string `xml:"font,attr"`
	Body string `xml:",innerxml"`
}

type pageBlock struct {
	Top      int
	Left     int
	Kind     string // "t" or "i"
	FontSize int
	Payload  string
}

type pageModel struct {
	Number int
	Width  int
	Height int
	Fonts  map[string]int
	Blocks []pageBlock
}

func convertViaPdftohtmlXML(srcPDF, destDir string, startAtChapter1 bool) (string, error) {
	tmpDir, err := os.MkdirTemp("", "pdf-to-markdown-")
	if err != nil {
		return "", err
	}
	defer os.RemoveAll(tmpDir)

	startPage := 1
	if startAtChapter1 {
		probeBase := filepath.Join(tmpDir, "probe")
		probeXML, err := runPdftohtmlXML(srcPDF, probeBase, 1, 1)
		if err != nil {
			return "", err
		}
		p, err := outlineChapter1StartPage(probeXML)
		if err != nil {
			return "", err
		}
		if p > 0 {
			startPage = p
		}
	}

	outBase := filepath.Join(tmpDir, "out")
	xmlPath, err := runPdftohtmlXML(srcPDF, outBase, startPage, 2000)
	if err != nil {
		return "", err
	}

	// Compute repeating header/footer lines first.
	headerFooter, err := headerFooterLines(xmlPath)
	if err != nil {
		return "", err
	}

	mediaDir := filepath.Join(destDir, "media")
	if err := os.MkdirAll(mediaDir, 0o755); err != nil {
		return "", err
	}

	var out strings.Builder
	pendingTail := ""

	dec, err := newXMLDecoderWithSanitizer(xmlPath)
	if err != nil {
		return "", err
	}
	defer dec.close()

	for {
		pm, ok, err := nextPage(dec.decoder)
		if err != nil {
			return "", err
		}
		if !ok {
			break
		}
		md, err := convertPageToMarkdown(pm, tmpDir, mediaDir, headerFooter)
		if err != nil {
			return "", err
		}
		if strings.TrimSpace(md) == "" {
			continue
		}
		blocks := mdBlocks(md)

		if pendingTail != "" {
			blocks = joinAcrossPages(pendingTail, blocks)
			if !strings.HasSuffix(pendingTail, "\n") {
				pendingTail = ""
			}
		}
		pendingTail = ""

		// Buffer incomplete tail paragraph.
		if len(blocks) > 0 {
			last := blocks[len(blocks)-1]
			if isPlainParagraph(last) && len(last) >= 40 && !sentenceEndRX.MatchString(strings.TrimSpace(last)) {
				pendingTail = last
				blocks = blocks[:len(blocks)-1]
			}
		}

		if len(blocks) > 0 {
			out.WriteString(strings.Join(blocks, "\n\n"))
			out.WriteString("\n\n")
		}
	}

	if strings.TrimSpace(pendingTail) != "" {
		out.WriteString(strings.TrimSpace(pendingTail))
		out.WriteString("\n")
	}

	return strings.TrimSpace(out.String()) + "\n", nil
}

func runPdftohtmlXML(srcPDF, outBase string, firstPage, lastPage int) (string, error) {
	cmd := exec.Command(
		"pdftohtml",
		"-q",
		"-xml",
		"-hidden",
		"-f",
		strconv.Itoa(firstPage),
		"-l",
		strconv.Itoa(lastPage),
		srcPDF,
		outBase,
	)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("command failed: pdftohtml -xml -hidden -f %d -l %d %s %s: %w", firstPage, lastPage, srcPDF, outBase, err)
	}
	return outBase + ".xml", nil
}

// xmlDecoderWithClose wraps a decoder and its underlying file.
type xmlDecoderWithClose struct {
	decoder *xml.Decoder
	close   func() error
}

// Poppler sometimes emits control characters that are illegal in XML 1.0.
// Filter them out so the XML decoder doesn't fail.
func newXMLDecoderWithSanitizer(xmlPath string) (*xmlDecoderWithClose, error) {
	data, err := os.ReadFile(xmlPath)
	if err != nil {
		return nil, err
	}
	// Fix invalid UTF-8 sequences and illegal XML 1.0 control bytes.
	data = bytes.ToValidUTF8(data, []byte(" "))
	for i := 0; i < len(data); i++ {
		b := data[i]
		if b < 0x20 && b != '\t' && b != '\n' && b != '\r' {
			data[i] = ' '
		}
	}
	dec := xml.NewDecoder(bytes.NewReader(data))
	return &xmlDecoderWithClose{decoder: dec, close: func() error { return nil }}, nil
}

func outlineChapter1StartPage(xmlPath string) (int, error) {
	dec, err := newXMLDecoderWithSanitizer(xmlPath)
	if err != nil {
		return 0, err
	}
	defer dec.close()

	for {
		tok, err := dec.decoder.Token()
		if err != nil {
			if errors.Is(err, io.EOF) {
				return 0, nil
			}
			return 0, err
		}
		se, ok := tok.(xml.StartElement)
		if !ok || se.Name.Local != "item" {
			continue
		}
		pageAttr := ""
		for _, a := range se.Attr {
			if a.Name.Local == "page" {
				pageAttr = a.Value
				break
			}
		}
		var buf bytes.Buffer
		if err := dec.decoder.DecodeElement(&buf, &se); err != nil {
			return 0, err
		}
		text := strings.TrimSpace(buf.String())
		if !strings.HasPrefix(text, "1 ") {
			continue
		}
		p, err := strconv.Atoi(strings.TrimSpace(pageAttr))
		if err != nil {
			return 0, nil
		}
		return p, nil
	}
}

func headerFooterLines(xmlPath string) (map[string]struct{}, error) {
	dec, err := newXMLDecoderWithSanitizer(xmlPath)
	if err != nil {
		return nil, err
	}
	defer dec.close()

	counts := map[string]int{}
	pageCount := 0

	for {
		pm, ok, err := nextPage(dec.decoder)
		if err != nil {
			return nil, err
		}
		if !ok {
			break
		}
		pageCount++
		var edge []string
		for _, b := range pm.Blocks {
			if b.Kind != "t" {
				continue
			}
			if len(b.Payload) == 0 || len(b.Payload) > 90 {
				continue
			}
			if pageNumRX.MatchString(b.Payload) {
				continue
			}
			if strings.HasSuffix(b.Payload, ".") || strings.HasSuffix(b.Payload, "!") || strings.HasSuffix(b.Payload, "?") {
				continue
			}
			if b.Top < 120 || (pm.Height > 0 && b.Top > pm.Height-70) {
				edge = append(edge, b.Payload)
			}
		}
		// Count only a few per page.
		if len(edge) > 6 {
			edge = append(edge[:3], edge[len(edge)-3:]...)
		}
		for _, s := range edge {
			counts[s]++
		}
	}

	threshold := 5
	if pageCount > 0 {
		if t := int(float64(pageCount) * 0.08); t > threshold {
			threshold = t
		}
	}
	res := map[string]struct{}{}
	for s, c := range counts {
		if c >= threshold {
			res[s] = struct{}{}
		}
	}
	return res, nil
}

func nextPage(dec *xml.Decoder) (*pageModel, bool, error) {
	for {
		tok, err := dec.Token()
		if err != nil {
			if errors.Is(err, io.EOF) {
				return nil, false, nil
			}
			return nil, false, err
		}
		se, ok := tok.(xml.StartElement)
		if !ok || se.Name.Local != "page" {
			continue
		}
		pm := &pageModel{Fonts: map[string]int{}}
		for _, a := range se.Attr {
			switch a.Name.Local {
			case "number":
				pm.Number, _ = strconv.Atoi(a.Value)
			case "width":
				pm.Width, _ = strconv.Atoi(a.Value)
			case "height":
				pm.Height, _ = strconv.Atoi(a.Value)
			}
		}

		// Decode contents until </page>.
		for {
			innerTok, err := dec.Token()
			if err != nil {
				return nil, false, err
			}
			switch it := innerTok.(type) {
			case xml.StartElement:
				switch it.Name.Local {
				case "fontspec":
					var fs xmlFontSpec
					if err := dec.DecodeElement(&fs, &it); err != nil {
						return nil, false, err
					}
					sz, _ := strconv.Atoi(strings.Split(fs.Size, ".")[0])
					pm.Fonts[fs.ID] = sz
				case "image":
					var im xmlImage
					if err := dec.DecodeElement(&im, &it); err != nil {
						return nil, false, err
					}
					top := atoi(im.Top)
					left := atoi(im.Left)
					w := atoi(im.Width)
					h := atoi(im.Height)
					if w >= 120 && h >= 120 {
						pm.Blocks = append(pm.Blocks, pageBlock{Top: top, Left: left, Kind: "i", Payload: strings.TrimSpace(im.Src)})
					}
				case "text":
					var tx xmlText
					if err := dec.DecodeElement(&tx, &it); err != nil {
						return nil, false, err
					}
					top := atoi(tx.Top)
					left := atoi(tx.Left)
					fontSize := pm.Fonts[tx.Font]
					payload := normalizeXMLText(tx.Body)
					if payload != "" {
						pm.Blocks = append(pm.Blocks, pageBlock{Top: top, Left: left, Kind: "t", FontSize: fontSize, Payload: payload})
					}
				default:
					// Skip unknown elements.
					if err := dec.Skip(); err != nil {
						return nil, false, err
					}
				}
			case xml.EndElement:
				if it.Name.Local == "page" {
					sort.Slice(pm.Blocks, func(i, j int) bool {
						if pm.Blocks[i].Top != pm.Blocks[j].Top {
							return pm.Blocks[i].Top < pm.Blocks[j].Top
						}
						if pm.Blocks[i].Left != pm.Blocks[j].Left {
							return pm.Blocks[i].Left < pm.Blocks[j].Left
						}
						return pm.Blocks[i].Kind < pm.Blocks[j].Kind
					})
					return pm, true, nil
				}
			}
		}
	}
}

func normalizeXMLText(s string) string {
	// Drop tags but keep text.
	s = strings.ReplaceAll(s, "<i>", "")
	s = strings.ReplaceAll(s, "</i>", "")
	s = regexp.MustCompile(`<[^>]+>`).ReplaceAllString(s, "")
	s = strings.ReplaceAll(s, "\u00a0", " ")
	s = strings.TrimSpace(s)
	s = strings.Join(strings.Fields(s), " ")
	return s
}

func atoi(s string) int {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0
	}
	if strings.Contains(s, ".") {
		s = strings.SplitN(s, ".", 2)[0]
	}
	v, _ := strconv.Atoi(s)
	return v
}

func convertPageToMarkdown(pm *pageModel, tmpDir, mediaDir string, headerFooter map[string]struct{}) (string, error) {
	blocks := make([]pageBlock, 0, len(pm.Blocks))
	imgIdx := 0

	for _, b := range pm.Blocks {
		if b.Kind == "i" {
			srcPath := b.Payload
			if srcPath == "" {
				continue
			}
			if !filepath.IsAbs(srcPath) {
				srcPath = filepath.Join(tmpDir, srcPath)
			}
			if _, err := os.Stat(srcPath); err != nil {
				continue
			}
			imgIdx++
			destName := fmt.Sprintf("page-%03d-img-%02d%s", pm.Number, imgIdx, strings.ToLower(filepath.Ext(srcPath)))
			destPath := filepath.Join(mediaDir, destName)
			if err := copyFile(srcPath, destPath); err != nil {
				return "", err
			}
			blocks = append(blocks, pageBlock{Top: b.Top, Left: b.Left, Kind: "i", Payload: destName})
			continue
		}

		line := strings.TrimSpace(b.Payload)
		if line == "" {
			continue
		}
		if _, ok := headerFooter[line]; ok {
			continue
		}
		// Drop running headers.
		if b.Top < 60 && b.FontSize <= 22 {
			if regexp.MustCompile(`^Chapter\s+\d+\s*$`).MatchString(line) {
				continue
			}
			if textIsProbablyHeading(line) && !sectionHeading.MatchString(line) {
				continue
			}
		}
		// Drop page numbers.
		if pageNumRX.MatchString(line) && b.FontSize <= 18 {
			if b.Top < 120 || (pm.Height > 0 && b.Top > pm.Height-70) || b.Left < 80 || (pm.Width > 0 && b.Left > pm.Width-120) {
				continue
			}
		}
		blocks = append(blocks, pageBlock{Top: b.Top, Left: b.Left, Kind: "t", FontSize: b.FontSize, Payload: line})
	}

	if len(blocks) == 0 {
		return "", nil
	}

	// Collapse chapter title pages: "1" + title lines.
	blocks = collapseTitlePage(blocks)

	var out []string
	para := ""
	var prevTop *int
	var prevLeft *int
	var prevFont *int

	pendingImage := ""
	pendingCaption := []string{}
	captionMode := false
	var lastCaptionTop *int
	var lastCaptionFont *int

	flushFigure := func() {
		if pendingImage == "" {
			captionMode = false
			pendingCaption = nil
			lastCaptionTop = nil
			lastCaptionFont = nil
			return
		}
		out = append(out, pendingImage, "")
		if len(pendingCaption) > 0 {
			cap := strings.Join(pendingCaption, " ")
			cap = strings.Join(strings.Fields(cap), " ")
			out = append(out, cap, "")
		}
		pendingImage = ""
		pendingCaption = nil
		captionMode = false
		lastCaptionTop = nil
		lastCaptionFont = nil
	}

	flushPara := func() {
		if strings.TrimSpace(para) != "" {
			out = append(out, strings.TrimSpace(para), "")
		}
		para = ""
		flushFigure()
	}

	isCaptionLine := func(s string, top int, fsz int) bool {
		if s == "" {
			return false
		}
		if sectionHeading.MatchString(s) || strings.HasPrefix(s, "#") {
			return false
		}
		if captionStartRX.MatchString(s) {
			return true
		}
		if regexp.MustCompile(`^(Key|KEY)\s*:\s*`).MatchString(s) {
			return true
		}
		if captionMode && len(pendingCaption) > 0 {
			if len(s) > 90 {
				return false
			}
			if lastCaptionTop != nil && top-*lastCaptionTop > 45 {
				return false
			}
			if lastCaptionFont != nil && abs(fsz-*lastCaptionFont) > 3 {
				return false
			}
			return true
		}
		return captionMode && len(s) <= 70
	}

	for _, b := range blocks {
		if b.Kind == "i" {
			flushFigure()
			pendingImage = "![](media/" + b.Payload + ")"
			pendingCaption = []string{}
			captionMode = true
			prevTop, prevLeft, prevFont = nil, nil, nil
			continue
		}

		line := b.Payload
		if pendingImage != "" && isCaptionLine(line, b.Top, b.FontSize) {
			pendingCaption = append(pendingCaption, line)
			ct, cf := b.Top, b.FontSize
			lastCaptionTop = &ct
			lastCaptionFont = &cf
			continue
		}
		if pendingImage != "" && strings.TrimSpace(para) == "" && captionMode {
			flushFigure()
		}

		if m := sectionHeading.FindStringSubmatch(line); len(m) == 3 {
			flushPara()
			depth := strings.Count(m[1], ".") + 1
			level := 2 + min(3, depth)
			out = append(out, strings.Repeat("#", level)+" "+line, "")
			prevTop, prevLeft, prevFont = nil, nil, nil
			continue
		}

		if b.FontSize >= 28 && textIsProbablyHeading(line) {
			flushPara()
			out = append(out, "## "+line, "")
			prevTop, prevLeft, prevFont = nil, nil, nil
			continue
		}

		// Paragraph breaks based on vertical gap and indent changes.
		joinGap := 0
		if prevTop != nil && prevFont != nil {
			gap := b.Top - *prevTop
			joinGap = max(14, int(float64(*prevFont)*1.15))
			splitGap := max(22, int(float64(*prevFont)*1.8))
			if pendingImage == "" {
				if gap > splitGap {
					if sentenceEndRX.MatchString(strings.TrimSpace(para)) {
						flushPara()
					} else if gap > int(float64(splitGap)*2.5) {
						flushPara()
					}
				}
				if prevLeft != nil && abs(b.Left-*prevLeft) > 80 && gap > joinGap {
					flushPara()
				}
			}
		}

		if para == "" {
			para = line
		} else {
			shouldJoin := isProbablyWrapped(para, line)
			if joinGap > 0 && prevTop != nil && (b.Top-*prevTop) <= joinGap {
				shouldJoin = true
			}
			if strings.HasSuffix(para, "-") && len(line) > 0 && unicode.IsLower([]rune(line)[0]) {
				para = strings.TrimSuffix(para, "-") + line
			} else if shouldJoin {
				para = para + " " + line
			} else {
				flushPara()
				para = line
			}
		}

		t, l, f := b.Top, b.Left, b.FontSize
		prevTop, prevLeft, prevFont = &t, &l, &f
	}

	flushPara()
	flushFigure()

	res := strings.Join(out, "\n")
	res = regexp.MustCompile(`\n{3,}`).ReplaceAllString(res, "\n\n")
	return strings.TrimSpace(res) + "\n", nil
}

func collapseTitlePage(blocks []pageBlock) []pageBlock {
	if len(blocks) < 3 {
		return blocks
	}
	chapNum := ""
	var parts []string
	consumed := 0
	for i := 0; i < len(blocks) && i < 8; i++ {
		b := blocks[i]
		if b.Kind != "t" || b.Top > 260 || b.FontSize < 28 {
			break
		}
		if chapNum == "" && regexp.MustCompile(`^\d+$`).MatchString(b.Payload) {
			chapNum = b.Payload
		} else {
			parts = append(parts, b.Payload)
		}
		consumed++
	}
	if chapNum == "" || len(parts) == 0 {
		return blocks
	}
	title := strings.TrimSpace(strings.Join(parts, " "))
	title = strings.Join(strings.Fields(title), " ")
	out := make([]pageBlock, 0, len(blocks)-consumed+1)
	out = append(out, pageBlock{Top: 0, Left: 0, Kind: "t", FontSize: 28, Payload: fmt.Sprintf("## Chapter %s: %s", chapNum, title)})
	out = append(out, blocks[consumed:]...)
	return out
}

func mdBlocks(md string) []string {
	var blocks []string
	var cur []string
	for _, ln := range strings.Split(md, "\n") {
		if strings.TrimSpace(ln) == "" {
			if len(cur) > 0 {
				blocks = append(blocks, strings.TrimSpace(strings.Join(cur, "\n")))
				cur = nil
			}
			continue
		}
		cur = append(cur, ln)
	}
	if len(cur) > 0 {
		blocks = append(blocks, strings.TrimSpace(strings.Join(cur, "\n")))
	}
	var out []string
	for _, b := range blocks {
		if strings.TrimSpace(b) != "" {
			out = append(out, b)
		}
	}
	return out
}

func isPlainParagraph(block string) bool {
	s := strings.TrimSpace(block)
	if s == "" {
		return false
	}
	if strings.HasPrefix(s, "#") {
		return false
	}
	if strings.HasPrefix(s, "![](media/") {
		return false
	}
	if strings.Contains(s, "\n") {
		return false
	}
	return true
}

func isImageBlock(block string) bool {
	return strings.HasPrefix(strings.TrimSpace(block), "![](media/")
}

func isCaptionBlock(block string) bool {
	s := strings.TrimSpace(block)
	if s == "" {
		return false
	}
	first := s
	if strings.Contains(first, "\n") {
		first = strings.SplitN(first, "\n", 2)[0]
	}
	first = strings.TrimSpace(first)
	if captionStartRX.MatchString(first) {
		return true
	}
	if regexp.MustCompile(`^(Key|KEY):\b`).MatchString(first) {
		return true
	}
	return false
}

func isCaptionContinuationBlock(block string) bool {
	s := strings.TrimSpace(block)
	if s == "" || strings.HasPrefix(s, "#") || strings.HasPrefix(s, "![](") || strings.Contains(s, "\n") {
		return false
	}
	if len(s) > 80 {
		return false
	}
	if sentenceEndRX.MatchString(s) {
		return false
	}
	if regexp.MustCompile(`^\d+(?:\.\d+)*\b`).MatchString(s) {
		return false
	}
	return true
}

func shouldJoinAcrossPages(tail, head string) bool {
	tail = strings.TrimSpace(tail)
	head = strings.TrimSpace(head)
	if tail == "" || head == "" {
		return false
	}
	if sentenceEndRX.MatchString(tail) {
		return false
	}
	if len(head) > 0 {
		r := []rune(head)[0]
		if unicode.IsLower(r) {
			return true
		}
	}
	if continuationRX.MatchString(head) {
		return true
	}
	if strings.HasSuffix(tail, ",") || strings.HasSuffix(tail, ";") || strings.HasSuffix(tail, ":") {
		return true
	}
	return false
}

func joinAcrossPages(pendingTail string, blocks []string) []string {
	if strings.TrimSpace(pendingTail) == "" {
		return blocks
	}
	joinIdx := -1
	for i, b := range blocks {
		if isPlainParagraph(b) && !isCaptionBlock(b) && !isCaptionContinuationBlock(b) {
			joinIdx = i
			break
		}
	}
	if joinIdx == -1 {
		return append([]string{strings.TrimSpace(pendingTail)}, blocks...)
	}
	if !shouldJoinAcrossPages(pendingTail, blocks[joinIdx]) {
		return append([]string{strings.TrimSpace(pendingTail)}, blocks...)
	}

	// Only reorder if the blocks before joinIdx are image/caption blocks.
	okLead := true
	captionSeen := false
	for _, b := range blocks[:joinIdx] {
		if isImageBlock(b) {
			continue
		}
		if isCaptionBlock(b) {
			captionSeen = true
			continue
		}
		if captionSeen && isCaptionContinuationBlock(b) {
			continue
		}
		okLead = false
		break
	}

	head := blocks[joinIdx]
	joined := ""
	if strings.HasSuffix(strings.TrimRightFunc(pendingTail, unicode.IsSpace), "-") && len(head) > 0 && unicode.IsLower([]rune(strings.TrimSpace(head))[0]) {
		joined = strings.TrimSuffix(strings.TrimRightFunc(pendingTail, unicode.IsSpace), "-") + strings.TrimLeftFunc(head, unicode.IsSpace)
	} else {
		joined = strings.TrimRightFunc(pendingTail, unicode.IsSpace) + " " + strings.TrimLeftFunc(head, unicode.IsSpace)
	}
	blocks[joinIdx] = joined

	if joinIdx > 0 && okLead {
		lead := append([]string{}, blocks[:joinIdx]...)
		blocks = append([]string{blocks[joinIdx]}, append(lead, blocks[joinIdx+1:]...)...)
	}
	return blocks
}

func textIsProbablyHeading(line string) bool {
	s := strings.TrimSpace(line)
	if s == "" || len(s) > 80 {
		return false
	}
	if strings.HasSuffix(s, ".") || strings.HasSuffix(s, "!") || strings.HasSuffix(s, "?") {
		return false
	}
	words := strings.Fields(s)
	if len(words) < 2 {
		return false
	}
	stop := map[string]struct{}{"and": {}, "the": {}, "of": {}, "to": {}, "in": {}, "a": {}, "an": {}, "for": {}, "on": {}, "with": {}}
	var scored []string
	for _, w := range words {
		if _, ok := stop[strings.ToLower(w)]; !ok {
			scored = append(scored, w)
		}
	}
	if len(scored) < 2 {
		scored = words
	}
	titled := 0
	for _, w := range scored {
		r := []rune(w)
		if len(r) > 0 && unicode.IsUpper(r[0]) {
			titled++
		}
	}
	return float64(titled)/float64(len(scored)) >= 0.7
}

func isProbablyWrapped(prev, next string) bool {
	if prev == "" || next == "" {
		return false
	}
	if strings.HasSuffix(prev, "-") {
		r := []rune(next)
		if len(r) > 0 && unicode.IsLower(r[0]) {
			return true
		}
	}
	if regexp.MustCompile(`^(?:[•\-*]|\d+\.)\s+`).MatchString(next) {
		return false
	}
	if sentenceEndRX.MatchString(prev) {
		return false
	}
	return true
}

func copyFile(src, dest string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer func() {
		_ = out.Close()
	}()
	if _, err := io.Copy(out, in); err != nil {
		return err
	}
	return out.Close()
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

func extractText(src string) (string, error) {
	tmp, err := os.CreateTemp("", "pdf-to-markdown-*.txt")
	if err != nil {
		return "", err
	}
	tmpPath := tmp.Name()
	if err := tmp.Close(); err != nil {
		return "", err
	}
	defer os.Remove(tmpPath)

	cmd := exec.Command("pdftotext", "-layout", "-enc", "UTF-8", src, tmpPath)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("command failed: pdftotext -layout -enc UTF-8 %s %s: %w", src, tmpPath, err)
	}

	data, err := os.ReadFile(tmpPath)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

type blockKind int

const (
	kindNone blockKind = iota
	kindParagraph
	kindHeading
	kindList
)

func convertToMarkdown(text string) string {
	text = strings.ReplaceAll(text, "\r\n", "\n")
	text = strings.ReplaceAll(text, "\r", "\n")
	text = strings.ReplaceAll(text, "\u00a0", " ")

	lines := strings.Split(text, "\n")
	out := make([]string, 0, len(lines))
	currentParagraph := ""
	lastKind := kindNone
	hasContent := false
	prevNonEmptyEndsSentence := true
	flushParagraph := func() {
		if strings.TrimSpace(currentParagraph) == "" {
			currentParagraph = ""
			return
		}
		appendBlock(&out, &lastKind, kindParagraph, currentParagraph)
		hasContent = true
		currentParagraph = ""
	}

	for i, rawLine := range lines {
		line := strings.TrimRightFunc(rawLine, unicode.IsSpace)
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			flushParagraph()
			continue
		}
		if isPageNumber(trimmed) || isNoiseLine(trimmed) {
			continue
		}
		if bullet, ok := normalizeBullet(trimmed); ok {
			flushParagraph()
			appendBlock(&out, &lastKind, kindList, bullet)
			hasContent = true
			prevNonEmptyEndsSentence = endsSentence(trimmed)
			continue
		}
		ctx := headingContext{
			prevBlank:                isBlankLine(lines, i-1),
			nextBlank:                isBlankLine(lines, i+1),
			prevNonEmptyEndsSentence: prevNonEmptyEndsSentence,
			hasContent:               hasContent,
		}
		if heading, ok := normalizeHeading(trimmed, ctx); ok {
			flushParagraph()
			appendBlock(&out, &lastKind, kindHeading, heading)
			hasContent = true
			prevNonEmptyEndsSentence = endsSentence(trimmed)
			continue
		}
		currentParagraph = appendParagraphLine(currentParagraph, trimmed)
		prevNonEmptyEndsSentence = endsSentence(trimmed)
	}
	flushParagraph()

	cleaned := strings.Join(out, "\n")
	cleaned = regexp.MustCompile(`\n{3,}`).ReplaceAllString(cleaned, "\n\n")
	return strings.TrimSpace(cleaned) + "\n"
}

func appendBlock(out *[]string, lastKind *blockKind, kind blockKind, line string) {
	if line == "" {
		return
	}
	if len(*out) > 0 && (*lastKind != kindNone && *lastKind != kindList && kind != kindList) {
		if (*out)[len(*out)-1] != "" {
			*out = append(*out, "")
		}
	}
	if len(*out) > 0 && kind == kindList && *lastKind != kindList && (*out)[len(*out)-1] != "" {
		*out = append(*out, "")
	}
	*out = append(*out, line)
	*lastKind = kind
}

func appendParagraphLine(current, next string) string {
	if current == "" {
		return next
	}
	if strings.HasSuffix(current, "-") && len(next) > 0 && unicode.IsLower(rune(next[0])) {
		return strings.TrimSuffix(current, "-") + next
	}
	return current + " " + next
}

func isPageNumber(line string) bool {
	if len(line) > 8 {
		return false
	}
	return regexp.MustCompile(`^(?:\d+|[ivxlcdmIVXLCDM]+)$`).MatchString(line)
}

func isNoiseLine(line string) bool {
	if len(line) > 60 {
		return false
	}
	if regexp.MustCompile(`^Page\s+\d+(?:\s+of\s+\d+)?$`).MatchString(line) {
		return true
	}
	if hasSpacedLetterNoise(line) {
		return true
	}
	return false
}

type headingContext struct {
	prevBlank                bool
	nextBlank                bool
	prevNonEmptyEndsSentence bool
	hasContent               bool
}

func normalizeHeading(line string, ctx headingContext) (string, bool) {
	line = stripTOCPageNumber(line)
	if line == "" {
		return "", false
	}
	if strings.HasPrefix(line, "-") {
		return "", false
	}
	upper := strings.ToUpper(line)
	switch {
	case strings.HasPrefix(upper, "PART "):
		return formatChapterHeading("#", line), true
	case strings.HasPrefix(upper, "CHAPTER "):
		return formatChapterHeading("##", line), true
	case strings.HasPrefix(upper, "APPENDIX "):
		return formatChapterHeading("##", line), true
	case strings.HasPrefix(upper, "SECTION "):
		return formatChapterHeading("###", line), true
	case isExactHeading(upper, "FOREWORD", "PREFACE", "INTRODUCTION", "CONCLUSION"):
		return "## " + titleCase(line), true
	}
	if heading, ok := normalizeNumericHeading(line); ok {
		return heading, true
	}
	if isFrontMatterHeading(line) {
		return "## " + titleCase(line), true
	}
	if ctx.prevBlank && ctx.nextBlank && (isUpperHeading(line) || (ctx.prevNonEmptyEndsSentence && isTitleHeading(line))) {
		prefix := "###"
		if !ctx.hasContent && isUpperHeading(line) {
			prefix = "#"
		}
		return prefix + " " + titleCase(line), true
	}
	return "", false
}

func formatChapterHeading(prefix, line string) string {
	re := regexp.MustCompile(`(?i)^(chapter|part|appendix)\s+([ivxlcdm0-9]+)[:.\-\s]*(.*)$`)
	match := re.FindStringSubmatch(line)
	if len(match) == 4 {
		label := strings.Title(strings.ToLower(match[1]))
		number := strings.ToUpper(strings.TrimSpace(match[2]))
		title := strings.TrimSpace(match[3])
		if title != "" {
			return fmt.Sprintf("%s %s %s: %s", prefix, label, number, title)
		}
		return fmt.Sprintf("%s %s %s", prefix, label, number)
	}
	return prefix + " " + titleCase(line)
}

func titleCase(line string) string {
	parts := strings.Fields(line)
	for i, part := range parts {
		if len(part) == 0 {
			continue
		}
		runes := []rune(strings.ToLower(part))
		runes[0] = unicode.ToUpper(runes[0])
		parts[i] = string(runes)
	}
	return strings.Join(parts, " ")
}

func isUpperHeading(line string) bool {
	if len(line) > 80 || len(strings.Fields(line)) > 10 {
		return false
	}
	if strings.Contains(line, ".") || strings.Contains(line, "!") || strings.Contains(line, "?") {
		return false
	}
	letters := 0
	uppercase := 0
	for _, r := range line {
		if unicode.IsLetter(r) {
			letters++
			if unicode.IsUpper(r) {
				uppercase++
			}
		}
	}
	if letters == 0 {
		return false
	}
	return uppercase >= letters*3/4
}

func isTitleHeading(line string) bool {
	if len(line) > 72 || len(strings.Fields(line)) > 8 {
		return false
	}
	if strings.HasSuffix(line, ".") || strings.HasSuffix(line, ":") || strings.HasSuffix(line, ";") || strings.HasSuffix(line, "!") || strings.HasSuffix(line, "?") {
		return false
	}
	if strings.Contains(line, "http://") || strings.Contains(line, "https://") {
		return false
	}
	words := strings.Fields(line)
	titleWords := 0
	for _, word := range words {
		clean := strings.Trim(word, `"'()[]{}<>.,!?`)
		if clean == "" {
			continue
		}
		runes := []rune(clean)
		if len(runes) == 0 {
			continue
		}
		first := runes[0]
		if unicode.IsUpper(first) {
			titleWords++
			continue
		}
		if isSmallWord(clean) {
			titleWords++
			continue
		}
	}
	return titleWords >= len(words)*3/4
}

func isSmallWord(word string) bool {
	switch strings.ToLower(word) {
	case "a", "an", "and", "as", "at", "by", "for", "in", "of", "on", "or", "the", "to", "up", "via", "with", "from":
		return true
	default:
		return false
	}
}

func endsSentence(line string) bool {
	return strings.HasSuffix(line, ".") || strings.HasSuffix(line, "!") || strings.HasSuffix(line, "?") || strings.HasSuffix(line, ":") || strings.HasSuffix(line, ";")
}

func isBlankLine(lines []string, idx int) bool {
	if idx < 0 || idx >= len(lines) {
		return true
	}
	return strings.TrimSpace(lines[idx]) == ""
}

func stripTOCPageNumber(line string) string {
	trimmed := regexp.MustCompile(`\s+(?:Page\s+)?(?:[ivxlcdmIVXLCDM]+|\d+)\s*$`).ReplaceAllString(line, "")
	trimmed = strings.TrimSpace(trimmed)
	if strings.Count(trimmed, " ") == 0 && strings.EqualFold(trimmed, line) {
		return line
	}
	if strings.HasPrefix(strings.ToUpper(trimmed), "CHAPTER ") || strings.HasPrefix(strings.ToUpper(trimmed), "PART ") || strings.HasPrefix(strings.ToUpper(trimmed), "APPENDIX ") || isFrontMatterHeading(trimmed) {
		return trimmed
	}
	return line
}

func normalizeNumericHeading(line string) (string, bool) {
	if match := regexp.MustCompile(`^(\d+)[\t ]+([A-Z][A-Z\s-]+)$`).FindStringSubmatch(line); len(match) == 3 {
		return fmt.Sprintf("## Chapter %s: %s", match[1], titleCase(match[2])), true
	}
	if match := regexp.MustCompile(`^(\d+[.)])\s+(.+)$`).FindStringSubmatch(line); len(match) == 3 && isTitleHeading(match[2]) {
		return fmt.Sprintf("### %s %s", match[1], titleCase(match[2])), true
	}
	return "", false
}

func isFrontMatterHeading(line string) bool {
	switch strings.ToLower(strings.TrimSpace(line)) {
	case "about the authors", "about renaissance periodization", "table of contents", "foreword", "preface", "introduction", "conclusion", "sources and further reading", "worksheet templates for volume landmark tracking":
		return true
	default:
		return false
	}
}

func hasSpacedLetterNoise(line string) bool {
	words := strings.Fields(line)
	if len(words) < 6 {
		return false
	}
	singleLetters := 0
	for _, word := range words {
		runes := []rune(word)
		if len(runes) == 1 && unicode.IsLetter(runes[0]) {
			singleLetters++
		}
	}
	return singleLetters >= len(words)*2/3
}

func normalizeBullet(line string) (string, bool) {
	if regexp.MustCompile(`^(?:[-*•]\s*|\d+[.)]\s+)`).MatchString(line) {
		line = regexp.MustCompile(`^(?:[-*•]\s*|\d+[.)]\s+)`).ReplaceAllString(line, "- ")
		return line, true
	}
	return "", false
}

func isExactHeading(line string, values ...string) bool {
	for _, value := range values {
		if line == value {
			return true
		}
	}
	return false
}

func trimToMarker(text, marker string) (string, error) {
	idx := strings.Index(text, marker)
	if idx == -1 {
		return "", fmt.Errorf("missing start marker: %s", marker)
	}
	return text[idx:], nil
}

func verifyOutput(text string) error {
	if strings.TrimSpace(text) == "" {
		return errors.New("verification failed: output is empty")
	}
	if strings.ContainsRune(text, '\f') {
		return errors.New("verification failed: found form feed characters")
	}
	return nil
}
