# Claude Code local setup

Claude Code-specific wiring on this machine. For the harness-agnostic stack (OpenViking, rtk), see `LOCAL-STACK.md`.

## Key paths

- Settings: `~/.claude/settings.json`
- Global instructions: `~/.claude/CLAUDE.md` (managed by Home Manager from `~/.config/nix-darwin/harness/claude/CLAUDE.md`)
- Hooks: `~/.claude/hooks/`
- Agents: `~/.claude/agents/` (managed by Home Manager from shared agents in `~/.config/nix-darwin/harness/shared/agents/`)
- Commands: `~/.claude/commands/` (managed by Home Manager from `~/.config/nix-darwin/harness/shared/commands/`)
- Skills: `~/.claude/skills/` (managed by Home Manager from shared skills in `harness/shared/skills/`)
- Plans: `~/.claude/plans/`
- OV per-project default config: `~/.claude/ov-hooks/ov.conf`

## Hooks

Configured in `~/.claude/settings.json`. Each row maps a Claude Code event to a script in `~/.claude/hooks/`.

| Event | Script | Purpose |
|---|---|---|
| `SessionStart` | `ov-session-start.sh` | OpenViking session bootstrap |
| `UserPromptSubmit` | `ov-user-prompt.sh` | OpenViking memory recall — injects relevant prior context |
| `Stop` | `ov-stop.sh` + `afplay Glass.aiff` | OV memory write + sound notification |
| `SessionEnd` | `ov-session-end.sh` | OV session cleanup |
| `PreToolUse` (Bash) | `rtk-rewrite.sh` | Compresses bash output via `rtk rewrite` (>= 0.23.0) |
| `PermissionRequest` | `afplay Glass.aiff` | Sound notification |
| `PreCompact` | `pre-compact.sh` | Injects guidance about what to preserve verbatim during compaction |

The OV hooks are thin wrappers that delegate to the canonical OpenViking claude-memory-plugin scripts under `~/openviking_workspace/.../claude-memory-plugin/hooks/`.

## Subagents

**Built-ins** (provided by Claude Code, configurable via `model:` parameter on the Agent tool call):

- `general-purpose` — multi-step research and execution
- `Plan` — implementation strategy
- `Explore` — codebase exploration (prefer for broad search)
- `statusline-setup` — config helper

**User-defined** (in `~/.claude/agents/`, published by Home Manager from shared harness sources):

- `code-reviewer` — `model: sonnet`
- `security-reviewer` — `model: sonnet`
- `tech-lead` — default model (heavy architectural reasoning)

The `model:` field in agent frontmatter is respected by Claude Code. Edit canonical files in `~/.config/nix-darwin/harness/` and run `nix-switch` - never edit generated harness copies directly.

## LiteLLM (opt-in, not enabled)

Claude Code talks to `api.anthropic.com` directly. To route through LiteLLM:

```sh
export ANTHROPIC_BASE_URL=http://127.0.0.1:4000
```

Caveats:

- Bypasses Claude Code subscription auth — uses API key billing
- Anthropic ↔ OpenAI tool-call translation is lossy for some tools
- Long agent loops can suffer if a request mid-conversation routes to a different provider

Recommended: leave off. Use per-subagent `model:` overrides for cost control instead.

## Intentionally not mirrored from opencode

- **auto-explore plugin** — Claude Code hooks can inject context but cannot spawn subagents. The built-in system prompt already nudges toward `Explore` for broad searches.
- **dcp/compress tool** — Claude Code's built-in `/compact` plus `pre-compact.sh` cover the same ground.

## Quick checklist (Claude Code-specific)

- Settings valid: `jq . ~/.claude/settings.json`
- Hooks executable: `ls -l ~/.claude/hooks/*.sh`
- Agents present after `nix-switch`: `ls ~/.claude/agents/`

For shared stack health checks (OpenViking, rtk), see LOCAL-STACK.md.
