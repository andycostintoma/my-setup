---
description: Refresh OpenCode models, pick top free models, and update favorites
---

Refresh the OpenCode model catalog, inspect all OpenCode providers and models, research the best free candidates, live-test access to avoid subscription-gated false positives, rank the top 5 usable free models for coding-agent use, then set my OpenCode favorites to exactly 7 entries in this order: top 5 usable free models, latest OpenAI model, latest Anthropic model. Rank best overall from the catalog, not just models from currently connected providers, but only write free models that pass validation or are clearly setup-required rather than paid-only.

Use this exact workflow:

1. Always run `opencode models --refresh` first.
2. Read the refreshed OpenCode model catalog cache from `~/.cache/opencode/models.json`.
3. Extract free candidate models where `(cost.input // 0) == 0` and `(cost.output // 0) == 0`.
4. Build a shortlist of promising free coding-agent candidates from the local catalog. Include enough candidates to compare, not just the first 5 matches.
5. Research the shortlisted models before final ranking. Prefer official provider/model docs, model cards, OpenRouter/model pages, release notes, benchmarks, and reputable recent comparisons. Look for coding ability, agent/tool-use reliability, context behavior, latency/reliability, free-tier caveats, and current availability.
6. Create an initial ranking of free models overall for coding-agent use. Do not demote a model only because its provider is not currently connected; instead, report that an account/API key is needed before it will appear in OpenCode's model picker. Prioritize:
   - tool calling support, especially `tool_call` / tools capability
   - reasoning support
   - high context and output limits
   - coding and agent benchmark evidence when available
   - reliability/availability on the specific free provider route
   - model quality signals from provider, model name, and model id
   - coding/agent-specific model families such as Qwen Coder, DeepSeek Flash/Pro, Nemotron Super, GLM, Kimi, MiniMax, and Poolside Laguna
7. Prefer models that are actually suitable for OpenCode coding sessions. Exclude image/audio-only models, embeddings, rerankers, moderation/safety-only models, and routers unless the router is clearly better than fixed free models.
8. Before writing favorites, smoke-test the ranked free-model shortlist through OpenCode using the exact `provider/model` id. Use OpenCode's available non-interactive prompt mode if present; otherwise inspect `opencode --help` and the installed/source CLI to find the correct prompt syntax. The test prompt should be tiny, for example: `Reply only: OK`.
9. Validate candidates in rank order until 5 usable free models are found. For each candidate:
   - If the model returns a normal response, mark it usable for this run.
   - If the error clearly says subscription, upgrade, payment, billing, paid plan, forbidden because of entitlement, or similar, mark it not free-access and skip it.
   - If the error says missing API key, unauthorized, provider not connected, or account required, do not treat that as a model-quality failure. Mark it setup-required and report that I need to create/connect that provider account/API key before using it.
   - If the error is rate limit, temporary quota, timeout, network failure, 5xx, or provider overload, retry once with the same tiny prompt. If it still fails, mark it temporarily unavailable and continue down the shortlist, but do not permanently blacklist it.
   - Keep exclusions for the current command run only unless the user explicitly asks to persist a denylist.
10. The final top 5 free favorites must be the best ranked candidates that either passed the smoke test or are only blocked by missing provider setup. Do not include candidates that clearly require a paid subscription/upgrade.
11. Select the latest suitable OpenAI coding/chat model from the `openai` provider. Exclude image/audio-only models, embeddings, search-only models, and research-only models. Prefer the newest flagship coding/chat model by release date and model naming.
12. Select the latest suitable Anthropic coding/chat model from the `anthropic` provider. Exclude legacy variants when a newer equivalent exists. Prefer the newest flagship Opus/Sonnet model by release date and model naming.
13. Read OpenCode favorites from `~/.local/state/opencode/model.json` field `.favorite`.
14. Replace `.favorite` with exactly 7 objects using this order: the selected top 5 free models, then the selected OpenAI model, then the selected Anthropic model.
15. Write the updated JSON back to `~/.local/state/opencode/model.json`.
16. Check which selected free-model providers are already connected or visible in OpenCode when possible.
17. For any selected free model whose provider is not connected or visible, explicitly tell me to create the required provider account if needed, get the API key/auth, and connect that provider in OpenCode before expecting the favorite to appear.
18. Report the 7 selected models, why they were selected, what research sources/signals were used, smoke-test results, which candidates were skipped and why, which provider accounts/API keys are required, which selected providers appear to be missing, and whether OpenCode should be restarted for the TUI to reflect the change.
19. If the user asks why a favorite is not visible, explain that OpenCode only shows favorites for connected/enabled providers and ask before replacing best-overall picks with currently visible alternatives.

Do not modify unrelated OpenCode config. The final favorites list should contain exactly 7 entries.
