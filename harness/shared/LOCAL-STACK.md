# Local Stack (harness-agnostic)

Shared local infrastructure that supports multiple AI agent harnesses. Each harness has its own `SETUP.md` for harness-specific wiring; this doc covers the components that all of them can plug into.

Canonical source: `~/.config/my-setup/harness/shared/LOCAL-STACK.md`. Home Manager publishes this file into each harness root.

## Components

- **OpenViking** — personal memory storage + repo indexing.
- **rtk** — CLI proxy that filters/compresses command output before it reaches LLM context.

## OpenViking

### What it does

- Personal memory storage with vector search
- Repo indexing

Server: `http://127.0.0.1:1933`. Data: `~/.openviking/`.

On Nix-managed machines, OpenViking CLI/server/hooks should be provided by Nix/Home Manager. Keep secret config such as API keys local or encrypted; do not commit plaintext secrets.

### Recall scoping (important)

When auto-recall is configured, scope to high-signal directories only:

- `viking://user/default/memories/preferences`
- `viking://user/default/memories/entities`

Avoid `events/` — diary-style noise that hurts signal.

### Per-harness adoption

- **opencode**: `auto-recall.ts` plugin injects relevant memories into the system prompt on the first user message of a session.

## rtk

CLI proxy that strips noise, deduplicates, and summarizes shell output before it reaches LLM context. Source of truth for rewrite rules: `rtk rewrite` (Rust binary).

### Key behaviors

- `rtk test` is silent on success; output only on failure.
- Calling `rtk` directly: each subcommand has its own flags. Run `rtk <subcommand> --help` — don't pass native tool flags blindly.
- If a command fails through `rtk`, run the native command directly.
- Don't retry the same command hoping for different output — the rewrite is deterministic.

### Per-harness adoption

- **opencode**: `openrtk` plugin wraps bash tool execution.

## Quick checklist

- OpenViking running: confirm server on `127.0.0.1:1933`
- rtk available: `rtk --version` (need >= 0.23.0)
