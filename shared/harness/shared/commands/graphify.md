---
description: Build, update, or query a graphify knowledge graph
---

This command is a thin entrypoint — all workflow logic lives in the `graphify`
skill. Invoke the `graphify` skill before doing anything else.

If arguments were provided after `/graphify`, pass them through as the requested graphify operation. If no arguments were provided, build or refresh a graph for the current directory.

Use the Nix-managed `graphify` CLI and `graphify-python` helper, not `pip`, `pipx`, or `uv tool install`.
