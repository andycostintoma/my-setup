import { readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const root = dirname(scriptDir);
const config: AgentLadderConfig = JSON.parse(
  await readFile(join(scriptDir, "agent-ladder.config.json"), "utf8"),
);

type TierName = "small" | "medium" | "high";
type TierConfig = {
  agent: string;
  display: string;
  model: string;
  reasoningEffort: string;
};
type ProviderConfig = {
  label: string;
  routerAgent: string;
  routerModel: string;
  routerReasoningEffort: string;
  descriptionModels: string;
  costReminder: string;
  tiers: Record<TierName, TierConfig>;
};
type AgentLadderConfig = {
  providers: Record<string, ProviderConfig>;
};

const tierOrder: TierName[] = ["small", "medium", "high"];

const tierDescriptions = {
  small: {
    label: "trivial",
    descriptionPrefix: "Cheapest",
    description:
      "Use for trivial edits, one-line changes, simple lookups, formatting tweaks, comment additions, and any task where reasoning depth is irrelevant.",
    routeSummary: "trivial work",
    dispatchedReason: "the task was classified as trivial",
    examples: [
      "Rename a variable or symbol",
      "Fix an obvious typo or formatting issue",
      "Add or update a comment / docstring",
      "Echo a value, list files, run a quick `git status`",
      "Confirm/deny a yes-or-no follow-up",
      "Apply a one-line edit the user described precisely",
    ],
    instruction:
      "Do the task directly. Do not over-engineer. Do not propose alternatives unless the request is genuinely ambiguous. If the task turns out to be larger than expected (you find yourself needing to read many files, refactor across modules, or reason about architecture), STOP and report back to the parent with: \"This is bigger than small-tier. Recommend re-dispatching to {{mediumAgent}} or {{highAgent}}.\"",
  },
  medium: {
    label: "standard coding work",
    descriptionPrefix: "Balanced",
    description:
      "Default for standard coding work - feature implementation, refactoring, multi-file edits within one repo, writing tests, ordinary bug fixes, normal code review, and most everyday task work.",
    routeSummary:
      "standard coding (this is the default if you're unsure between small and medium)",
    dispatchedReason: "the task was classified as standard coding work",
    examples: [
      "Implement a feature within a single repo",
      "Refactor a module or rename across a handful of files",
      "Write or update tests",
      "Fix a non-trivial bug after the cause is roughly known",
      "Apply a code review's suggestions",
      "Update a wiki task page with findings + edits",
      "Generate a PR description from a diff",
      "Anything that needs real reasoning but not deep architecture",
    ],
    instruction:
      "Work efficiently. Don't burn turns on excessive exploration when the task is well-scoped. If the task reveals genuinely architectural complexity (cross-repo refactor, contract change, multi-service coordination, deep debugging that needs hypotheses), STOP and report back: \"This needs high-tier. Recommend re-dispatching to {{highAgent}}.\"",
  },
  high: {
    label: "deep reasoning",
    descriptionPrefix: "Heavy-reasoning",
    description:
      "Use for architecture decisions, cross-repo or cross-service refactors, tricky multi-hypothesis debugging, design reviews, ADR drafting, and anything where deep thinking measurably pays for itself.",
    routeSummary: "heavy reasoning",
    dispatchedReason: "the task requires deep reasoning",
    examples: [
      "Design a new service, RPC contract, or schema",
      "Cross-repo refactor touching multiple repos",
      "Debugging where the failure mode isn't obvious and needs multiple hypotheses",
      "Architectural review / ADR drafting",
      "Reconciling contradictory wiki claims or proposing decisions",
      "Performance investigation with multiple suspect dimensions",
      "Anything that benefits from careful multi-step reasoning",
    ],
    instruction:
      "Think hard before acting. Lay out hypotheses, weigh trade-offs, propose ADRs when warranted. If the task turns out to be simpler than classified, just do it - don't artificially inflate the work, but don't down-shift to a different agent either (you're already here).",
  },
};

const routerExamples = {
  small: [
    "Rename a variable / fix a typo / format a file",
    "Add or update a comment or docstring",
    "Apply a one-line edit the user described precisely",
    "Run a single quick command (`git status`, `ls`, etc.) and report back",
    "Confirm/deny a yes-or-no follow-up",
  ],
  medium: [
    "Implement a feature inside one repo",
    "Refactor a module / rename across a handful of files",
    "Write or update tests",
    "Fix a non-trivial bug after the cause is roughly known",
    "Update a wiki task page with findings + edits",
    "Generate a PR description from a diff",
    "Code review or applying review feedback",
  ],
  high: [
    "Design a new service, RPC contract, or schema",
    "Cross-repo refactor touching multiple repos",
    "Debugging where the failure mode isn't obvious",
    "Architectural review / ADR drafting",
    "Reconciling contradictory wiki claims",
    "Performance investigation across multiple dimensions",
    "Anything where the user explicitly asks for deep analysis or planning",
  ],
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

function applyTemplate(text: string, provider: ProviderConfig) {
  return text
    .replaceAll("{{mediumAgent}}", provider.tiers.medium.agent)
    .replaceAll("{{highAgent}}", provider.tiers.high.agent);
}

function renderSubagent(provider: ProviderConfig, tierName: TierName) {
  const tier = provider.tiers[tierName];
  const spec = tierDescriptions[tierName];
  const providerLabel = `${provider.label} tier (${tier.display})`;

  const body = [
    `You are the ${tierName} tier of the ${provider.label} auto-router ladder.`,
    "",
    `You were dispatched by \`${provider.routerAgent}\` because ${spec.dispatchedReason}. Examples of what fits here:`,
    "",
    bulletList(spec.examples),
    "",
    applyTemplate(spec.instruction, provider),
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
    "\"general\"": "allow",
    "\"scout\"": "allow",
    "\"code-reviewer\"": "allow",
    "\"security-reviewer\"": "allow",
    "\"tech-lead\"": "allow",
  };

  const routingBlocks = tierOrder
    .map((tierName) => {
      const tier = provider.tiers[tierName];
      const spec = tierDescriptions[tierName];
      const examples = routerExamples[tierName];
      return [
        `**${tierName.toUpperCase()} -> \`${tier.agent}\` (${tier.display})** - ${spec.routeSummary}:`,
        bulletList(examples),
      ].join("\n");
    })
    .join("\n\n");

  const agents = tierOrder.map((tierName) => provider.tiers[tierName].agent).join("` / `");

  const body = [
    "You are a classifier/router. Do not implement the request yourself; choose one route and call the matching subagent with the `task` tool.",
    "",
    "# Routes",
    "",
    "Pick exactly one route. `explore` is for discovery-first read-only work.",
    "",
    routingBlocks,
    "",
    "# Rules",
    "",
    bulletList([
      "Short follow-ups that clearly continue the prior task inherit the previous tier; reclassify only on topic shift or explicit `@small`, `@medium`, or `@high`.",
      "Honor explicit tier prefixes and omit the prefix from the subagent prompt.",
      "Bias to MEDIUM when unsure between small and medium; bias to HIGH for architecture, cross-repo work, ambiguous debugging, audits, investigations, design, or explicit deep analysis.",
      `Dispatch with one of: \`${agents}\`. Pass the user's request, plus any missing context needed because subagents start fresh.`,
      "After the subagent finishes, report its final output verbatim unless the user asked for a summary.",
      "Answer routing questions, greetings, and genuinely ambiguous action-vs-discussion turns directly instead of dispatching.",
    ]),
    "",
    `Cost goal: route cheap work to ${provider.costReminder}; let subagents escalate if needed. Subagents inherit cwd and should read workspace rules themselves.`,
    "",
  ].join("\n");

  return frontmatter([
    [
      "description",
      `Auto-routing build agent (${provider.label} ladder). Classifies each task into small/medium/high and dispatches to the matching ${provider.label} subagent (${provider.descriptionModels}). Use when you want cost-aware routing across ${provider.label} models without manually picking a tier.`,
    ],
    ["mode", "primary"],
    ["model", provider.routerModel],
    ["temperature", "0.1"],
    ["reasoningEffort", provider.routerReasoningEffort],
    [
      "permission",
      {
        edit: "deny",
        bash: "deny",
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
