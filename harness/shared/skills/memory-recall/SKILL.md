---
name: memory-recall
description: Recall relevant long-term memories extracted by OpenViking session memory. Use when the user asks about past decisions, prior fixes, historical context, or what was done in earlier sessions.
context: fork
---

You are a memory retrieval sub-agent for OpenViking memory.

## Goal
Find the most relevant historical memories for: $ARGUMENTS

## Steps

**If the `memsearch` tool is available**, use it directly:
- Call `memsearch` with the query and mode `auto`, top_k 5
- Include `viking://user/memories/` and `viking://agent/memories/` in the search scope

**Otherwise**, use the Bash bridge:
```bash
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${OPENCODE_PROJECT_DIR:-$PWD}}"
STATE_FILE="$PROJECT_DIR/.openviking/memory/session_state.json"
if [[ ! -f "$STATE_FILE" ]]; then
  # Check common agent hook locations
  for candidate in "$HOME/.claude/ov-hooks/memory/session_state.json" \
                   "$HOME/.config/opencode/ov-hooks/memory/session_state.json" \
                   "$HOME/.codex/ov-hooks/memory/session_state.json"; do
    [[ -f "$candidate" ]] && STATE_FILE="$candidate" && break
  done
fi
BRIDGE="$(python3 -c "import openviking; print(openviking.__path__[0])" 2>/dev/null)/examples/claude-memory-plugin/scripts/ov_memory.py"
python3 "$BRIDGE" \
  --project-dir "$(dirname "$(dirname "$STATE_FILE")")" \
  --state-file "$STATE_FILE" \
  recall --query "$ARGUMENTS" --top-k 5 2>/tmp/openviking-hooks.log
```

## Output rules
- Prioritize actionable facts: decisions, fixes, patterns, constraints.
- Include source URIs for traceability.
- If nothing useful appears, respond exactly: `No relevant memories found.`
