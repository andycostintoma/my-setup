import type { Plugin } from "@opencode-ai/plugin"

const AUTO_EXPLORE_ENABLED = process.env.OPENCODE_AUTO_EXPLORE !== "0"
const MAX_PROMPT_CHARS = 4000
const MIN_COOLDOWN_MS = 25_000

const SEARCHY_RE =
  /\b(where is|where does|find|locate|search|ripgrep|rg\b|grep\b|which file|entrypoint|trace|follow|map out|architecture|how does|how is|what calls|who calls|references|usages?)\b/i

type SessionExploreState = {
  lastRunAtMs: number
}

const sessionState = new Map<string, SessionExploreState>()

function extractUserText(parts: unknown[]): string {
  if (!Array.isArray(parts)) return ""
  return parts
    .filter((p: any) => p && p.type === "text" && typeof p.text === "string")
    .map((p: any) => p.text)
    .join("\n")
    .trim()
}

export const AutoExplorePlugin: Plugin = async ({ client }) => {
  return {
    "chat.message": async (input, output) => {
      if (!AUTO_EXPLORE_ENABLED) return

      const sessionId = input.sessionID
      if (!sessionId) return

      const text = extractUserText((output as any).parts)
      if (!text) return
      if (!SEARCHY_RE.test(text)) return

      const now = Date.now()
      const prior = sessionState.get(sessionId)
      if (prior && now-prior.lastRunAtMs < MIN_COOLDOWN_MS) return
      sessionState.set(sessionId, { lastRunAtMs: now })

      const prompt = text.length > MAX_PROMPT_CHARS ? `${text.slice(0, MAX_PROMPT_CHARS)}…` : text

      try {
        const res = await client.task.create({
          body: {
            description: "Auto explore",
            subagent_type: "explore",
            prompt: `Thoroughness: quick\n\nUser request:\n${prompt}\n\nReturn a tight answer with: (1) key files/paths, (2) key symbols/functions, (3) next actionable step.`
          }
        })

        if (res?.task_id) {
          ;(output as any).message += `\n\n[auto-explore started: ${res.task_id}]`
        }
      } catch {
        // fail silent
      }
    },
  }
}

export default AutoExplorePlugin
