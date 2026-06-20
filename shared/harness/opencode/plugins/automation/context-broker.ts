import { execFile } from "node:child_process"
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { basename, dirname, isAbsolute, join, resolve } from "node:path"
import { promisify } from "node:util"
import type { Plugin } from "@opencode-ai/plugin"

const execFileAsync = promisify(execFile)

const CONFIG_PATH = join(homedir(), ".config", "opencode", "context-broker.json")
const STATE_DIR = join(homedir(), ".local", "state", "opencode", "context-broker")
const LOG_PATH = join(STATE_DIR, "context-broker.log")
const GRAPH_FILE = join("graphify-out", "graph.json")
const MAX_OUTPUT_CHARS = 2400
const MAX_SEARCH_HITS = 2

type BrokerConfig = {
  enabled: boolean
  openviking: {
    enabled: boolean
    endpoint: string
    scoreThreshold: number
    maxResults: number
  }
  graphify: {
    enabled: boolean
    updateExisting: boolean
    autoInit: boolean
    debounceMs: number
    maxTrackedFiles: number
    workspaceRoots: string[]
    repoRoots: string[]
    trustedAutoInitRoots: string[]
    workspaceGraphMode: "workspace-only" | "disabled"
  }
}

type SearchHit = {
  uri?: string
  abstract?: string
  match_reason?: string
  score?: number
}

type RepoState = {
  root: string
  dirty: boolean
  timer?: NodeJS.Timeout
  lastJobAt?: number
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
  graphify: {
    enabled: true,
    updateExisting: true,
    autoInit: false,
    debounceMs: 45_000,
    maxTrackedFiles: 5000,
    workspaceRoots: [],
    repoRoots: [],
    trustedAutoInitRoots: [],
    workspaceGraphMode: "workspace-only",
  },
}

const STRUCTURE_TERMS = [
  "architecture",
  "call graph",
  "caller",
  "callers",
  "calls",
  "dependency",
  "dependencies",
  "flow",
  "how does",
  "how is",
  "map",
  "path between",
  "relationship",
  "trace",
  "what calls",
  "where is",
  "wired",
  "wiring",
]

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

const repoStates = new Map<string, RepoState>()
const pendingBySession = new Map<string, PendingContext>()
const recentRepos: string[] = []
let graphJobRunning = false
const graphQueue: string[] = []

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

function normalizePath(path: string): string {
  if (path.startsWith("~/")) return join(homedir(), path.slice(2))
  return path
}

function loadConfig(): BrokerConfig {
  try {
    const raw = JSON.parse(readFileSync(CONFIG_PATH, "utf8")) as Partial<BrokerConfig>
    return {
      ...DEFAULT_CONFIG,
      ...raw,
      openviking: { ...DEFAULT_CONFIG.openviking, ...raw.openviking },
      graphify: {
        ...DEFAULT_CONFIG.graphify,
        ...raw.graphify,
        workspaceRoots: (raw.graphify?.workspaceRoots ?? DEFAULT_CONFIG.graphify.workspaceRoots).map(normalizePath),
        repoRoots: (raw.graphify?.repoRoots ?? DEFAULT_CONFIG.graphify.repoRoots).map(normalizePath),
        trustedAutoInitRoots: (raw.graphify?.trustedAutoInitRoots ?? DEFAULT_CONFIG.graphify.trustedAutoInitRoots).map(normalizePath),
      },
    }
  } catch {
    return DEFAULT_CONFIG
  }
}

function clamp(text: string, max = MAX_OUTPUT_CHARS): string {
  const trimmed = text.trim()
  if (trimmed.length <= max) return trimmed
  return `${trimmed.slice(0, max)}\n[truncated]`
}

async function run(command: string, args: string[], cwd: string, timeoutMs: number) {
  return execFileAsync(command, args, {
    cwd,
    timeout: timeoutMs,
    maxBuffer: 16 * 1024 * 1024,
  })
}

async function gitRoot(path: string): Promise<string | null> {
  const cwd = directoryFor(path)
  try {
    const { stdout } = await run("git", ["rev-parse", "--show-toplevel"], cwd, 2500)
    const root = stdout.trim()
    return root || null
  } catch {
    return null
  }
}

function directoryFor(path: string): string {
  try {
    if (existsSync(path) && statSync(path).isDirectory()) return path
  } catch {
    // fall through
  }
  return dirname(path)
}

function under(path: string, root: string): boolean {
  const normalizedPath = resolve(path)
  const normalizedRoot = resolve(root)
  return normalizedPath === normalizedRoot || normalizedPath.startsWith(`${normalizedRoot}/`)
}

function isWorkspaceRoot(repoRoot: string, config: BrokerConfig): boolean {
  return config.graphify.workspaceRoots.some((root) => resolve(root) === resolve(repoRoot))
}

