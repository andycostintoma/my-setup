import { readFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"
import type { Plugin } from "@opencode-ai/plugin"

const SECRETS_PATH = join(homedir(), "medidrive", ".secrets.env")

function parseDotenv(text: string): Record<string, string> {
  const out: Record<string, string> = {}
  for (const rawLine of text.split("\n")) {
    const line = rawLine.trim()
    if (!line || line.startsWith("#")) continue
    const eq = line.indexOf("=")
    if (eq < 0) continue
    const key = line.slice(0, eq).trim().replace(/^export\s+/, "")
    let val = line.slice(eq + 1).trim()
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1)
    }
    out[key] = val
  }
  return out
}

function loadSecrets(): Record<string, string> {
  try {
    return parseDotenv(readFileSync(SECRETS_PATH, "utf8"))
  } catch {
    return {}
  }
}

export default (async () => {
  return {
    config: (cfg: any) => {
      const secrets = loadSecrets()
      const mcp = cfg?.mcp
      if (!mcp || typeof mcp !== "object") return

      const postmanKey = secrets["POSTMAN_API_KEY"]
      if (mcp.postman && mcp.postman.type === "local") {
        if (postmanKey) {
          mcp.postman.env = {
            ...(mcp.postman.env ?? {}),
            POSTMAN_API_KEY: postmanKey,
          }
        } else {
          mcp.postman.enabled = false
        }
      }

      const linearKey = secrets["LINEAR_API_KEY"]
      if (mcp.linear && mcp.linear.type === "remote") {
        if (linearKey) {
          mcp.linear.headers = {
            ...(mcp.linear.headers ?? {}),
            Authorization: `Bearer ${linearKey}`,
          }
        } else {
          mcp.linear.enabled = false
        }
      }

      const notionToken = secrets["NOTION_TOKEN"]
      if (mcp.notion && mcp.notion.type === "local") {
        if (notionToken) {
          mcp.notion.env = {
            ...(mcp.notion.env ?? {}),
            NOTION_TOKEN: notionToken,
          }
        } else {
          mcp.notion.enabled = false
        }
      }
    },
  }
}) satisfies Plugin
