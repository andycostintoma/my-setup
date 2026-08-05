# Local Stack (harness-agnostic)

Shared local infrastructure that supports multiple AI agent harnesses. Each harness has its own `SETUP.md` for harness-specific wiring; this doc covers the components that all of them can plug into.

Canonical source: `my-setup/shared/harness/shared/LOCAL-STACK.md`. Home Manager publishes this file into each harness root.

## Components

- **rtk** — CLI proxy that filters/compresses command *output* before it reaches LLM context.
- **DCP** (`@tarquinen/opencode-dcp`) — model-driven, surgical mid-session *context* compression (opencode only).

### Which tool for which question

These overlap in spirit ("help the model find things") but operate on different axes — keep them distinct:

| Need | Use |
|---|---|
| Shrink noisy shell command **output** | rtk |
| Shrink the running conversation **context** mid-session | DCP (`compress`) + opencode built-in compaction |

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

- rtk available: `rtk --version` (need >= 0.23.0)
