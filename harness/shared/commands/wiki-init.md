---
description: Bootstrap a new LLM-Wiki in the current directory (raw/, wiki/, index.md, log.md, AGENTS.md schema)
---
Scaffold a new LLM-Wiki in the current working directory following Karpathy's pattern. The wiki is a persistent, citation-disciplined markdown knowledge base that an LLM agent maintains over time.

## Steps

1. **Verify the target directory.**
   - Confirm with the user that `pwd` is the intended location.
   - If the directory contains existing files (other than `.git`, `.gitignore`, `README.md`), STOP and ask whether to abort, target a subdirectory, or proceed in place.

2. **Gather context from the user.** Ask:
   - **Domain:** what is this wiki about? (e.g., "personal research on transformer interpretability", "notes on Roman history", "company onboarding wiki")
   - **Source style:** text-only / mixed media (images, audio, video) / code repos
   - **Expected scale:** dozens / hundreds / thousands of sources
   - **Naming preference for entities:** any conventions to lock in (e.g., always lowercase, always include disambiguator)

3. **Scaffold the layout.** Create:

   ```
   raw/
     .gitkeep
     assets/.gitkeep
   wiki/
     entities/.gitkeep
     concepts/.gitkeep
     sources/.gitkeep
     overviews/.gitkeep
     comparisons/.gitkeep
   index.md
   log.md
   AGENTS.md
   .gitignore
   README.md
   ```

4. **Populate templates.**

   **`AGENTS.md`** — harness policy + wiki schema. Two clearly separated sections:

   ```markdown
   # Agent Policy

   This is an LLM-Wiki. The `wiki` skill provides the full operational procedures (ingest, query, lint, citation rules). Activate it when working in this repo.

   - Never modify files under `raw/` without explicit user instruction.
   - Every non-trivial claim in `wiki/` must cite a raw source via footnote.
   - Append a log entry to `log.md` after every ingest, query-filed-as-page, or lint pass.
   - Update `index.md` whenever you create, rename, or delete a wiki page.

   ---

   # Wiki Schema

   ## Domain

   <USER-PROVIDED DOMAIN>

   ## Source style

   <text-only | mixed-media | code-repos>

   ## Expected scale

   <dozens | hundreds | thousands>

   ## Naming conventions

   - Slugs: lowercase, hyphenated, ASCII.
   - Entities: <user-provided rules, or "use canonical name from source">.
   - Disambiguation: append a qualifier in parens or hyphenated suffix when names collide.

   ## Page types

   - `wiki/entities/<slug>.md` — people, orgs, products, datasets, places.
   - `wiki/concepts/<slug>.md` — ideas, methods, theories.
   - `wiki/sources/<slug>.md` — one summary per ingested source.
   - `wiki/overviews/<topic>.md` — cross-source synthesis.
   - `wiki/comparisons/<a>-vs-<b>.md` — side-by-side analysis.

   ## Frontmatter schema

   ```yaml
   type: entity | concept | source-summary | comparison | overview
   created: YYYY-MM-DD
   updated: YYYY-MM-DD
   sources: [raw/path/to/file]
   tags: [tag]
   ```

   ## Citation format

   - Inline footnotes: `claim[^src1]`.
   - Footnote definitions in a `## Sources` section at page bottom.
   - Footnote target: `raw/` path with optional anchor (heading, page, line range).
   - Every entry in frontmatter `sources` must be cited at least once in the body.

   ## Co-evolution

   Update this schema as conventions emerge. Append a log entry when you change schema rules so future sessions know.
   ```

   **`index.md`** — empty catalog with stub sections:

   ```markdown
   # Index

   Catalog of every page in this wiki. Maintained by the LLM on every ingest.

   ## Entities
   _none yet_

   ## Concepts
   _none yet_

   ## Sources
   _none yet_

   ## Overviews
   _none yet_

   ## Comparisons
   _none yet_
   ```

   **`log.md`** — bootstrap entry only:

   ```markdown
   # Log

   Append-only chronological record. Format: `## [YYYY-MM-DD] <op> | <subject>`.

   ## [<TODAY>] init | wiki bootstrapped
   Created raw/, wiki/, index.md, log.md, AGENTS.md. Domain: <user-provided>. Ready for first ingest.
   ```

   **`.gitignore`** — minimal:

   ```
   .DS_Store
   .obsidian/workspace*
   *.tmp
   lint-report-*.md
   ```

   **`README.md`** — short pointer:

   ```markdown
   # <Wiki Name>

   An LLM-Wiki for <domain>. Sources live in `raw/` (immutable). LLM-maintained pages live in `wiki/`. See `AGENTS.md` for conventions and the `wiki` skill for procedures.

   ## Workflow

   - Drop sources into `raw/`.
   - Ask the agent to ingest. It updates `wiki/`, `index.md`, and `log.md`.
   - Query the wiki via the agent; file useful answers back as new pages.
   - Periodically run a lint pass.

   Browse `wiki/` directly or open the repo in Obsidian.
   ```

5. **Initialize git.** Ask before running:
   - `git init`
   - `git add -A`
   - Stage but do NOT commit (per global policy: no commits without explicit "commit this" instruction). Tell the user the working tree is staged and ready to commit.

6. **Print next steps:**
   - Confirm the `wiki` skill is available (`nix-switch` if the harness config is stale).
   - Drop the first source into `raw/`.
   - Ask the agent to ingest it.
   - Optionally open the directory in Obsidian.

## Rules

- Substitute `<TODAY>` with the actual current date in ISO format.
- Substitute `<USER-PROVIDED DOMAIN>` etc. with the user's actual answers; don't leave placeholders.
- If the user declines to answer some questions, use sensible defaults but flag them in `AGENTS.md` as "TODO: confirm".
- Do not ingest any sources during init. That's a separate operation.
- Do not commit. Stage only.
- Do not create any files outside the listed scaffold.
