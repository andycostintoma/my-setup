import type { Plugin } from "@opencode-ai/plugin"

/**
 * Auto-recall plugin for OpenViking memories.
 *
 * Strategy: per session, on the first user message, decide whether to query
 * OpenViking. If the message has signals suggesting prior context would help
 * (or if it's short/ambiguous), search the user's `preferences` and `entities`
 * directories — these hold stable facts. Skip `events` (activity-log noise).
 *
 * If results clear the score threshold, append a compact "Relevant prior
 * context" block to the system prompt for that session. Cache the decision so
 * we never query twice for the same session.
 *
 * Fail-silent: any HTTP error or unexpected response is swallowed.
 */

const OPENVIKING_ENDPOINT = process.env.OPENVIKING_ENDPOINT || "http://localhost:1933"
const SCORE_THRESHOLD = 0.55
const MAX_RESULTS = 3
const SCOPED_URIS = [
  "viking://user/default/memories/preferences",
  "viking://user/default/memories/entities",
]

const RECALL_TRIGGER_RE =
  /\b(previously|earlier|last time|before|remember|continue|resume|the (one|thing|file|service|repo|project) (we|i)|why (did|does|is|was)|what (was|did) we|how did we)\b/i

type RecallState = {
  injected: boolean
  context: string | null
}

type SearchHit = { uri: string; abstract?: string; score: number }
type SearchResponse = {
  status?: string
  result?: { memories?: SearchHit[] }
}

const sessionState = new Map<string, RecallState>()

function shouldRecall(message: string): boolean {
  const trimmed = message.trim()
  if (trimmed.length === 0) return false
  if (trimmed.length < 40) return true
  if (RECALL_TRIGGER_RE.test(trimmed)) return true
  return false
}

async function search(query: string, targetUri: string): Promise<SearchHit[]> {
  try {
    const res = await fetch(`${OPENVIKING_ENDPOINT}/api/v1/search/find`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        query,
        target_uri: targetUri,
        limit: MAX_RESULTS,
        score_threshold: SCORE_THRESHOLD,
      }),
      signal: AbortSignal.timeout(2000),
    })
    if (!res.ok) return []
    const data = (await res.json()) as SearchResponse
    return data.result?.memories ?? []
  } catch {
    return []
  }
}

function formatHits(hits: SearchHit[]): string | null {
  const lines: string[] = []
  for (const hit of hits) {
    const abstract = hit.abstract?.trim()
    if (!abstract) continue
    const oneLine = abstract.replace(/\s+/g, " ").slice(0, 200)
    lines.push(`- ${oneLine}`)
  }
  if (lines.length === 0) return null
  return ["## Relevant prior context", "", ...lines].join("\n")
}

export const AutoRecallPlugin: Plugin = async () => {
  return {
    "chat.message": async (input, output) => {
      const sessionId = input.sessionID
      if (sessionState.has(sessionId)) return

      const text = output.parts
        .filter((p): p is { type: "text"; text: string } => p.type === "text")
        .map((p) => p.text)
        .join("\n")

      if (!shouldRecall(text)) {
        sessionState.set(sessionId, { injected: false, context: null })
        return
      }

      const hitArrays = await Promise.all(SCOPED_URIS.map((uri) => search(text, uri)))
      const hits = hitArrays
        .flat()
        .sort((a, b) => b.score - a.score)
        .slice(0, MAX_RESULTS)

      const context = formatHits(hits)
      sessionState.set(sessionId, { injected: false, context })
    },

    "experimental.chat.system.transform": async (input, output) => {
      const sessionId = input.sessionID
      if (!sessionId) return
      const state = sessionState.get(sessionId)
      if (!state || state.injected || !state.context) return

      output.system.push(state.context)
      state.injected = true
    },
  }
}

export default AutoRecallPlugin
