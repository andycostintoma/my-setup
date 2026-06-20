import { tool } from "@opencode-ai/plugin/tool"
import { execFile } from "node:child_process"
import { existsSync } from "node:fs"
import { join } from "node:path"

const MAX_OUTPUT = 30_000

type RunResult = { ok: true; output: string } | { ok: false; error: string }

function graphPath(directory: string): string {
  return join(directory, "graphify-out", "graph.json")
}

function ensureGraph(directory: string): string | null {
  const graph = graphPath(directory)
  if (!existsSync(graph)) {
    return `No knowledge graph found at ${graph}. Build one first with \`graphify extract .\` (or run /graphify), then retry.`
  }
  return null
}

function runGraphify(args: string[], directory: string): Promise<RunResult> {
  return new Promise((resolve) => {
    execFile(
      "graphify",
      args,
      { cwd: directory, timeout: 120_000, maxBuffer: 16 * 1024 * 1024 },
      (err, stdout, stderr) => {
        const out = (stdout || "").trim()
        const errOut = (stderr || "").trim()
        if (err) {
          resolve({
            ok: false,
            error: errOut || out || (err as Error).message || "graphify failed",
          })
          return
        }
        resolve({ ok: true, output: out || errOut || "(no output)" })
      },
    )
  })
}

function clamp(text: string): string {
  if (text.length <= MAX_OUTPUT) return text
  return text.slice(0, MAX_OUTPUT) + "\n\n[... output truncated ...]"
}

export const query = tool({
  description:
    "Ask a natural-language question about the CURRENT repo's structure using the graphify knowledge graph (BFS traversal over graphify-out/graph.json). Use for relationship/architecture/'how does X connect to Y' questions about THIS repo. For external/reference repos use OpenViking instead.",
  args: {
    question: tool.schema
      .string()
      .describe("Natural-language question, e.g. 'how does auth connect to the database layer?'"),
  },
  async execute(args, context) {
    const missing = ensureGraph(context.directory)
    if (missing) return missing
    const result = await runGraphify(["query", args.question], context.directory)
    if (!result.ok) return `graphify query failed: ${result.error}`
    return clamp(result.output)
  },
})

export const path = tool({
  description:
    "Find the shortest dependency/relationship path between two nodes (functions, types, files, modules) in the current repo's graphify knowledge graph.",
  args: {
    from: tool.schema.string().describe("Source node name, e.g. a function, type, or file"),
    to: tool.schema.string().describe("Target node name"),
  },
  async execute(args, context) {
    const missing = ensureGraph(context.directory)
    if (missing) return missing
    const result = await runGraphify(["path", args.from, args.to], context.directory)
    if (!result.ok) return `graphify path failed: ${result.error}`
    return clamp(result.output)
  },
})

export const explain = tool({
  description:
    "Plain-language explanation of a single node and its neighbors in the current repo's graphify knowledge graph. Use to understand what a function/type/module is and what it touches.",
  args: {
    node: tool.schema.string().describe("Node name to explain, e.g. a function, type, file, or module"),
  },
  async execute(args, context) {
    const missing = ensureGraph(context.directory)
    if (missing) return missing
    const result = await runGraphify(["explain", args.node], context.directory)
    if (!result.ok) return `graphify explain failed: ${result.error}`
    return clamp(result.output)
  },
})
