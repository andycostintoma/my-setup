---
name: update-models
description: "Use when refreshing the OpenCode model catalog, picking the best free coding-agent models, live-testing model access, and updating OpenCode favorites. Triggers on /update-models or requests to refresh models, re-rank free models, or fix the favorites list."
license: MIT
compatibility: opencode,claude,codex
---

# Update OpenCode Models

Refresh the OpenCode model catalog, research the best free coding-agent models,
live-test access to avoid subscription-gated false positives, then set the
OpenCode favorites to exactly **7** entries in this order: the top 5 usable free
models, the latest OpenAI model, and the latest Anthropic model.

Rank best overall from the **whole catalog**, not just currently connected
providers. Only write free models that pass validation or are clearly
setup-required (missing account/API key) rather than paid-only.

## Locating files

Do not hardcode paths blindly — confirm them for the installed OpenCode version.
The conventional locations on this machine:

- Refreshed model catalog cache: `~/.cache/opencode/models.json`
- Favorites state: `~/.local/state/opencode/model.json`, field `.favorite`

If either is missing or differs, find the real location (inspect `opencode`
config dirs, `XDG_*` overrides, or `opencode --help`) before reading/writing.

## Workflow

1. Run `opencode models --refresh` first.
2. Read the refreshed catalog cache.
3. Extract free candidates where `(cost.input // 0) == 0` and
   `(cost.output // 0) == 0`.
4. Build a shortlist of promising free coding-agent candidates — enough to
   compare, not just the first 5 matches.
5. **Research** the shortlist before final ranking. Prefer official
   provider/model docs, model cards, OpenRouter/model pages, release notes,
   benchmarks, and reputable recent comparisons. Look for coding ability,
   agent/tool-use reliability, context behavior, latency/reliability, free-tier
   caveats, and current availability.
6. Rank free models overall for coding-agent use. Do not demote a model only
   because its provider is not currently connected; instead note that an
   account/API key is needed before it appears in the picker. Prioritize:
   - tool calling / tools capability
   - reasoning support
   - high context and output limits
   - coding/agent benchmark evidence when available
   - reliability/availability on the specific free route
   - quality signals from provider, model name, and id
   - strong coding/agent model families (these change over time — treat the
     current frontier as a moving target, not a fixed list; recent examples
     have included Qwen Coder, DeepSeek, Nemotron, GLM, Kimi, MiniMax, and
     Poolside Laguna families)
7. Exclude image/audio-only models, embeddings, rerankers, moderation/safety-only
   models, and routers (unless a router is clearly better than fixed free models).
8. **Smoke-test** the ranked free shortlist through OpenCode using the exact
   `provider/model` id. Use OpenCode's non-interactive prompt mode (inspect
   `opencode --help` if unsure). Keep the prompt tiny, e.g. `Reply only: OK`.
9. Validate candidates in rank order until 5 usable free models are found:
   - Normal response → usable for this run.
   - Error clearly about subscription/upgrade/payment/billing/paid plan/
     entitlement → not free-access, skip.
   - Error about missing API key/unauthorized/provider not connected/account
     required → **setup-required**, not a quality failure; report that the user
     must create/connect that provider first.
   - Rate limit/quota/timeout/network/5xx/overload → retry once with the same
     tiny prompt; if still failing, mark temporarily unavailable and continue,
     but do not permanently blacklist.
   - Keep exclusions for the current run only unless the user asks to persist a
     denylist.
10. The final top 5 free favorites are the best ranked candidates that either
    passed the smoke test or are only blocked by missing provider setup. Never
    include candidates that clearly require a paid subscription/upgrade.
11. Select the latest suitable OpenAI coding/chat model from the `openai`
    provider (exclude image/audio-only, embeddings, search-only, research-only;
    prefer newest flagship by release date and naming).
12. Select the latest suitable Anthropic coding/chat model from the `anthropic`
    provider (exclude legacy variants when a newer equivalent exists; prefer
    newest flagship Opus/Sonnet).
13. Read current favorites from the favorites state file's `.favorite` field.
14. Replace `.favorite` with exactly 7 objects in this order: top 5 free, then
    OpenAI, then Anthropic.
15. Write the updated JSON back.
16. Check which selected free-model providers are already connected/visible.
17. For any selected free model whose provider is not connected/visible, tell the
    user to create the provider account if needed, get the API key/auth, and
    connect it before expecting the favorite to appear.
18. **Report:** the 7 selected models, why, research sources/signals used,
    smoke-test results, which candidates were skipped and why, which provider
    accounts/API keys are required, which selected providers appear missing, and
    whether OpenCode should be restarted for the TUI to reflect the change.
19. If the user asks why a favorite is not visible, explain that OpenCode only
    shows favorites for connected/enabled providers; ask before replacing
    best-overall picks with currently visible alternatives.

## Rules

- Do not modify unrelated OpenCode config.
- The final favorites list must contain exactly 7 entries.
