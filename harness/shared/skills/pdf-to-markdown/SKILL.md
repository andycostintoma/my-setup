---
name: pdf-to-markdown
description: "Use when converting PDF books with a real text layer into readable Markdown notes. Extracts figures into media/ (no OCR fallback)."
license: MIT
---

# PDF To Markdown

Use this skill when the user wants one or more PDF files converted into Markdown notes and the PDFs have a usable text layer.

## Goal

Produce note-style Markdown from text PDFs without OCR, including embedded figures.

Expected output per book:
- one destination folder per book
- one `.md` file inside that folder
- one `media/` folder for extracted figures
- readable Markdown, not a raw text dump

## Workflow

1. Inspect the target repo for the local note structure you should match.
2. Decide the destination folder and markdown filename.
3. Run the local Go cleanup command:

```bash
pdf-to-markdown \
  --src "/absolute/path/to/book.pdf" \
  --dest-dir "/absolute/path/to/output/book-folder" \
  --output-name "Book_Name.md" \
  --start-at-chapter-1
```

4. Read the generated markdown and compare it against the local note style.
5. If needed, make small deterministic improvements in the local script rather than hand-editing one generated book.
6. Verify the result before you stop.

## Conversion Rules

- Default backend is `pdftohtml -xml` to keep layout and extract images.
- Images are written under `media/` and referenced as `![](media/...)`.
- Optional: `--backend pdftotext` for text-only extraction.
- Support only PDFs with an actual text layer.
- Do not add OCR fallback.
- Preserve chapter headings, paragraphs, bullet lists, and simple structural breaks.
- Trim obvious front matter with `--start-marker` when needed.
- Skip scanned PDFs or image-only pages unless the user explicitly changes the scope.

## Verification Checklist

Always verify that the generated note:
- keeps the actual book content, not a summary
- has no raw page-number noise or form-feed artifacts left over
- has no broken layout from line wrapping
- matches the surrounding repo's note style as closely as practical

## Editing Rules

- Prefer fixing repeated conversion problems in `tools/pdf-to-markdown/main.go`.
- Do not leave scratch conversion scripts in the target repo when this local skill can own the logic.
- Do not aggressively strip content just to make the file cleaner; preserve body text and real headings unless they are clear PDF layout noise.

## When To Ask

Ask one short question if any of these are unclear:
- which PDF files to convert
- where the converted notes should live
- what existing local note style should be matched
- what marker should define the start of real content if the PDF has heavy front matter
