import { exec } from "child_process"
import { existsSync } from "fs"
import { homedir } from "os"
import { join } from "path"
import { promisify } from "util"
import type { Plugin } from "@opencode-ai/plugin"

const execAsync = promisify(exec)
const CACHE_TTL_MS = 60 * 1000
const MAX_REPO_NAMES = 120

let initPromise: Promise<boolean> | null = null
let cachedRepoSummary: string | null = null
let lastFetchTime = 0

async function run(cmd: string, opts: { timeout?: number } = {}) {
  return execAsync(cmd, { timeout: 10_000, ...opts })
}

function showToast(client: any, message: string, variant: "warning" | "error" = "warning") {
  if (!client?.tui?.showToast) return

  client.tui
    .showToast({
      body: { title: "OpenViking", message, variant, duration: 8000 },
    })
    .catch(() => {})
}

async function isHealthy() {
  try {
    await run("ov health", { timeout: 3000 })
    return true
  } catch {
    return false
  }
}

async function startServer() {
  await run("openviking-server > /tmp/openviking.log 2>&1 &")
  for (let i = 0; i < 10; i++) {
    await new Promise((resolve) => setTimeout(resolve, 3000))
    if (await isHealthy()) return true
  }
  return false
}

async function init(client: any): Promise<boolean> {
  if (!initPromise) {
    initPromise = (async () => {
      if (await isHealthy()) return true

      try {
        await run("command -v ov", { timeout: 2000 })
      } catch {
        showToast(client, "openviking is not installed", "error")
        return false
      }

      if (!existsSync(join(homedir(), ".openviking", "ov.conf"))) {
        showToast(client, "~/.openviking/ov.conf not found", "warning")
        return false
      }

      if (!(await startServer())) {
        showToast(client, "Failed to start openviking server. Check /tmp/openviking.log", "error")
        return false
      }

      return true
    })().finally(() => {
      initPromise = null
    })
  }

  return initPromise
}

async function loadRepos() {
  const now = Date.now()
  if (cachedRepoSummary !== null && now - lastFetchTime < CACHE_TTL_MS) return

  try {
    const { stdout } = await run("ov ls viking://resources/ --simple --node-limit 2000")
    const repoNames = stdout
      .split(/\r?\n/)
      .map((line) => line.trim().split(/\s+/)[0])
      .filter((uri) => uri.startsWith("viking://resources/"))
      .map((uri) => uri.replace("viking://resources/", "").replace(/\/$/, ""))
      .filter(Boolean)
      .sort()

    if (repoNames.length > 0) {
      const listed = repoNames.slice(0, MAX_REPO_NAMES)
      const omitted = repoNames.length - listed.length
      cachedRepoSummary =
        `Indexed repositories (${repoNames.length} total, names only): ${listed.join(", ")}` +
        (omitted > 0 ? `, and ${omitted} more` : "")
      lastFetchTime = now
    }
  } catch {
    // Keep OpenCode startup independent from OpenViking availability.
  }
}

export const OpenVikingContextPlugin: Plugin = async ({ client }) => {
  async function refresh() {
    if (await init(client)) await loadRepos()
  }

  Promise.resolve().then(refresh).catch(() => {})

  return {
    event: async ({ event }: any) => {
      if (event?.type !== "session.created") return

      cachedRepoSummary = null
      await refresh()
    },

    "experimental.chat.system.transform": (_input, output: any) => {
      if (!cachedRepoSummary) return
      output.system.push(
        "## OpenViking - Indexed Code Repositories\n\n" +
          "OpenViking provides semantic search and retrieval for external/reference repositories. " +
          "When the user asks about one of these projects, external repository internals, or prior indexed resources, " +
          "load skill(\"openviking\") and search OpenViking before answering.\n\n" +
          cachedRepoSummary,
      )
    },
  }
}

export default OpenVikingContextPlugin
