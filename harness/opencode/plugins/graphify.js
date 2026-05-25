// graphify OpenCode plugin.
// Reminds agents to use an existing knowledge graph before broad raw-file searches.
import { existsSync } from "fs";
import { join } from "path";

export const GraphifyPlugin = async ({ directory }) => {
  let reminded = false;

  return {
    "tool.execute.before": async (input, output) => {
      if (reminded) return;
      if (input.tool !== "bash") return;
      if (!existsSync(join(directory, "graphify-out", "graph.json"))) return;

      output.args.command =
        'printf "%s\\n" "[graphify] knowledge graph found at graphify-out/. For focused codebase questions, prefer graphify query/path/explain before broad raw-file searches." && ' +
        output.args.command;
      reminded = true;
    },
  };
};
