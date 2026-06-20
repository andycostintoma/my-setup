#!/usr/bin/env node

import { createServer } from "node:http";
import type { IncomingMessage, ServerResponse } from "node:http";
import { fileURLToPath } from "node:url";
import { realpathSync } from "node:fs";

type JsonObject = Record<string, any>;

const host = process.env.OLLAMA_OPENCODE_PROXY_HOST || "127.0.0.1";
const port = Number(process.env.OLLAMA_OPENCODE_PROXY_PORT || "11435");
const upstream = (process.env.OLLAMA_UPSTREAM || "http://127.0.0.1:11434").replace(/\/$/, "");

function sendJson(res: ServerResponse, status: number, body: JsonObject) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
}

function sse(res: ServerResponse, payload: JsonObject) {
  res.write(`data: ${JSON.stringify(payload)}\n\n`);
}

function textFromContent(content: any): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .map((part) => {
      if (typeof part === "string") return part;
      if (part?.type === "text") return part.text || "";
      if (part?.text) return part.text;
      return "";
    })
    .filter(Boolean)
    .join("\n");
}

function toOllamaMessages(messages: any[] = []) {
  return messages.map((message) => {
    const converted = {
      role: message.role,
      content: textFromContent(message.content),
    };

    if (message.tool_calls) {
      converted.tool_calls = message.tool_calls.map((call) => ({
        function: {
          name: call.function?.name,
          arguments: parseToolArgs(call.function?.arguments),
        },
      }));
    }

    if (message.role === "tool" && message.tool_call_id) {
      converted.tool_call_id = message.tool_call_id;
    }

    return converted;
  });
}

function parseToolArgs(args: any) {
  if (args == null || args === "") return {};
  if (typeof args !== "string") return args;
  try {
    return JSON.parse(args);
  } catch {
    return args;
  }
}

function toOpenAIToolCalls(toolCalls: any[] = []) {
  return toolCalls.map((call, index) => ({
    id: call.id || `call_${index}`,
    type: "function",
    function: {
      name: call.function?.name || call.name,
      arguments: JSON.stringify(call.function?.arguments ?? call.arguments ?? {}),
    },
  }));
}

function toOllamaRequest(body: any, stream: boolean) {
  const options: JsonObject = {};
  if (body.max_tokens != null) options.num_predict = body.max_tokens;
  if (body.temperature != null) options.temperature = body.temperature;
  if (body.top_p != null) options.top_p = body.top_p;
  if (body.frequency_penalty != null) options.frequency_penalty = body.frequency_penalty;
  if (body.presence_penalty != null) options.presence_penalty = body.presence_penalty;
  if (body.seed != null) options.seed = body.seed;
  if (Array.isArray(body.stop)) options.stop = body.stop;
  if (typeof body.stop === "string") options.stop = [body.stop];

  return {
    model: body.model,
    messages: toOllamaMessages(body.messages),
    tools: body.tools,
    stream,
    think: false,
    options,
  };
}

async function readBody(req: IncomingMessage) {
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk);
  return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
}

async function proxyChat(body: any, res: ServerResponse) {
  const stream = body.stream !== false;
  const response = await fetch(`${upstream}/api/chat`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(toOllamaRequest(body, stream)),
  });

  if (!response.ok) {
    const error = await response.text();
    sendJson(res, response.status, { error: { message: error } });
    return;
  }

  if (!stream) {
    const data: any = await response.json();
    const message = data.message || {};
    sendJson(res, 200, {
      id: `chatcmpl-${Date.now()}`,
      object: "chat.completion",
      created: Math.floor(Date.now() / 1000),
      model: body.model,
      choices: [
        {
          index: 0,
          message: {
            role: "assistant",
            content: message.content || "",
            ...(message.tool_calls ? { tool_calls: toOpenAIToolCalls(message.tool_calls) } : {}),
          },
          finish_reason: message.tool_calls ? "tool_calls" : "stop",
        },
      ],
      usage: usageFromOllama(data),
    });
    return;
  }

  res.writeHead(200, {
    "content-type": "text/event-stream",
    "cache-control": "no-cache",
    connection: "keep-alive",
  });

  const id = `chatcmpl-${Date.now()}`;
  const created = Math.floor(Date.now() / 1000);
  sse(res, {
    id,
    object: "chat.completion.chunk",
    created,
    model: body.model,
    choices: [{ index: 0, delta: { role: "assistant" }, finish_reason: null }],
  });

  let buffer = "";
  for await (const chunk of response.body) {
    buffer += Buffer.from(chunk).toString("utf8");
    const lines = buffer.split("\n");
    buffer = lines.pop() || "";
    for (const line of lines) {
      if (!line.trim()) continue;
      const data = JSON.parse(line);
      const message = data.message || {};

      if (message.content) {
        sse(res, {
          id,
          object: "chat.completion.chunk",
          created,
          model: body.model,
          choices: [{ index: 0, delta: { content: message.content }, finish_reason: null }],
        });
      }

      if (message.tool_calls) {
        sse(res, {
          id,
          object: "chat.completion.chunk",
          created,
          model: body.model,
          choices: [
            { index: 0, delta: { tool_calls: toOpenAIToolCalls(message.tool_calls) }, finish_reason: null },
          ],
        });
      }

      if (data.done) {
        sse(res, {
          id,
          object: "chat.completion.chunk",
          created,
          model: body.model,
          choices: [
            {
              index: 0,
              delta: {},
              finish_reason: message.tool_calls ? "tool_calls" : "stop",
            },
          ],
        });
        if (body.stream_options?.include_usage) {
          sse(res, {
            id,
            object: "chat.completion.chunk",
            created,
            model: body.model,
            choices: [],
            usage: usageFromOllama(data),
          });
        }
      }
    }
  }

  res.write("data: [DONE]\n\n");
  res.end();
}

function usageFromOllama(data: any) {
  const prompt = data.prompt_eval_count || 0;
  const completion = data.eval_count || 0;
  return {
    prompt_tokens: prompt,
    completion_tokens: completion,
    total_tokens: prompt + completion,
  };
}

export function createOllamaProxyServer() {
  return createServer(async (req: IncomingMessage, res: ServerResponse) => {
    try {
      const url = new URL(req.url || "/", `http://${req.headers.host}`);
      if (req.method === "GET" && url.pathname === "/v1/models") {
        sendJson(res, 200, { object: "list", data: [] });
        return;
      }

      if (req.method === "POST" && url.pathname === "/v1/chat/completions") {
        await proxyChat(await readBody(req), res);
        return;
      }

      sendJson(res, 404, { error: { message: "not found" } });
    } catch (error) {
      sendJson(res, 500, { error: { message: error?.message || String(error) } });
    }
  });
}

function isMainModule(): boolean {
  const entry = process.argv[1];
  if (!entry) return false;
  const modulePath = fileURLToPath(import.meta.url);
  if (entry === modulePath) return true;
  // ~/.config/opencode/services is a Home Manager symlink into the Nix store,
  // so argv[1] (the symlink path) and import.meta.url (the resolved store path)
  // differ. Compare canonical realpaths so the service still self-starts.
  try {
    return realpathSync(entry) === realpathSync(modulePath);
  } catch {
    return false;
  }
}

if (isMainModule()) {
  const server = createOllamaProxyServer();
  server.listen(port, host, () => {
    console.error(`ollama-opencode-proxy listening on http://${host}:${port}, upstream ${upstream}`);
  });
}
