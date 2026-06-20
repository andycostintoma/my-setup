---
name: pdf-to-markdown
description: "Use when converting text-layer PDF books to Markdown, or auditing an existing Markdown book section against the original PDF with pdf-to-markdown --audit-md."
license: MIT
---

# PDF To Markdown

Use this skill when the user wants one or more PDF files converted into Markdown notes, or when an existing Markdown book needs to be checked section by section against the original PDF.

## Goal

Produce note-style Markdown from text PDFs without OCR, including embedded figures.

Expected output per book:
- one destination folder per book
- one `.md` file inside that folder
- one `media/` folder for extracted figures
- readable Markdown, not a raw text dump

For existing converted books, produce a PDF-backed repair workflow:
- compare the Markdown section against the PDF section
- identify heading, caption, image, and layout drift
- patch only the broken Markdown
- rerun the audit until warnings are understood

## Conversion Workflow

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

## Section Audit Workflow

Use audit mode when the Markdown already exists and the task is to make it match the PDF section by section.

Run:

```bash
pdf-to-markdown \
  --src "/absolute/path/to/book.pdf" \
  --audit-md "/absolute/path/to/book.md" \
  --section 1.2
```

The tool infers the PDF page range from the section heading and reports:
- inferred PDF pages
- Markdown line range for the section
- PDF headings found in the section range
- Markdown headings found in the section
- PDF captions found from layout XML
- Markdown captions and image links
- image-count mismatches
- suspicious Markdown lines such as broken hyphenation, missing punctuation spaces, comma spacing artifacts, and overlong captions

If automatic page inference is wrong, override it:

```bash
pdf-to-markdown \
  --src "/absolute/path/to/book.pdf" \
  --audit-md "/absolute/path/to/book.md" \
  --section 1.3 \
  --pdf-first-page 43 \
  --pdf-last-page 55
```

Recommended repair loop:

1. Run audit for the requested section.
2. Read the flagged Markdown lines and the nearby Markdown context.
3. Use the PDF page range in the report as the source of truth.
4. Patch only confirmed formatting drift: broken headings, caption/body joins, missing image/caption separation, line-wrap hyphenation, bad spacing, or split equations.
5. Rerun the audit for the same section.
6. Treat remaining warnings as leads, not automatic failures.

Known audit limitations:
- PDF captions may appear as partial IDs such as `Figure 1.6`; matching by figure/table number is intentional.
- Body prose beginning with “Figure 1.x shows…” is usually not a caption and should not be patched unless it is actually broken.
- Image counts can be noisy near section boundaries when the inferred PDF end page excludes a figure that still belongs to the Markdown section.
- Long legitimate captions may be reported as suspicious; inspect before editing.

## Conversion Rules

- Default backend is `pdftohtml -xml` to keep layout and extract images.
- Audit mode also uses `pdftohtml -xml` so headings, captions, coordinates, and image blocks are visible to the checker.
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

When auditing existing Markdown, verify that the section:
- has the same real headings as the PDF section
- preserves every figure and caption in the section
- does not join figure captions into body prose
- does not split body prose around images in a way that changes meaning
- has no obvious PDF line-wrap artifacts left in repaired lines

## Editing Rules

- Prefer fixing repeated conversion problems in `personal-mac/tools/pdf-to-markdown/main.go`.
- For one-off book cleanup, prefer the audit report plus small `apply_patch` edits over reconverting the whole book.
- Do not leave scratch conversion scripts in the target repo when this local skill can own the logic.
- Do not aggressively strip content just to make the file cleaner; preserve body text and real headings unless they are clear PDF layout noise.

## When To Ask

Ask one short question if any of these are unclear:
- which PDF files to convert
- where the converted notes should live
- what existing local note style should be matched
- what marker should define the start of real content if the PDF has heavy front matter
