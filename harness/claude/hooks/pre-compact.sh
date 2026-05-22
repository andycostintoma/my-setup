#!/usr/bin/env bash
# Injected before compaction to guide what the summary preserves.
# Mirrors DCP's protectedTools + compression prompt defaults.
jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "PreCompact",
    "additionalContext": "When summarizing this session, always preserve verbatim: (1) the current PLAN.md state and any open decisions, (2) completed Task/TodoWrite outputs and their conclusions, (3) file paths and line numbers of recent edits with a one-line reason, (4) any OpenViking search results that informed the current work, (5) architecture decisions and the reasoning behind them. Compress only: repeated tool outputs, exploratory dead-ends, and intermediate bash output already captured by RTK. Never compress the most recent user message or the last assistant response."
  }
}'
