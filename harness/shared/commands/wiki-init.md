---
description: Bootstrap a new LLM-Wiki in the current directory
---

Invoke the `wiki` skill before doing anything else and follow its
"Initializing a wiki" workflow.

Bootstrap a new LLM-Wiki in the current working directory:

- Interview the user first (domain, source style, scale, shape, naming).
- Scaffold the **minimal** seed (`raw/`, `wiki/`, `index.md`, `log.md`,
  `AGENTS.md` with Agent Policy + Wiki Schema sections). Do not pre-create empty
  page-type directories — they emerge on first use.
- Let each wiki keep its own shape (standalone vs embedded `.wiki/`, custom
  top-level dirs, etc.); record conventions in the wiki's `AGENTS.md` schema.
- Stage with git only if asked; never commit. Do not ingest sources during init.

If arguments were provided after `/wiki-init`, treat them as the target
directory or domain hint.
