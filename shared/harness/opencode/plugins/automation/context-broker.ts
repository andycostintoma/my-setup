import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"
import type { Plugin } from "@opencode-ai/plugin"

const CONFIG_PATH = join(homedir(), ".config", "opencode", "context-broker.json")
const STATE_DIR = join(homedir(), ".local", "state", "opencode", "context-broker")
const LOG_PATH = join(STATE_DIR, "context-broker.log")
const MAX_SEARCH_HITS = 2

type BrokerConfig = {
  enabled: boolean
  openviking: {
    enabled: boolean
    endpoint: string
    scoreThreshold: number
    maxResults: number
  }
}

type SearchHit = {
  uri?: string
  abstract?: string
  match_reason?: string
  score?: number
}

type PendingContext = {
  text: string
  createdAt: number
}

const DEFAULT_CONFIG: BrokerConfig = {
  enabled: true,
  openviking: {
    enabled: true,
    endpoint: process.env.OPENVIKING_ENDPOINT || "http://127.0.0.1:1933",
    scoreThreshold: 0.72,
    maxResults: MAX_SEARCH_HITS,
  },
}

const OPENVIKING_TERMS = [
  "before",
  "cross repo",
  "cross-repo",
  "earlier",
  "external repo",
  "historical",
  "history",
  "indexed repo",
  "last time",
  "memory",
  "other repo",
  "previous",
  "previously",
  "prior",
  "reference repo",
  "remember",
  "similar service",
]

const pendingBySession = new Map<string, PendingContext>()

function log(message: string, meta: Record<string, unknown> = {}) {
  try {
    mkdirSync(STATE_DIR, { recursive: true })
    writeFileSync(LOG_PATH, `${new Date().toISOString()} ${message} ${JSON.stringify(meta)}\n`, {
      flag: "a",
    })
  } catch {
    // Keep the broker invisible if local state is unavailable.
  }
}

function loadConfig(): BrokerConfig {
  try {
    const raw = JSON.parse(readFileSync(CONFIG_PATH, "utf8")) as Partial<BrokerConfig>
    return {
      ...DEFAULT_CONFIG,
      ...raw,
      openviking: { ...DEFAULT_CONFIG.openviking, ...raw.openviking },
    }
  } catch {
    return DEFAULT_CONFIG
  }
}

function clamp(text: string, max = 2400): string {
  const trimmed = text.trim()
  if (trimmed.length <= max) return trimmed
  return `${trimmed.slice(0, max)}\n[truncated]`
}

function termScore(text: string, terms: string[]): number {
  const normalized = text.toLowerCase()
  let score = 0
  for (const term of terms) {
    if (normalized.includes(term)) score += term.includes(" ") ? 2 : 1
  }
  return score
}

async function searchOpenViking(text: string, config: BrokerConfig): Promise<string | null> {
  if (!config.openviking.enabled) return null
  if (termScore(text, OPENVIKING_TERMS) < 2) return null
  try {
    const res = await fetch(`${config.openviking.endpoint}/api/v1/search/find`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        query: text,
        limit: config.openviking.maxResults,
        score_threshold: config.openviking.scoreThreshold,
      }),
      signal: AbortSignal.timeout(2500),
    })
    if (!res.ok) return null
    const data = (await res.json()) as any
    const result = data.result ?? data
    const hits: SearchHit[] = [
      ...(result.memories ?? []),
      ...(result.resources ?? []),
      ...(result.skills ?? []),
    ]
      .filter((hit: SearchHit) => (hit.score ?? 0) >= config.openviking.scoreThreshold)
      .slice(0, config.openviking.maxResults)
    if (hits.length === 0) return null
    return [
      "### OpenViking",
      ...hits.map((hit) => {
        const label = hit.uri ? ` (${hit.uri})` : ""
        const body = clamp(hit.abstract || hit.match_reason || "", 360)
        return `- ${body}${label}`
      }),
    ].join("\n")
  } catch (error: any) {
    log("openviking search failed", { error: error.message })
    return null
  }
}

function extractUserText(parts: unknown): string {
  if (!Array.isArray(parts)) return ""
  return parts
    .filter((part: any) => part?.type === "text" && typeof part.text === "string")
    .map((part: any) => part.text)
    .join("\n")
    .trim()
}

export const ContextBrokerPlugin: Plugin = async () => {
  const config = loadConfig()
  if (!config.enabled) return {}

  return {
    "chat.message": async (input: any, output: any) => {
      const sessionId = input?.sessionID
      if (!sessionId) return
      const text = extractUserText(output?.parts)
      if (!text) return

      const context = await searchOpenViking(text, config)
      if (!context) return

      pendingBySession.set(sessionId, {
        text: ["## Retrieved Context", context].join("\n\n"),
        createdAt: Date.now(),
      })
    },

    "experimental.chat.system.transform": (input: any, output: any) => {
      const sessionId = input?.sessionID
      if (!sessionId) return
      const pending = pendingBySession.get(sessionId)
      if (!pending) return
      pendingBySession.delete(sessionId)
      if (Date.now() - pending.createdAt > 30_000) return
      output.system.push(pending.text)
    },
  }
}

export default ContextBrokerPlugin
