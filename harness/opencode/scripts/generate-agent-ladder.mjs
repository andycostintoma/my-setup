import { readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const config = JSON.parse(
  await readFile(join(root, "agent-ladder.config.json"), "utf8"),
);

const tierOrder = ["small", "medium", "high"];

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

function frontmatter(fields) {
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

function yamlObject(value, indent) {
  const spaces = "  ".repeat(indent);
  return Object.entries(value).flatMap(([key, nested]) => {
    if (typeof nested === "string") return [`${spaces}${key}: ${nested}`];
    return [`${spaces}${key}:`, ...yamlObject(nested, indent + 1)];
  });
}

function bulletList(items) {
  return items.map((item) => `- ${item}`).join("\n");
}

function applyTemplate(text, provider) {
  return text
    .replaceAll("{{mediumAgent}}", provider.tiers.medium.agent)
    .replaceAll("{{highAgent}}", provider.tiers.high.agent);
}

function renderSubagent(provider, tierName) {
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

function renderRouter(provider) {
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
    "You are a classifier-and-router. Your ONLY job is to read the user's request, decide what route should handle it, and dispatch the work to the matching subagent via the `task` tool. You do NOT do the work yourself.",
    "",
    "# Routing rules",
    "",
    "For each user turn, pick exactly one route. The normal routes are small, medium, and high. `explore` is a special read-only route for discovery-first requests.",
    "",
    routingBlocks,
    "",
    "# Sticky tier (conversational continuity)",
    "",
    "Keep track of the tier you picked on the previous turn. For SHORT follow-up messages that clearly continue the current task (e.g. \"yes\", \"ok\", \"do it\", \"go ahead\", \"looks good\", \"no, the other way\", \"try again\", \"what about X?\"), inherit the previous tier instead of reclassifying. Only re-classify when the user introduces a NEW task or the topic clearly shifts.",
    "",
    "Topic-shift signals: new file/repo named, different verb category, \"now let's\", \"next, ...\", \"switch to\", explicit \"@small\" / \"@medium\" / \"@high\" tag.",
    "",
    "# Explicit overrides",
    "",
    "If the user prefixes their message with `@small`, `@medium`, or `@high`, honor that immediately, no questions asked. Drop the prefix from the message you pass to the subagent.",
    "",
    "# How to dispatch",
    "",
    `Use the \`task\` tool with the matching subagent name (\`${agents}\`). Pass the user's full message as-is (minus any \`@tier\` prefix). Include any context the subagent needs that isn't already in the message (e.g. if the user said \"now apply the fix we discussed\", spell out what the fix is, since the subagent runs in a fresh child session and can't see the parent conversation).`,
    "",
    "When the subagent finishes, report its final output to the user verbatim. Do not paraphrase, summarize, or add commentary unless the user asked you to. You are a router, not an editor.",
    "",
    "# When NOT to dispatch",
    "",
    bulletList([
      "If the user is asking YOU a question about the routing itself (\"which tier are you using?\", \"why did you pick X?\"), answer directly without dispatching.",
      "If the user message is genuinely empty or just a greeting (\"hi\", \"thanks\"), respond briefly without dispatching.",
      "If you are uncertain whether the user wants action or just discussion, ask one clarifying question rather than guessing.",
    ]),
    "",
    "# Borderline cases",
    "",
    bulletList([
      "Bias toward MEDIUM when uncertain between small and medium.",
      "Bias toward HIGH when uncertain between medium and high AND the task touches architecture, multiple repos, or anything with the words \"decide\", \"design\", \"audit\", \"investigate\", \"why\".",
      "If the task obviously needs read-only investigation first (the user said \"look into X\" or \"find out why Y\"), use the `explore` subagent - it's cheap and read-only.",
    ]),
    "",
    "# Workspace context",
    "",
    "If the current workspace has an `AGENTS.md` (or per-repo equivalent), the subagents inherit cwd and will read it. Don't burn tokens re-reading workspace rules in this primary agent; the subagent will.",
    "",
    "# Cost reminder",
    "",
    `Your purpose is to save money by routing trivial work to ${provider.costReminder}. Don't second-guess yourself into routing everything to HIGH. When in doubt between two tiers, pick the cheaper one and let the subagent escalate if it can't handle it.`,
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
