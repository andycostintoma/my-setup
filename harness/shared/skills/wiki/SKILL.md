---
name: wiki
description: "Activate when working inside an LLM-Wiki — a personal/team knowledge base built from raw sources into an LLM-maintained markdown wiki. Detect by presence of `raw/`, `wiki/`, `index.md`, `log.md`, and a wiki-schema section in `AGENTS.md`. Covers ingest, query, lint, page conventions, citation discipline, and index/log maintenance. Based on Karpathy's LLM-Wiki pattern with mandatory provenance."
license: MIT
compatibility: opencode,claude,codex
---

# LLM-Wiki Maintenance

You are the disciplined maintainer of an LLM-Wiki — a persistent, compounding knowledge base. The human curates sources and asks questions. You do all the bookkeeping: summarizing, cross-referencing, filing, citation tracking, lint.

## Detecting a wiki

A directory is a wiki when ALL of these exist at its root:
- `raw/` — immutable source material
- `wiki/` — LLM-owned markdown pages
- `index.md` — catalog of wiki pages
- `log.md` — chronological event log
- `AGENTS.md` — contains a `## Wiki Schema` section with this wiki's conventions

If any are missing, this is not a wiki — do not apply these procedures. Suggest `/wiki-init` if appropriate.

## Initializing a wiki

When asked to bootstrap a new wiki (e.g. via `/wiki-init`), **interview first,
scaffold minimally, let structure emerge.** Real wikis diverge in shape — some
follow the canonical `raw/`+`wiki/` Karpathy split, others grow custom top-level
dirs (`learning/`, `ops/`, `schema/`, `flows/`, `tasks/`, `shared/`), embed
inside a working code repo under `.wiki/`, add their own `_lint.py`, or use git
submodules. Do not impose the full directory tree up front; seed the minimum and
record this wiki's conventions in its schema.

### Interview

Confirm `pwd` is the intended location. If it contains files other than `.git`,
`.gitignore`, `README.md`, stop and ask whether to abort, target a subdirectory,
or proceed in place. Then ask:

- **Domain:** what is this wiki about?
- **Source style:** text-only / mixed media / code repos.
- **Expected scale:** dozens / hundreds / thousands of sources.
- **Shape:** standalone wiki repo, or embedded in an existing project (e.g.
  `.wiki/` inside a code repo)?
- **Naming conventions:** any rules to lock in (lowercase, disambiguators).

### Minimal seed

Create only what every wiki needs; do not pre-create empty page-type dirs —
create `wiki/entities/`, `concepts/`, etc. on first use when they actually hold a
page. The seed:

- `raw/` (with `.gitkeep`) — immutable sources. Skip if the wiki is purely
  synthesis with no raw corpus, and note that in the schema.
- `wiki/` (with `.gitkeep`) — LLM-owned pages.
- `index.md` — catalog with stub sections (`_none yet_`).
- `log.md` — append-only log with a single bootstrap entry
  (`## [<TODAY>] init | wiki bootstrapped`).
