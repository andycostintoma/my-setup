---
name: graphify
description: "Use when the user types /graphify or asks to build, query, update, explain, or navigate a graphify knowledge graph from code, docs, papers, images, or a raw folder."
license: MIT
compatibility: opencode,claude,codex
---

# Graphify

Use `graphify` to turn code, docs, papers, screenshots, diagrams, and raw research folders into a persistent knowledge graph under `graphify-out/`.

The package installed here is the official PyPI package `graphifyy`, pinned by Nix. The CLI command is `graphify`. For Python module access inside the same pinned environment, use `graphify-python`.

## Triggers

Use this skill when:
- The user types `/graphify`.
- The user asks to build, update, query, explain, or navigate a graphify graph.
- A codebase question can be answered from an existing `graphify-out/graph.json`.

## Quick Commands

```bash
graphify extract .
graphify extract ./raw --backend claude
graphify update .
graphify query "what connects auth to billing?"
graphify path "AuthModule" "Database"
graphify explain "Scheduler"
graphify watch .
graphify hook install
```

Use `graphify --help` for the full command list.

## Agent Workflow

When building a new graph for a mixed corpus and semantic extraction is needed, use subagents for extraction instead of reading every file in the main context.

1. Detect the target path. If the user did not pass one, use `.`.
2. Run `graphify-python -c "import graphify; print('ok')"` to verify the pinned Python environment is available.
3. Prefer the CLI for normal operation: `graphify extract <path>`.
4. For manual semantic extraction or recovery, split uncached docs, papers, and images into chunks of 20-25 files.
5. Dispatch all extraction subagents in one message with the Task tool so they run in parallel.
6. Each subagent must return only JSON with `nodes`, `edges`, `input_tokens`, and `output_tokens`.
7. Mark edge confidence as `EXTRACTED`, `INFERRED`, or `AMBIGUOUS`. Never invent edges.
8. Merge subagent outputs, then run graph build, clustering, report, and visualization steps through `graphify` or `graphify-python`.

Use `--max-concurrency 1` for local LLM backends. Use higher concurrency only for API-backed models.

## Existing Graphs

Before broad codebase exploration, check whether `graphify-out/graph.json` exists.

If it exists:
- Use `graphify query "<question>"` for broad questions.
- Use `graphify path "<A>" "<B>"` for relationships.
- Use `graphify explain "<concept>"` for focused concept exploration.
- Read `graphify-out/GRAPH_REPORT.md` only for broad architecture review or when query/path/explain is insufficient.
- If `graphify-out/wiki/index.md` exists, use it for broad navigation before raw source browsing.

Dirty `graphify-out/` files are expected after hooks or updates. Do not treat them as a reason to skip the graph.

## After Code Changes

After modifying code in a repo that has `graphify-out/graph.json`, run:

```bash
graphify update .
```

This is AST-only and should not require LLM/API cost. If docs, papers, or images changed, run `graphify extract . --update` if supported by the installed CLI, or rebuild with `graphify extract .`.

## Reporting

When a graph build completes, report:
- Output path: `graphify-out/`
- `GRAPH_REPORT.md`
- `graph.json`
- `graph.html` or Obsidian/wiki outputs if generated
- The most interesting suggested question, if the report includes one

Keep the response concise. Do not paste the full report unless the user asks.
