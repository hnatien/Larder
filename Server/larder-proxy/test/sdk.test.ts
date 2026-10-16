import Anthropic from "@anthropic-ai/sdk";
import { describe, expect, it } from "vitest";
import { callModel } from "../src/model.js";
import { buildParsePantryRequest } from "../src/routes/parsePantry.js";

// Drives the real SDK client through a stubbed fetch to check the wire format and parse behaviour.
function clientReturning(message: Record<string, unknown>, sink: { body?: Record<string, unknown> }) {
  return new Anthropic({
    apiKey: "test-key",
    maxRetries: 0,
    fetch: async (_url, init) => {
      sink.body = JSON.parse(String(init?.body));
      return new Response(JSON.stringify(message), { status: 200, headers: { "content-type": "application/json" } });
    },
  });
}

const baseMessage = {
  id: "msg_1",
  type: "message",
  role: "assistant",
  model: "claude-haiku-5-5",
  stop_sequence: null,
  stop_details: null,
  usage: { input_tokens: 10, output_tokens: 5, cache_read_input_tokens: 0, cache_creation_input_tokens: 8 },
};

describe("real SDK client", () => {
  const params = buildParsePantryRequest({ text: "2 tins chickpeas" }, "claude-haiku-5-5");
  const log = { requestId: "r", route: "parse-pantry", model: "claude-haiku-5-5" };

  it("sends the cached system block and a JSON schema format, with no sampling or thinking params", async () => {
    const sink: { body?: Record<string, unknown> } = {};
    const output = { lines: [{ rawName: "chickpeas", quantity: 2, unit: "tin", location: null, bestByHint: null }] };
    const client = clientReturning(
      { ...baseMessage, stop_reason: "end_turn", content: [{ type: "text", text: JSON.stringify(output) }] },
      sink,
    );
    const result = await callModel(client, params, log);
    expect(result).toEqual({ ok: true, output });
    const body = sink.body!;
    expect(body.system).toEqual([expect.objectContaining({ cache_control: { type: "ephemeral" } })]);
    expect(body.output_config).toMatchObject({ effort: "low", format: { type: "json_schema" } });
    for (const key of ["temperature", "top_p", "top_k", "thinking", "fallbacks"]) expect(body).not.toHaveProperty(key);
  });

  it("surfaces a refusal with non-JSON text as declined instead of throwing", async () => {
    const client = clientReturning(
      {
        ...baseMessage,
        stop_reason: "refusal",
        stop_details: { type: "refusal", category: null, explanation: null },
        content: [{ type: "text", text: "I can't help with that." }],
      },
      {},
    );
    const result = await callModel(client, params, log);
    expect(result).toEqual({ ok: false, reply: { status: 422, body: { error: "declined", category: null } } });
  });
});