- `AGENTS.md` — two clearly separated sections: a short **Agent Policy**
  (activate the `wiki` skill; never modify `raw/`; cite every non-trivial claim;
  append to `log.md`; keep `index.md` in sync) and a **Wiki Schema** capturing
  the interview answers plus this wiki's page types, slug rules, frontmatter
  schema, and citation format (see the sections below for the canonical
  defaults — copy and adapt, don't impose).
- `.gitignore` — `.DS_Store`, `.obsidian/workspace*`, `*.tmp`, `lint-report-*.md`.
- `README.md` (optional) — a short pointer to `raw/`, `wiki/`, `AGENTS.md`, and
  this skill.

Substitute `<TODAY>` with the real ISO date and the interview placeholders with
the user's actual answers. If the user declines a question, use a sensible
default and flag it in the schema as `TODO: confirm`.

### After scaffolding

- Initialize git only if asked: `git init` then `git add -A`. **Stage, do not
  commit** (global policy: no commits without explicit instruction).
- Do not ingest any sources during init — ingest is a separate operation.
- Tell the user to restart their agent session if the harness config that
  publishes this skill is stale, drop the first source into `raw/`, then ask for
  an ingest.

## The three layers

| Layer | Path | Owner | Mutability |
|---|---|---|---|
| Raw sources | `raw/` | Human | **Never modify.** Read-only source of truth. |
| Wiki | `wiki/` | LLM (you) | You create, update, link, delete pages here. |
| Schema | `AGENTS.md` § Wiki Schema | Co-evolved | Human and LLM update together; conventions for THIS wiki. |

`raw/` is sacred. Never edit, rename, or delete files there without explicit user instruction. If a source must change, the user does it.

## Page anatomy

Every wiki page MUST have:

```markdown
---
type: entity | concept | source-summary | comparison | overview | synthesis
created: YYYY-MM-DD
updated: YYYY-MM-DD
sources: [raw/path/to/source-1.md, raw/path/to/source-2.pdf]
tags: [tag1, tag2]
---

# Page Title

Body content with inline citations: claim about X[^src1].

Another claim synthesizing two sources[^src1][^src2].

## Sources

[^src1]: `raw/path/to/source-1.md` — optional anchor (heading, page, line range)
[^src2]: `raw/path/to/source-2.pdf` — p. 14
```

`sources` in frontmatter lists every raw/ file the page draws from. Footnotes attach to specific claims. Both must agree: every footnote must appear in `sources`, and every entry in `sources` should be cited at least once in the body.

## Citation rule (mandatory)

This is the single non-negotiable invariant. The biggest valid critique of LLM-Wiki is lossy compression — derived pages can drift from sources, drop caveats, invent details. Citations are the mitigation.

Rules:
1. **Every non-trivial factual claim must cite at least one raw source.** Definitions, dates, numbers, attributions, quotes, opinions-of-authors — all require a citation.
2. **Synthesis claims cite all sources they synthesize.** "Both X and Y argue Z[^src1][^src2]" not "X and Y argue Z[^src1]".
3. **Never invent entities or facts not in `raw/`.** If a page mentions a person, paper, dataset, or event, it must trace back to a raw source. If you need to add context not in any source, mark it explicitly: `> **Note (LLM):** ...` — these notes are excluded from citation requirements but flagged on lint.
4. **Don't paraphrase past the point of fidelity.** When a source's exact wording matters (definitions, claims under dispute), quote it.
5. **Stale citations are bugs.** If you update a page, verify cited sources still support the surviving claims.

Acceptable uncited content: structural prose ("This page covers..."), navigation ("See also..."), TOCs, transition sentences. When in doubt, cite.

## Page types and naming

- `wiki/entities/<slug>.md` — people, organizations, products, places, datasets.
- `wiki/concepts/<slug>.md` — ideas, theories, methods, patterns.
- `wiki/sources/<slug>.md` — per-source summaries (one per ingested source).
- `wiki/comparisons/<a>-vs-<b>.md` — side-by-side analyses.
- `wiki/overviews/<topic>.md` — high-level synthesis pages.
- `wiki/_synthesis.md` — the evolving thesis (optional, one per wiki).

Slugs: lowercase, hyphenated, ASCII. Use the canonical name from the source ("gpt-4" not "gpt4"). Wiki-schema in `AGENTS.md` may override these defaults.

## Cross-references

Use Obsidian-style wikilinks: `[[entities/transformer]]` or `[[concepts/attention-mechanism]]`. They render in Obsidian and are easy for you to grep. Every entity mentioned across pages should have its own page; every concept page should be linked from at least one other page (no orphans).

## index.md format

Content-oriented catalog. Sectioned by page type. Each entry: link, one-line summary, source count, last-updated date.

```markdown
# Index

## Entities
- [[entities/transformer]] — Neural architecture introduced in "Attention Is All You Need". (sources: 4, updated: 2026-04-12)
- [[entities/openai]] — Research lab behind GPT series. (sources: 7, updated: 2026-04-15)

## Concepts
- [[concepts/attention-mechanism]] — Mechanism for weighting input relevance. (sources: 3, updated: 2026-04-10)

## Sources
- [[sources/attention-is-all-you-need]] — Vaswani et al., 2017. NeurIPS paper introducing the Transformer. (ingested: 2026-04-08)

## Overviews
- [[overviews/transformer-architecture]] — Synthesis of how Transformers work and why. (sources: 6, updated: 2026-04-15)
```

Update `index.md` on every ingest and every page rename/delete.

## log.md format

Chronological, append-only. One entry per event. Standard prefix: `## [YYYY-MM-DD] <op> | <subject>`.

```markdown
## [2026-04-08] ingest | Attention Is All You Need
Added raw/papers/attention-is-all-you-need.pdf.
- Created [[sources/attention-is-all-you-need]]
- Created [[entities/transformer]]
- Updated [[concepts/attention-mechanism]] (was stub)
- Updated [[overviews/nlp-architectures]] (added Transformer section)

## [2026-04-09] query | "How does multi-head attention differ from single-head?"
Filed answer as [[concepts/multi-head-attention]].

## [2026-04-15] lint | scheduled
Found 3 contradictions, 2 orphan pages, 1 uncited claim. See lint-report-2026-04-15.md (transient, not committed).
```

The log is the operational history. Never edit past entries; append corrections as new entries.

## Workflows

### Ingest

When the user adds a source to `raw/` and asks you to process it:

1. **Read** the source in full. For long PDFs, read sections sequentially.
2. **Discuss** key takeaways with the user — confirm what's worth filing before writing.
3. **Create** `wiki/sources/<slug>.md` — the source summary, with citations back to specific sections of the source.
4. **Identify** entities and concepts mentioned. For each:
   - If a page exists, **update** it (add new claims with citations, reconcile conflicts, update `sources` and `updated` frontmatter).
   - If not, **create** a new entity/concept page.
5. **Update** relevant overview/synthesis pages to integrate the new findings.
6. **Update** `index.md` — add new entries, bump source counts and dates.
7. **Append** a log entry listing every page touched.
8. **Verify** the citation invariant on every touched page.

A single ingest typically touches 5–15 pages. Stay involved with the user — don't batch-ingest silently.

### Query

When the user asks a question:

1. **Read** `index.md` first to find candidate pages.
2. **Read** those pages. Follow wikilinks if needed.
3. **Answer** with citations to wiki pages (and through them to raw sources). Distinguish what the wiki says from what you're inferring.
4. **Offer** to file the answer as a new page if it's a non-trivial synthesis the user might want again. Comparison answers, novel connections, and "explain X" responses are good candidates.
5. **Append** a log entry.

If the wiki doesn't have enough to answer, say so. Don't fabricate. Suggest sources to ingest.

### Lint

Periodic health check. Run when asked, or proactively after large ingest batches.

Detect:
- **Contradictions** — pages that make conflicting claims, especially across sources of different dates or authors.
- **Stale claims** — claims contradicted by a newer source the page hasn't yet integrated.
- **Uncited claims** — body sentences that look factual but lack a footnote.
- **Frontmatter drift** — `sources` doesn't match the footnotes actually used.
- **Orphan pages** — wiki pages with no inbound wikilinks.
- **Missing entity pages** — entities mentioned across multiple pages but lacking their own page.
- **Broken raw/ paths** — citations or `sources` entries pointing to non-existent files.
- **Missing cross-references** — pages discussing related concepts without linking.
- **Index drift** — `index.md` entries for pages that don't exist, or pages missing from `index.md`.

Output a lint report. Do not auto-fix without user approval — propose changes, let the human decide. Rationale: many lint candidates are judgment calls (is this really a contradiction, or just nuance?). Cheap to surface, expensive to silently rewrite.

## Scaling

`index.md` works well to ~hundreds of pages. Beyond that, add a search layer:

- **qmd** (https://github.com/tobi/qmd) — local BM25/vector search over markdown, has CLI + MCP server.
- **ripgrep + frontmatter** — works for any size; cheaper to maintain than a full search index.
- **Per-section sub-indexes** — `wiki/entities/_index.md`, etc., shrinks the load-first surface.

Don't pre-build search infrastructure. Add it when navigation actually slows. Document the migration in `AGENTS.md` § Wiki Schema when you do.

## Anti-patterns

- ❌ Modifying anything under `raw/`.
- ❌ Paraphrasing without citing.
- ❌ Deleting or rewriting past `log.md` entries.
- ❌ Inventing entities not present in raw sources.
- ❌ Batch-ingesting without verifying citations on every touched page.
- ❌ Auto-fixing lint findings — always propose first.
- ❌ Letting `index.md` drift from actual wiki contents.
- ❌ Using flat slugs that collide ("openai" the company vs. "openai" the API — qualify: `openai-company`, `openai-api`).
- ❌ Mixing the harness's `AGENTS.md` policy with the wiki schema. Keep them in clearly separated sections.

## Tools

- **Obsidian** — recommended viewer. Graph view shows orphans and hubs at a glance.
- **git** — wiki is a markdown git repo; commit after every ingest.
- **rg / grep** — fastest way to find a claim, entity, or citation across pages.
- **Marp** — markdown slide format if the user wants slide deck output from wiki content.

## Output formats for queries

The default answer is markdown filed back into the wiki, but for one-off queries you can produce:
- A new wiki page (preferred for synthesis).
- A markdown table (comparisons).
- A Marp slide deck (`---` separated slides; tell the user to render).
- A matplotlib chart (script, not image — let the user run it).

Always cite sources regardless of output format.

## When you're not sure

Ask. Specifically:
- Before deleting or renaming a wiki page.
- Before resolving a contradiction by picking one side.
- Before merging two entity pages.
- Before adding a `> **Note (LLM):**` block (these are exceptions to citation; user should approve).

The user is responsible for direction; you're responsible for execution and bookkeeping.
