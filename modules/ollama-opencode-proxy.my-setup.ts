#!/usr/bin/env node

import { createServer } from "node:http";
import type { IncomingMessage, ServerResponse } from "node:http";

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

function parseToolArgs(args: any) {
  if (args == null || args === "") return {};
  if (typeof args !== "string") return args;
  try {
    return JSON.parse(args);
  } catch {
    return args;
  }
}

function toOllamaMessages(messages: any[] = []) {
  return messages.map((message) => {
    const converted: JsonObject = {
      role: message.role,
      content: textFromContent(message.content),
    };

    if (message.tool_calls) {
      converted.tool_calls = message.tool_calls.map((call: any) => ({
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

function openAIToolCalls(toolCalls: any[] = []) {
  return toolCalls.map((call, index) => ({
    id: call.id || `call_${index}`,
    type: "function",
    function: {
      name: call.function?.name || call.name,
      arguments: JSON.stringify(call.function?.arguments ?? call.arguments ?? {}),
    },
  }));
}

function toolCallsFromPayload(payload: string) {
  try {
    const parsed = JSON.parse(payload.trim());
    const calls = Array.isArray(parsed) ? parsed : [parsed];
    return calls
      .filter((call) => call?.name || call?.function?.name)
      .map((call) => ({
        name: call.name || call.function?.name,
        arguments: call.arguments ?? call.function?.arguments ?? {},
      }));
  } catch {
    return [];
  }
}

function toolCallsFromContent(content: string) {
  const tagged = content.match(/<([a-z][\w-]*)>\s*([\s\S]*?)\s*<\/\1>/i);
  if (tagged) {
    const calls = toolCallsFromPayload(tagged[2]);
    if (calls.length > 0) return calls;
  }

  const fenced = content.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
  if (fenced) {
    const calls = toolCallsFromPayload(fenced[1]);
    if (calls.length > 0) return calls;
  }

  return toolCallsFromPayload(content);
}

function normalizedAssistantMessage(message: any, parseToolContent: boolean) {
  const content = message.content || "";
  const toolCalls = message.tool_calls || (parseToolContent ? toolCallsFromContent(content) : []);
  if (toolCalls.length > 0) {
    return {
      role: "assistant",
      content: "",
      tool_calls: openAIToolCalls(toolCalls),
    };
  }
  return { role: "assistant", content };
}

function finishReason(message: any, parseToolContent: boolean, content = message.content || "") {
  return message.tool_calls || (parseToolContent && toolCallsFromContent(content).length > 0) ? "tool_calls" : "stop";
}

function mayBeTaggedToolContent(content: string) {
  const trimmed = content.trimStart();
  return trimmed === "" || trimmed.startsWith("<") || trimmed.startsWith("{") || trimmed.startsWith("[") || trimmed.startsWith("`");
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

function usageFromOllama(data: any) {
  const prompt = data.prompt_eval_count || 0;
  const completion = data.eval_count || 0;
  return {
    prompt_tokens: prompt,
    completion_tokens: completion,
    total_tokens: prompt + completion,
  };
}

async function proxyChat(body: any, res: ServerResponse) {
  const stream = body.stream !== false;
  const parseToolContent = Array.isArray(body.tools) && body.tools.length > 0;
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
          message: normalizedAssistantMessage(message, parseToolContent),
          finish_reason: finishReason(message, parseToolContent),
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
  let content = "";
  let finalData: any = {};
  let finalMessage: any = {};
  let streamingText = false;

  for await (const chunk of response.body) {
    buffer += Buffer.from(chunk).toString("utf8");
    const lines = buffer.split("\n");
    buffer = lines.pop() || "";
    for (const line of lines) {
      if (!line.trim()) continue;
      const data = JSON.parse(line);
      const message = data.message || {};
      if (message.content) {
        content += message.content;
        if (!parseToolContent || streamingText || !mayBeTaggedToolContent(content)) {
          const text = streamingText ? message.content : content;
          streamingText = true;
          sse(res, {
            id,
            object: "chat.completion.chunk",
            created,
            model: body.model,
            choices: [{ index: 0, delta: { content: text }, finish_reason: null }],
          });
        }
      }
      if (message.tool_calls) finalMessage.tool_calls = message.tool_calls;
      if (data.done) {
        finalData = data;
        finalMessage = { ...finalMessage, ...message, content };
      }
    }
  }

  const parsedToolCalls = finalMessage.tool_calls || (parseToolContent ? toolCallsFromContent(content) : []);
  if (parsedToolCalls.length > 0) {
    sse(res, {
      id,
      object: "chat.completion.chunk",
      created,
      model: body.model,
      choices: [{ index: 0, delta: { tool_calls: openAIToolCalls(parsedToolCalls) }, finish_reason: null }],
    });
  } else if (content && !streamingText) {
    sse(res, {
      id,
      object: "chat.completion.chunk",
      created,
      model: body.model,
      choices: [{ index: 0, delta: { content }, finish_reason: null }],
    });
  }

  sse(res, {
    id,
    object: "chat.completion.chunk",
    created,
    model: body.model,
    choices: [{ index: 0, delta: {}, finish_reason: parsedToolCalls.length > 0 ? "tool_calls" : "stop" }],
  });

  if (body.stream_options?.include_usage) {
    sse(res, {
      id,
      object: "chat.completion.chunk",
      created,
      model: body.model,
      choices: [],
      usage: usageFromOllama(finalData),
    });
  }

  res.write("data: [DONE]\n\n");
  res.end();
}

function createOllamaProxyServer() {
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
      sendJson(res, 404, { error: { message: "Not found" } });
    } catch (error) {
      sendJson(res, 500, { error: { message: error instanceof Error ? error.message : String(error) } });
    }
  });
}

createOllamaProxyServer().listen(port, host, () => {
  console.log(`ollama opencode proxy listening on http://${host}:${port}`);
});
