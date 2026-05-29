import { exec } from "child_process"
import { existsSync } from "fs"
import { homedir } from "os"
import { join } from "path"
import { promisify } from "util"
import type { Plugin } from "@opencode-ai/plugin"

const execAsync = promisify(exec)
const CACHE_TTL_MS = 60 * 1000

let initPromise: Promise<boolean> | null = null
let cachedRepos: string | null = null
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
  if (cachedRepos !== null && now - lastFetchTime < CACHE_TTL_MS) return

  try {
    const { stdout } = await run("ov --output json ls viking://resources/ --abs-limit 2000")
    const items = JSON.parse(stdout)?.result ?? []
    const repos = items
      .filter((item) => item.uri?.startsWith("viking://resources/"))
      .map((item) => {
        const name = item.uri.replace("viking://resources/", "").replace(/\/$/, "")
        return item.abstract ? `- **${name}** (${item.uri})\n  ${item.abstract}` : `- **${name}** (${item.uri})`
      })

    if (repos.length > 0) {
      cachedRepos = repos.join("\n")
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

      cachedRepos = null
      await refresh()
    },

    "experimental.chat.system.transform": (_input, output: any) => {
      if (!cachedRepos) return
      output.system.push(
        "## OpenViking - Indexed Code Repositories\n\n" +
          "The following repos are semantically indexed and searchable.\n" +
          "When the user asks about any of these projects or their internals, " +
          "you MUST proactively load skill(\"openviking\") and use the correct ov commands to search and retrieve content before answering.\n\n" +
          cachedRepos,
      )
    },
  }
}

export default OpenVikingContextPlugin
