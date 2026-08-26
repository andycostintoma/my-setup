---
name: medidrive-wiki
description: "Activate for MediDrive workspace wiki work under ~/medidrive/.wiki: querying, filing findings, maintaining task and flow and decision pages, Linear MED2 task scaffolding, and MediDrive-specific wiki ownership rules. Load alongside the generic wiki skill when useful; this skill overrides generic raw/wiki assumptions for this workspace."
license: MIT
compatibility: opencode,claude,codex
---

# MediDrive Wiki Overlay

Use this skill for the MediDrive knowledge base at `~/medidrive/.wiki/`. It layers on top of the generic `wiki` skill, but MediDrive rules win when they differ.

## Scope

- Wiki root: `~/medidrive/.wiki/`
- Workspace policy: `~/medidrive/AGENTS.md`
- Source of truth: code in `~/medidrive/repos/<repo>/`; wiki pages are scratch memory and orientation
- There is no generic `raw/` + `wiki/` split here. Do not require generic LLM-Wiki detection before applying MediDrive wiki rules.

## Canonical homes

Exactly three tiers: `tasks/`, `flows/`, `shared/`. Every cross-cutting fact has one home:

- Domain vocabulary: `shared/glossary.md`
- Proto contracts: source-of-truth files in `~/medidrive/repos/nemt-proto/proto/`; use `shared/protos/index.md` only as a source pointer/status index, and do not create `shared/protos/<package>.md` mirror pages
- Cross-service flows spanning ≥ 2 repos or ≥ 1 vendor: `flows/<flow>.md`
- Ecosystem decisions: `shared/decisions/NNN-*.md`
- Known bugs / inconsistencies awaiting a ticket: `shared/followups/`
- Procedures: `shared/<topic>.md`
- Linear work specs: `tasks/med2-<id>-<slug>.md`
- Linear umbrellas: `tasks/med2-<id>-<slug>/index.md` plus sibling sub-ticket pages
- Umbrella-scoped migration/decision context: `tasks/med2-<id>-<slug>/migration/` or `tasks/med2-<id>-<slug>/decisions/`

Per-repo middle-tier folders are intentionally not part of this wiki. Do not create `<repo>/callers/`, `<repo>/outbound/`, `<repo>/rpcs/`, `<repo>/actors/`, `<repo>/actions/`, `<repo>/architecture/`, `<repo>/flows/`, or `<repo>/migration/`. Source code is the source of truth for that shape; rebuild it ad hoc when needed.

Keep content task-scoped until a second umbrella or service needs it, then promote to `shared/` or `flows/`, rewrite links, and log the promotion in `~/medidrive/.wiki/log.md`.

## Page rules

- Filenames: kebab-case, no dates in filenames
- Frontmatter: `tags`, `status`, `last-verified`, `volatility`
- Volatility contract:
  - `stable`: trust unless superseded by ADR
  - `current`: trust shape, verify specific refs
  - `volatile`: use as index only; re-read source before coding or quoting
- Prefer pointers over snippets. Snippet only when exact code is load-bearing.
- Shard pages over ~300 lines or covering more than 3 distinct entities.
- Use code refs with `path/from/repo/root.go:L42` or relative markdown links per `AGENTS.md`.

## Workflows

### Query

1. Start from `~/medidrive/.wiki/index.md` unless the user points to a page.
2. Use wiki pages for orientation.
3. Verify source code before acting on `volatile` claims or quoting specific implementation details.
4. If the answer came from source and belongs in durable memory, file it back into the wiki and append the relevant `log.md` entry.

### Ingest

1. File facts into their canonical home.
2. Update relevant indexes on page add/rename/delete.
3. Append `## [YYYY-MM-DD] ingest | <topic>` to `~/medidrive/.wiki/log.md`. There is one append-only log; there are no repo-local logs.
4. Bump `last-verified` on touched pages.

### Task pages

Use `tasks/med2-<id>-<slug>.md`, or `tasks/med2-<id>-<slug>/index.md` plus sibling sub-ticket pages when the ticket is an umbrella. Include:

- Frontmatter: `linear`, `branch`, `repos`, `area`, plus normal page fields
- `Brief`: goal/spec from Linear
- `Git-verified`: branches, commits, files, merge status
- `Divergence from doc`: when Linear and git disagree; git wins
- `Staging QA`: exact recipes, target IDs, Spanner verification, error matrix, provisioning SQL
- `Related`: links to flow/decision/proto pages

When importing/updating a MED2 task, inspect matching `med2-<id>-<slug>` branches across affected repos and compare against `origin/staging`.

### Linear ticket drafting

For a pasteable Linear ticket:

- Title: imperative, concrete, no MED2 prefix
- Body: one tight 2-4 sentence paragraph
- No tables, file lists, proto deltas, acceptance criteria, related links, or push order
- Full details belong in the wiki task page after the user provides the MED2 id

## Search

- `~/medidrive/repos/<repo>/`: read-only research with filesystem tools; never OpenViking for working-copy truth.
- `~/medidrive/worktrees/med2-<id>/<repo>/`: filesystem tools; this is where all task edits happen.
- Sibling MediDrive repos: OpenViking or filesystem for research; edits still go in a worktree.
- External/pattern repos: OpenViking.
- Cross-cutting wiki search: use filesystem search/read tools over `~/medidrive/.wiki/`, starting from `index.md` when unsure.
- Ask before long operations.

## Safety

- Do not create new docs unless the user asked. Wiki updates count as requested only when the task is explicitly wiki/documentation work or a finding must be filed per MediDrive workflow.
- Do not run service builds, generation, or migration commands without explicit user instruction.
- Never modify source-of-record claims from stale wiki memory alone; verify from code first.
- The wiki repo is local-only: no remote, no push. Commit wiki ops only on explicit request.
