---
name: study-notes
description: "Activate when writing or extending structured study notes from a mix of sources: a primary text/book (source of truth for headings and structure), lecture slides (for high-value diagrams and figures only), and video course transcripts (for teaching emphasis and worked examples). Covers source synthesis, figure selection, style discipline, and the subsection-by-subsection workflow. Use whenever the session repo has an AGENTS.md with a `## Current Progress` section referencing NOTES.md."
license: MIT
compatibility: opencode,claude,antigravity
---

# Study Notes Skill

You are maintaining structured study notes from multi-source learning material.
The human curates the sources and reviews quality. You do the synthesis, figure
selection, and mechanical work — one subsection at a time.

## Detecting an active study-notes repo

Apply this skill when the working directory has an `AGENTS.md` that contains a
`## Current Progress` section referencing a `NOTES.md`. The `AGENTS.md` is
always the local source of truth for repo-specific rules; always read it first.

## Source hierarchy

Every subsection is synthesized from up to three sources:

| Priority | Source | Role |
|---|---|---|
| 1 (authoritative) | Book / primary text | Structural source of truth: headings, figures, code blocks, mathematical notation |
| 2 (reinforcing) | Lecture slides PDF | High-value diagrams and figures only — never navigation/outline slides |
| 3 (clarifying) | Video course transcript | Teaching emphasis, worked examples, verbal mental models |

The book drives structure. Slides and transcripts enrich it. Never reorganize or
rename headings to match slides or transcript phrasing.

## Before starting any subsection

1. Read the workspace `AGENTS.md` for current progress marker and repo-specific style rules.
2. Find the exact subsection boundaries in `NOTES.md` (match the book's heading hierarchy exactly).
3. Read the corresponding book section in the primary text.
4. Locate the relevant slide range in the lecture PDF (use a text extraction pass if needed to identify page numbers before rendering images).
5. Read the relevant transcript segment.
6. Only then synthesize — do not write while still gathering sources.

## Writing style

Follow the teaching-oriented style established in the existing notes:

- Start with the concrete implementation picture: what components/state exist, what to imagine physically.
- Define notation early; disambiguate symbols that have multiple meanings in context.
- For any code/HDL/assembly snippet, follow it immediately with a `Meaning:` block that is line-by-line and states what changes.
- For figures and program examples, explain by blocks (init, loop condition, body, increment/jump, termination) with short pseudocode as a roadmap before diving into snippets.
- Use tiny traces (one or two iterations, a few key state values) to make pointer-like or stateful behavior concrete.
- Short paragraphs, explicit examples, small code/text blocks. Not dense academic prose.
- Construction ladders (e.g. `DFF → Bit → Register → RAM`) when a section builds layered abstractions.

## Figure selection (slides)

This is the most judgment-sensitive step. Only extract and embed a slide figure
when ALL of the following are true:

- [ ] You have actually viewed the image (not inferred its content from the PDF text extraction)
- [ ] It contains a diagram, truth table, circuit schematic, code listing, or other visual that conveys information the prose cannot replicate well
- [ ] It is not a navigation/outline slide (chapter menu, section divider, agenda, "Theory / Practice / Project" layout; e.g., Slide 36 in Lecture 1)
- [ ] It is not a purely motivational/decorative slide (portraits, analogies without diagrams)
- [ ] It genuinely adds something the book's own figures do not already show

If uncertain, default to **no figure** — prose is preferable to a distracting or
redundant image.

### Handling User Feedback on Figures
- **Do not overreact to negative feedback:** If the user points out that a specific slide figure adds no value (e.g. "slide 36 adds nothing"), do NOT completely wipe out all slide figures from the notes.
- **Review and refine:** Remove only the specific low-value or redundant slides identified, and make sure to look for and keep the high-value diagrams (e.g., interface/implementation splits, simulator GUI callouts, test/compare script flows) that actually complement the learning notes.

### Figure extraction workflow

```bash
# 1. Extract slide text to identify candidate page numbers
pdftoppm -png -r 72 -f 1 -l <N> slides/<name>.pdf /tmp/preview/s
# (low-res pass for visual scan)

# 2. Extract selected slides at full quality
pdftoppm -png -r 150 -f <page> -l <page> slides/<name>.pdf /tmp/s-<n>

# 3. Copy to the media directory
cp /tmp/s-<n>-0<page>.png media/slides/chapter-<N>/slide-<n>-<descriptive-name>.png
```

Name files as: `slide-<number>-<short-description-of-content>.png`
Never name a file after its slide number alone (e.g. `slide-25.png`) — the name
must describe what is actually in the image.

### Embedding figures

Use the exact format the existing notes use:

```markdown
![](media/slides/chapter-N/slide-<n>-<description>.png)

**Figure (Slide N)** One-sentence description of what the figure shows and why it is here.
```

The caption must state what the figure actually contains, not what the slide
section is titled.

## What to avoid

- ❌ Navigation/outline slides (chapter menu, "Theory / Practice / Project 1" section dividers)
- ❌ Slides you have not viewed as an image
- ❌ Captions describing the slide's section heading instead of its content
- ❌ Duplicating information already in the book's own embedded figures
- ❌ Jumping ahead to later subsections before the current one is fully clear
- ❌ Appending bulk content (whole-chapter indexes, all-subsections at once) unless explicitly requested
- ❌ Creating extra documentation files (READMEs, summaries) unless asked

## After each subsection

1. Verify all embedded image paths resolve to actual files (`ls media/slides/...`).
2. Confirm headings match the book's structure exactly.
3. Stop and present the work — do not proceed to the next subsection automatically.
4. Update the `## Current Progress` marker in the workspace `AGENTS.md` to reflect where we are.

## When you are not sure

Ask. Specifically:
- If the current progress marker in `AGENTS.md` is ambiguous (which subsection to work on next).
- If a slide might add value but you are not certain (describe it, let the user decide).
- If the transcript diverges significantly from the book (flag the discrepancy, do not silently pick a side).
- If a figure is too large or complex to usefully embed in notes format.

The user controls direction and quality bar. You control execution and mechanical discipline.
