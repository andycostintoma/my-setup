# Local Stack (harness-agnostic)

Shared local infrastructure that supports multiple AI agent harnesses. Each harness has its own `SETUP.md` for harness-specific wiring; this doc covers the components that all of them can plug into.

Canonical source: `my-setup/shared/harness/shared/LOCAL-STACK.md`. Home Manager publishes this file into each harness root.

## Components

- **OpenViking** — personal cross-session memory + semantic index of external/reference repos.
- **graphify** — typed knowledge graph of the active working repo for relationship/traversal questions.
- **context broker** — opencode automation that keeps OpenViking/graphify useful without always-on prompt instructions.
- **rtk** — CLI proxy that filters/compresses command *output* before it reaches LLM context.
- **DCP** (`@tarquinen/opencode-dcp`) — model-driven, surgical mid-session *context* compression (opencode only).

### Which tool for which question

These overlap in spirit ("help the model find things") but operate on different axes — keep them distinct:

| Need | Use |
|---|---|
| Recall a past decision / preference / prior session | OpenViking memory |
| Look up an **external / reference** repo (frameworks, other services) | OpenViking resources |
| Understand how the **current repo** wires together (callers, paths, neighbors) | graphify |
| Shrink noisy shell command **output** | rtk |
| Shrink the running conversation **context** mid-session | DCP (`compress`) + opencode built-in compaction |

OpenViking indexes *other* repos and your memory; graphify graphs the active repo. They are complementary, not redundant.

## OpenViking

### What it does

- Personal memory storage with vector search (cross-session preferences, entities, agent cases)
- Semantic index of ~external/reference repos under `viking://resources/`

Server: `http://127.0.0.1:1933`. Data: `~/.openviking/`.

On Nix-managed machines, OpenViking CLI/server/hooks should be provided by Nix/Home Manager. Keep secret config such as API keys local or encrypted; do not commit plaintext secrets.

### Recall scoping (important)

When automatic OpenViking reads are configured, scope to high-signal directories only:

- `viking://user/default/memories/preferences`
- `viking://user/default/memories/entities`

Avoid `events/` — diary-style noise that hurts signal.

### Per-harness adoption

- **opencode**: `openviking/memory.ts` captures sessions, exposes the `memread`/`membrowse`/`memsearch`/`memcommit` tools, and auto-commits captured work in the background. `automation/context-broker.ts` performs compact, high-confidence OpenViking reads when prior memory/cross-repo/reference context is relevant. Home Manager publishes `~/.openviking/ovcli.settings.conf` so the `ov` CLI is initialized without a manual language-selection step.

## graphify

### What it does

Builds a typed knowledge graph (`graphify-out/graph.json`) of the current repo — nodes (functions, types, files, modules) and edges (calls, imports, relationships) — then answers structural questions without scanning the whole codebase.

Provided by Nix as the `graphify` and `graphify-python` CLI wrappers (pinned `graphifyy` via `uvx`). Core verbs:

- `graphify extract <path>` — full extraction (AST + semantic LLM); run once to build the graph.
- `graphify update <path>` — re-extract changed code files (no LLM); run after edits.
- `graphify query "<question>"` — BFS traversal answering a natural-language question.
- `graphify path "A" "B"` — shortest relationship path between two nodes.
- `graphify explain "X"` — plain-language explanation of a node and its neighbors.
- `graphify watch <path>` — rebuild on change.

Use `--max-concurrency 1` with local LLM backends.

> **Never run graphify (or any `uvx` tool) under `sudo`/root.** Doing so writes root-owned entries into `~/.cache/uv`, which then breaks normal user-context runs with permission errors. If that happens, `chown` the affected cache entries back to the user.

### Mechanism

graphify is exposed as three layers:

- **CLI** — the tool itself (Nix-managed).
- **`graphify` skill** — the workflow/knowledge for building and querying the graph.
- **`/graphify` command** — thin entrypoint that invokes the skill.
- **context broker** — background maintenance and compact retrieval for active repos.

### Per-harness adoption

- **opencode**: custom tools in `~/.config/opencode/tools/graphify.ts` expose `graphify_query`, `graphify_path`, and `graphify_explain`, which shell out to the CLI against `<project>/graphify-out/graph.json` (they prompt to build the graph first if it is missing). The `graphify` skill + `/graphify` command remain available for explicit build/update workflows.
- **opencode**: `automation/context-broker.ts` watches tool activity, marks active repos dirty, debounces `graphify update`, and runs `graphify extract` only for repos under trusted auto-init roots configured by the consuming setup repo. It injects only compact Graphify query results for high-confidence current-repo structure questions; it does not inject generic routing instructions or full graph reports.

## Context Broker

The broker is the automatic layer that keeps OpenViking and graphify available without polluting normal prompts.

- Write side: OpenViking session capture/auto-commit remains in `openviking/memory.ts`; the broker handles graphify maintenance only.
- Read side: the broker searches OpenViking for high-confidence prior-memory/cross-repo/reference questions and queries graphify for high-confidence active-repo structure questions.
- Ambiguous requests inject nothing.
- Results are compact and turn-scoped under `## Retrieved Context`; no indexed repo list, generic routing guide, or failed-status spam is injected.
- Config: `~/.config/opencode/context-broker.json`. Shared defaults are safe; machine/workspace-specific trusted roots belong in the consuming setup repo.

## rtk

CLI proxy that strips noise, deduplicates, and summarizes shell output before it reaches LLM context. Source of truth for rewrite rules: `rtk rewrite` (Rust binary).

### Key behaviors

- `rtk test` is silent on success; output only on failure.
- Calling `rtk` directly: each subcommand has its own flags. Run `rtk <subcommand> --help` — don't pass native tool flags blindly.
- If a command fails through `rtk`, run the native command directly.
- Don't retry the same command hoping for different output — the rewrite is deterministic.

### Per-harness adoption

- **opencode**: `openrtk` plugin wraps bash tool execution.

## DCP (Dynamic Context Pruning)

`@tarquinen/opencode-dcp` exposes the `compress` tool that the model invokes to surgically compress *closed* sections of the conversation mid-session (plus deduplication of repeated tool calls and error-input purging). Session history is never destroyed — pruned content is replaced with placeholders before being sent to the LLM.

This is **not** redundant with opencode's built-in `compaction`:

- **Built-in compaction** — coarse, automatic, whole-session; fires when the context window fills. A safety net.
- **DCP** — fine-grained, model-driven, surgical; compresses specific stale spans early. Finer control + earlier token savings.

They coexist. Trade-off: pruning slightly lowers prompt-cache hit rate (~5%), usually a net win on long sessions. Config lives in `dcp.jsonc` at the opencode config root (currently all defaults).

### Per-harness adoption

- **opencode**: `@tarquinen/opencode-dcp` plugin; built-in compaction remains as a backstop.

## Quick checklist

- OpenViking running: confirm server on `127.0.0.1:1933`
- rtk available: `rtk --version` (need >= 0.23.0)
- graphify available: `graphify --help` (must run as your user, not root)
