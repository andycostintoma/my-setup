---
name: epub-to-markdown
description: "Activate when converting EPUB books into readable Markdown notes with local media folders instead of keeping a raw pandoc dump."
license: MIT
---

# EPUB To Markdown

Use this skill when the user wants one or more EPUB files converted into readable Markdown notes.

## Goal

Produce note-style Markdown that preserves the book content while stripping EPUB/container bloat.

Expected output per book:
- one destination folder per book
- one `.md` file inside that folder
- one adjacent `media/` folder
- readable Markdown, not raw pandoc archive output

## Workflow

1. Inspect the target repo for the local note structure you should match.
2. Decide the destination folder and markdown filename.
3. Run the bundled cleanup script at `scripts/epub_to_markdown.rb` from this skill directory:

```bash
ruby "/Users/andytoma/.config/nix-darwin/harness/claude/skills/epub-to-markdown/scripts/epub_to_markdown.rb" \
  --src "/absolute/path/to/book.epub" \
  --dest-dir "/absolute/path/to/output/book-folder" \
  --output-name "Book_Name.md" \
  --start-marker "# Real content start" \
  --unwrap-blockquotes
```

4. Read the generated markdown and compare it against the local note style.
5. If needed, make small deterministic improvements in the shared script rather than hand-editing one generated book.
6. For technical books, apply the post-processing rules below.
7. Verify the result before you stop.

## Post-Processing For Technical Books

Technical EPUBs often encode formulas, operators, short code fragments, and
symbols as tiny images. These make Markdown notes hard to read and should be
converted when the meaning is clear.

- Replace small inline formula images with Markdown math, for example
  `$x + y$`, `$x \cdot y$`, `$\bar{x}$`, `$2^n - 1$`, or `$\sqrt{x}$`.
- Replace small inline code images with inline code or fenced code blocks,
  depending on size: `` `D=M` ``, `` `RAM[SP++] = D` ``, or a language-tagged
  code fence.
- Preserve real diagrams, screenshots, figures, tables, and visual layouts as
  images. Do not convert these just because they contain text.
- If an inline image is ambiguous, inspect it directly or use OCR as an aid,
  then manually review the replacement in context. Do not blindly OCR-replace
  formulas or code.
- After replacing inline formula/code images, remove media files that are no
  longer referenced.
- Prefer a single book-local `media/` folder. If conversion produces nested
  paths like `media/images/`, flatten them when it matches the surrounding note
  style and update all image links.
- Add a linked `## Table of Contents` at the start of long books. Include the
  heading levels that are useful for navigation, generate internal Markdown
  anchors, and handle duplicate headings with the renderer's suffix convention
  such as `#introduction-1`.
- Add internal links when prose refers to chapters, appendices, parts, or clear
  contextual references such as "the next chapter" and "the previous chapter".
  Skip headings, code blocks, existing links, and inline code when adding these
  links.
- If a separate summary file is created, preserve the source section headings,
  code blocks, and images exactly, while summarizing only the prose.

## Options

- `--start-marker TEXT`
  Use when the EPUB front matter should be trimmed so the note starts at the first real part/chapter/intro section.

- `--unwrap-blockquotes`
  Use when the source EPUB incorrectly turns normal body content into top-level blockquotes and those should be flattened.

## Verification Checklist

Always verify that the generated note:
- keeps the actual book content, not a summary
- stores images under the book-local `media/` folder
- has no `.html` or `.xhtml` fragment links left over
- has no raw calibre/span/div/nav junk left over
- does not render figures as headings
- has a table of contents whose links all resolve, when a TOC is added
- has internal chapter, appendix, and part links that target existing headings
- has no broken image links and no non-local image paths
- has no unused media files after replacing formula/code images
- matches the surrounding repo's note style as closely as practical

## Editing Rules

- Prefer fixing repeated conversion problems in `scripts/epub_to_markdown.rb`.
- Do not leave scratch conversion scripts in the target repo when this shared skill can own the logic.
- Do not aggressively strip content just to make the file cleaner; preserve body text, headings, images, captions, lists, and callouts unless they are clear EPUB packaging noise.

## When To Ask

Ask one short question if any of these are unclear:
- which EPUB files to convert
- where the converted notes should live
- what existing local note style should be matched
- what marker should define the start of real content if the EPUB has heavy front matter