function isTrustedAutoInitRepo(repoRoot: string, config: BrokerConfig): boolean {
  return config.graphify.trustedAutoInitRoots.some((root) => under(repoRoot, root))
}

function graphPath(repoRoot: string): string {
  return join(repoRoot, GRAPH_FILE)
}

function rememberRepo(repoRoot: string) {
  const normalized = resolve(repoRoot)
  const existing = recentRepos.indexOf(normalized)
  if (existing >= 0) recentRepos.splice(existing, 1)
  recentRepos.unshift(normalized)
  recentRepos.splice(6)
}

function collectStrings(value: unknown, out: string[] = [], depth = 0): string[] {
  if (depth > 5 || out.length > 100) return out
  if (typeof value === "string") {
    out.push(value)
    return out
  }
  if (Array.isArray(value)) {
    for (const item of value) collectStrings(item, out, depth + 1)
    return out
  }
  if (value && typeof value === "object") {
    for (const item of Object.values(value as Record<string, unknown>)) collectStrings(item, out, depth + 1)
  }
  return out
}

function candidatePaths(values: string[], baseDirectory: string): string[] {
  const paths = new Set<string>()
  for (const value of values) {
    if (value.length > 1000) continue
    for (const token of value.split(/[\s'"`:,()[\]{}<>]+/)) {
      if (!token) continue
      if (token.startsWith("~/") || token.startsWith("/")) {
        paths.add(normalizePath(token.replace(/[.,;]+$/, "")))
        continue
      }
      if (token.startsWith("./") || token.startsWith("../")) {
        paths.add(resolve(baseDirectory, token.replace(/[.,;]+$/, "")))
      }
    }
  }
  return [...paths]
}

async function resolveReposFromPaths(paths: string[], config: BrokerConfig): Promise<string[]> {
  const repos = new Set<string>()
  for (const path of paths) {
    const repoRootFromWorkspace = repoFromWorkspacePath(path, config)
    if (repoRootFromWorkspace) {
      repos.add(repoRootFromWorkspace)
      continue
    }
    const root = await gitRoot(path)
    if (root) repos.add(root)
  }
  return [...repos]
}

function repoFromWorkspacePath(path: string, config: BrokerConfig): string | null {
  for (const repoRoot of config.graphify.repoRoots) {
    if (!under(path, repoRoot)) continue
    const relative = resolve(path).slice(resolve(repoRoot).length).replace(/^\/+/, "")
    const repoName = relative.split("/")[0]
    if (!repoName) return null
    const candidate = join(repoRoot, repoName)
    if (existsSync(join(candidate, ".git"))) return candidate
  }
  return null
}

function reposMentionedByName(text: string, config: BrokerConfig): string[] {
  const normalized = text.toLowerCase()
  const repos: string[] = []
  for (const repoRoot of config.graphify.repoRoots) {
    let entries: string[] = []
    try {
      entries = readdirSync(repoRoot)
    } catch {
      continue
    }
    for (const entry of entries.slice(0, 300)) {
      const candidate = join(repoRoot, entry)
      if (!existsSync(join(candidate, ".git"))) continue
      const name = entry.toLowerCase()
      if (normalized.includes(name)) repos.push(candidate)
    }
  }
  return repos
}

async function shouldAutoExtract(repoRoot: string, config: BrokerConfig): Promise<boolean> {
  if (!config.graphify.autoInit) return false
  if (!isTrustedAutoInitRepo(repoRoot, config)) return false
  if (isWorkspaceRoot(repoRoot, config) && config.graphify.workspaceGraphMode === "workspace-only") return false
  try {
    const { stdout } = await run("git", ["ls-files"], repoRoot, 15_000)
    const files = stdout.split(/\r?\n/).filter(Boolean)
    return files.length > 0 && files.length <= config.graphify.maxTrackedFiles
  } catch {
    return false
  }
}

async function ensureGraphifyExcluded(repoRoot: string) {
  try {
    const { stdout } = await run("git", ["rev-parse", "--git-path", "info/exclude"], repoRoot, 2500)
    const excludePath = resolve(repoRoot, stdout.trim())
    mkdirSync(dirname(excludePath), { recursive: true })

    let existing = ""
    try {
      existing = readFileSync(excludePath, "utf8")
    } catch {
      // Missing exclude files are expected in freshly initialized repos.
    }

    const ignored = existing
      .split(/\r?\n/)
      .map((line) => line.trim())
      .some((line) => line === "graphify-out" || line === "graphify-out/")
    if (!ignored) writeFileSync(excludePath, `${existing.endsWith("\n") || existing.length === 0 ? "" : "\n"}graphify-out/\n`, { flag: "a" })
  } catch (error: any) {
    log("git exclude update failed", { repoRoot, error: error.message })
  }
}

function scheduleGraphMaintenance(repoRoot: string, config: BrokerConfig) {
  if (!config.enabled || !config.graphify.enabled) return
  rememberRepo(repoRoot)
  const state = repoStates.get(repoRoot) ?? { root: repoRoot, dirty: false }
  state.dirty = true
  if (state.timer) clearTimeout(state.timer)
  state.timer = setTimeout(() => enqueueGraphJob(repoRoot, config), config.graphify.debounceMs)
  repoStates.set(repoRoot, state)
}

function enqueueGraphJob(repoRoot: string, config: BrokerConfig) {
  const state = repoStates.get(repoRoot)
  if (!state?.dirty) return
  state.dirty = false
  if (!graphQueue.includes(repoRoot)) graphQueue.push(repoRoot)
  void drainGraphQueue(config)
}

async function drainGraphQueue(config: BrokerConfig) {
  if (graphJobRunning) return
  graphJobRunning = true
  try {
    while (graphQueue.length > 0) {
      const repoRoot = graphQueue.shift()
      if (!repoRoot) continue
      await maintainGraph(repoRoot, config)
    }
  } finally {
    graphJobRunning = false
  }
}

async function maintainGraph(repoRoot: string, config: BrokerConfig) {
  if (!config.graphify.enabled) return
  await ensureGraphifyExcluded(repoRoot)
  if (existsSync(graphPath(repoRoot))) {
    if (!config.graphify.updateExisting) return
    try {
      log("graphify update started", { repoRoot })
      await run("graphify", ["update", repoRoot], repoRoot, 180_000)
      log("graphify update completed", { repoRoot })
    } catch (error: any) {
      log("graphify update failed", { repoRoot, error: error.message })
    }
    return
  }

  if (!(await shouldAutoExtract(repoRoot, config))) return
  try {
    log("graphify extract started", { repoRoot })
    await run("graphify", ["extract", repoRoot], repoRoot, 600_000)
    log("graphify extract completed", { repoRoot })
  } catch (error: any) {
    log("graphify extract failed", { repoRoot, error: error.message })
  }
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
  } catch {
    return null
  }
}

async function queryGraphify(text: string, repos: string[], config: BrokerConfig): Promise<string | null> {
  if (!config.graphify.enabled) return null
  if (termScore(text, STRUCTURE_TERMS) < 2) return null
  const readyRepos = repos.filter((repoRoot) => existsSync(graphPath(repoRoot))).slice(0, 2)
  if (readyRepos.length === 0) return null
  const sections: string[] = []
  for (const repoRoot of readyRepos) {
    try {
      const { stdout, stderr } = await run("graphify", ["query", text], repoRoot, 120_000)
      const output = clamp(stdout || stderr || "", 1000)
      if (output) sections.push(`### Graphify: ${basename(repoRoot)}\n${output}`)
    } catch (error: any) {
      log("graphify query failed", { repoRoot, error: error.message })
    }
  }
  return sections.length > 0 ? sections.join("\n\n") : null
}

function extractUserText(parts: unknown): string {
  if (!Array.isArray(parts)) return ""
  return parts
    .filter((part: any) => part?.type === "text" && typeof part.text === "string")
    .map((part: any) => part.text)
    .join("\n")
    .trim()
}

async function resolveRelevantRepos(text: string, baseDirectory: string, config: BrokerConfig): Promise<string[]> {
  const paths = candidatePaths([text], baseDirectory)
  const repos = new Set<string>(await resolveReposFromPaths(paths, config))
  for (const repo of reposMentionedByName(text, config)) repos.add(repo)
  for (const repo of recentRepos.slice(0, 2)) repos.add(repo)
  if (repos.size === 0) {
    const root = await gitRoot(baseDirectory)
    if (root) repos.add(root)
  }
  return [...repos]
}

export const ContextBrokerPlugin: Plugin = async ({ directory }) => {
  const config = loadConfig()
  if (!config.enabled) return {}

  return {
    "tool.execute.after": async (input: any, output: any) => {
      const values = collectStrings(input).concat(collectStrings(output))
      const paths = candidatePaths(values, directory)
      if (paths.length === 0 && isAbsolute(directory)) paths.push(directory)
      const repos = await resolveReposFromPaths(paths, config)
      for (const repo of repos) scheduleGraphMaintenance(repo, config)
    },

    "chat.message": async (input: any, output: any) => {
      const sessionId = input?.sessionID
      if (!sessionId) return
      const text = extractUserText(output?.parts)
      if (!text) return

      const repos = await resolveRelevantRepos(text, directory, config)
      for (const repo of repos) scheduleGraphMaintenance(repo, config)

      const [openvikingContext, graphifyContext] = await Promise.all([
        searchOpenViking(text, config),
        queryGraphify(text, repos, config),
      ])
      const sections = [openvikingContext, graphifyContext].filter((section): section is string => Boolean(section))
      if (sections.length === 0) return

      pendingBySession.set(sessionId, {
        text: ["## Retrieved Context", ...sections].join("\n\n"),
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
