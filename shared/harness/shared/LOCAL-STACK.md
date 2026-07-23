# Local Stack (harness-agnostic)

Shared local infrastructure that supports multiple AI agent harnesses. Each harness has its own `SETUP.md` for harness-specific wiring; this doc covers the components that all of them can plug into.

Canonical source: `my-setup/shared/harness/shared/LOCAL-STACK.md`. Home Manager publishes this file into each harness root.

## Components

- **OpenViking** — personal cross-session memory + semantic index of external/reference repos.
- **context broker** — opencode automation that keeps OpenViking useful without always-on prompt instructions.
- **rtk** — CLI proxy that filters/compresses command *output* before it reaches LLM context.
- **DCP** (`@tarquinen/opencode-dcp`) — model-driven, surgical mid-session *context* compression (opencode only).

### Which tool for which question

These overlap in spirit ("help the model find things") but operate on different axes — keep them distinct:

| Need | Use |
|---|---|
| Recall a past decision / preference / prior session | OpenViking memory |
| Look up an **external / reference** repo (frameworks, other services) | OpenViking resources |
| Shrink noisy shell command **output** | rtk |
| Shrink the running conversation **context** mid-session | DCP (`compress`) + opencode built-in compaction |

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

## Context Broker

The broker is the automatic layer that keeps OpenViking available without polluting normal prompts.

- Write side: OpenViking session capture/auto-commit remains in `openviking/memory.ts`.
- Read side: the broker searches OpenViking for high-confidence prior-memory/cross-repo/reference questions.
- Ambiguous requests inject nothing.
- Results are compact and turn-scoped under `## Retrieved Context`; no indexed repo list, generic routing guide, or failed-status spam is injected.
- Config: `~/.config/opencode/context-broker.json`. Shared defaults are safe.

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
