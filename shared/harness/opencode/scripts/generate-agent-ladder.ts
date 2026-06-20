import { readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const root = dirname(scriptDir);
const config: AgentLadderConfig = JSON.parse(
  await readFile(join(scriptDir, "agent-ladder.config.json"), "utf8"),
);

type TierName = "low" | "medium" | "strong";
type TierConfig = {
  agent: string;
  display: string;
  model: string;
  reasoningEffort?: string;
};
type ProviderConfig = {
  label: string;
  routerAgent: string;
  routerModel?: string;
  routerReasoningEffort?: string;
  descriptionModels: string;
  tiers: Record<TierName, TierConfig>;
};
type AgentLadderConfig = {
  providers: Record<string, ProviderConfig>;
};

const tierOrder: TierName[] = ["low", "medium", "strong"];

const tierDescriptions = {
  low: {
    label: "bounded low-cost work",
    descriptionPrefix: "Low-cost",
    description:
      "Use for trivial edits, one-line changes, simple lookups, formatting tweaks, log reduction, and tightly scoped mechanical tasks where reasoning depth is irrelevant.",
    dispatchedReason: "the frontier orchestrator identified bounded low-cost work",
    examples: [
      "Rename a variable or symbol",
      "Fix an obvious typo or formatting issue",
      "Add or update a comment / docstring",
      "Run a quick command and summarize the result",
      "Reduce a long log or test output to relevant failures",
      "Apply a one-line edit the user described precisely",
    ],
    instruction:
      "Do only the bounded task assigned by the parent. Do not over-engineer, broaden scope, or propose alternatives unless the prompt is genuinely ambiguous. If the task turns out to require multi-file reasoning, architecture, or broad investigation, STOP and report that it exceeds low-tier scope.",
  },
  medium: {
    label: "standard coding work",
    descriptionPrefix: "Balanced",
    description:
      "Use for standard bounded coding work, repo exploration, tests, ordinary bug fixes, and implementation slices where the frontier orchestrator owns the final decision.",
    dispatchedReason: "the frontier orchestrator identified standard bounded work",
    examples: [
      "Implement a feature slice within a single repo",
      "Refactor a module or rename across a handful of files",
      "Write or update tests",
      "Fix a non-trivial bug after the cause is roughly known",
      "Explore a subsystem and return concrete file/function evidence",
      "Apply a clearly scoped code review suggestion",
      "Run a verification pass and report failures with causes",
    ],
    instruction:
      "Work efficiently within the assigned boundary. Do not make architecture decisions, expand across unrelated files, or coordinate other agents. If the task reveals a contract change, cross-repo impact, ambiguous debugging, or design trade-off, STOP and report that it needs frontier judgment.",
  },
  strong: {
    label: "strong worker",
    descriptionPrefix: "Strong",
    description:
      "Use for difficult bounded implementation, deep investigation slices, design review support, and high-stakes checks under frontier orchestration.",
    dispatchedReason: "the frontier orchestrator identified a difficult bounded slice",
    examples: [
      "Investigate a tricky failure mode within a bounded subsystem",
      "Implement a complex but already-decided change",
      "Compare design options and return trade-offs for the parent to decide",
      "Review a risky diff or migration plan with concrete evidence",
      "Analyze performance or correctness across multiple suspect dimensions",
      "Reconcile conflicting evidence without making the final call",
    ],
    instruction:
      "Think carefully, but stay a worker. Do not become the overall boss, call other agents, or make irreversible architecture/API/product decisions unless the parent explicitly delegated that decision. Return evidence, options, risks, and a recommendation for the frontier orchestrator to judge.",
  },
};

function frontmatter(fields: [string, string | Record<string, any> | undefined][]) {
  return [
    "---",
    ...fields.flatMap(([key, value]) => {
      if (value === undefined) return [];
      if (typeof value === "string") return [`${key}: ${value}`];
      if (typeof value === "object") return [`${key}:`, ...yamlObject(value, 1)];
      return [];
    }),
    "---",
    "",
  ].join("\n") + "\n";
}

function yamlObject(value: Record<string, any>, indent: number): string[] {
  const spaces = "  ".repeat(indent);
  return Object.entries(value).flatMap(([key, nested]) => {
    if (typeof nested === "string") return [`${spaces}${key}: ${nested}`];
    return [`${spaces}${key}:`, ...yamlObject(nested, indent + 1)];
  });
}

function bulletList(items: string[]) {
  return items.map((item) => `- ${item}`).join("\n");
}

function renderSubagent(provider: ProviderConfig, tierName: TierName) {
  const tier = provider.tiers[tierName];
  const spec = tierDescriptions[tierName];
  const providerLabel = `${provider.label} worker (${tier.display})`;

  const body = [
    `You are the ${tierName} worker in the ${provider.label} efficient-frontier ladder.`,
    "",
    `You were dispatched by \`${provider.routerAgent}\` because ${spec.dispatchedReason}. Examples of work that fits here:`,
    "",
    bulletList(spec.examples),
    "",
    spec.instruction,
    "",
    "# Working Contract",
    "",
    bulletList([
      "Treat the parent prompt as the complete assignment. Ask for clarification only if required to avoid an unsafe or wrong change.",
      "Respect explicit scope and out-of-scope boundaries. Do not inspect or edit unrelated areas just because they are nearby.",
      "Do not call other subagents or attempt to hand work back through another task call.",
      "Avoid editing files that the parent says another agent may edit concurrently.",
      "Run only verification that is relevant to your assigned slice, unless the parent provided a broader command.",
    ]),
    "",
    "# Return Format",
    "",
    "Return a compact handoff with:",
    "",
    bulletList([
      "Outcome: what you did or found",
      "Evidence: files, functions, line references, command results, or logs that support it",
      "Files changed: exact paths, or `none`",
      "Verification: commands run and pass/fail status, or why not run",
      "Uncertainty: assumptions, risks, disagreements, or follow-up needed",
      "Stop condition: confirm the bounded assignment is complete, or state why you stopped",
    ]),
    "",
    "Follow any `AGENTS.md` (or per-repo equivalent) rules present in the current workspace.",
    "",
  ].join("\n");

  return frontmatter([
    [
      "description",
      `${spec.descriptionPrefix} ${providerLabel}. ${spec.description}`,
    ],
    ["mode", "subagent"],
    ["model", tier.model],
    ["temperature", "0.2"],
    ["reasoningEffort", tier.reasoningEffort],
    [
      "permission",
      {
        edit: "allow",
        bash: "allow",
        webfetch: "allow",
        websearch: "allow",
        task: {
          "\"*\"": "deny",
        },
      },
    ],
  ]) + body;
}

function renderRouter(provider: ProviderConfig) {
  const taskPermissions = {
    "\"*\"": "deny",
    ...Object.fromEntries(
      tierOrder.map((tierName) => [`\"${provider.tiers[tierName].agent}\"`, "allow"]),
    ),
    "\"explore\"": "allow",
  };

  const workerBlocks = tierOrder
    .map((tierName) => {
      const tier = provider.tiers[tierName];
      const spec = tierDescriptions[tierName];
      return [
        `**${tierName.toUpperCase()} -> \`${tier.agent}\` (${tier.display})**`,
        spec.description,
        "",
        bulletList(spec.examples),
      ].join("\n");
    })
    .join("\n\n");

  const agents = tierOrder.map((tierName) => provider.tiers[tierName].agent).join("` / `");

  const body = [
    `You are the ${provider.label} efficient-frontier orchestrator. You are the architect, integrator, final judge, and user-facing owner of the work.`,
    "",
    "Use the current primary model selected by OpenCode as the frontier model; do not assume a specific frontier model ID. Delegate bounded, token-heavy, or parallelizable slices to workers when that improves quality or cost, but keep final responsibility centralized.",
    "",
    "# Worker Agents",
    "",
    `Workers available through the \`task\` tool: same-provider \`${agents}\`, plus OpenCode native \`explore\` for read-only discovery.`,
    "",
    workerBlocks,
    "",
    "# Orchestration Rules",
    "",
    bulletList([
      "First identify frontier-only work: architecture, cross-file integration, ambiguous trade-offs, final edits, conflict resolution, and final user communication stay with you.",
      "Delegate only bounded work: repo scans, evidence gathering, log reduction, tests, narrow implementation slices, review passes, and mechanical edits with clear ownership.",
      "Keep tiny, tightly coupled, or high-context work local rather than adding coordination overhead.",
      "Spawn independent subagents in parallel when useful, but never assign multiple agents to edit the same files concurrently.",
      "Do not call yourself, another frontier/high-cost boss, or recursive orchestrators. Workers are helpers, not alternate owners.",
      "Treat subagent output as leads. Reopen cited files, inspect high-risk diffs, resolve disagreements centrally, and rerun or spot-check important verification before finalizing.",
      "Do not claim universal cost or quality savings. Use delegation only when it is plausibly beneficial for this task.",
      "If the user is only asking a question, brainstorming, greeting, or asking for a plan, answer directly unless delegation is genuinely needed for evidence.",
    ]),
    "",
    "# Handoff Packets",
    "",
    "Every subagent prompt must be self-contained and include:",
    "",
    bulletList([
      "Repo/workspace path and relevant current context",
      "Objective and expected deliverable",
      "Scope and explicit out-of-scope boundaries",
      "Files, directories, commands, or symbols to inspect when known",
      "Whether edits are allowed and which files are reserved for the worker",
      "Required evidence and verification commands",
      "Stop conditions and escalation criteria",
      "Compact return format: outcome, evidence, files changed, verification, uncertainty, stop condition",
    ]),
    "",
    "# Completion",
    "",
    bulletList([
      "Integrate worker results into a single coherent solution; do not paste raw worker transcripts unless useful.",
      "Own all final claims. If you cannot verify something important, say so clearly.",
      "Follow any `AGENTS.md` (or per-repo equivalent) rules present in the current workspace.",
    ]),
    "",
  ].join("\n");

  return frontmatter([
    [
      "description",
      `Efficient-frontier build orchestrator (${provider.label} ladder). Uses the current primary model as frontier owner and delegates bounded work to low/medium/strong ${provider.label} workers (${provider.descriptionModels}) when useful.`,
    ],
    ["mode", "primary"],
    ["model", provider.routerModel],
    ["temperature", "0.1"],
    ["reasoningEffort", provider.routerReasoningEffort],
    [
      "permission",
      {
        edit: "allow",
        bash: "allow",
        webfetch: "allow",
        websearch: "allow",
        read: "allow",
        glob: "allow",
        grep: "allow",
        list: "allow",
        task: taskPermissions,
      },
    ],
  ]) + body;
}

for (const provider of Object.values(config.providers)) {
  await writeFile(
    join(root, "agents", `${provider.routerAgent}.md`),
    renderRouter(provider),
  );

  for (const tierName of tierOrder) {
    const tier = provider.tiers[tierName];
    await writeFile(join(root, "agents", `${tier.agent}.md`), renderSubagent(provider, tierName));
  }
}
