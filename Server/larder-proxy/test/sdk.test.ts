import Anthropic from "@anthropic-ai/sdk";
import type { JSONSchema } from "@anthropic-ai/sdk/lib/transform-json-schema";
import { describe, expect, it } from "vitest";
import { z } from "zod";
import { callModel, strictJsonSchema } from "../src/model.js";
import { buildAdjustRequest } from "../src/routes/adjust.js";
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

  it("sends enums as enforced keywords, including a nullable one", async () => {
    const sink: { body?: Record<string, unknown> } = {};
    const client = clientReturning(
      { ...baseMessage, stop_reason: "end_turn", content: [{ type: "text", text: '{"lines": []}' }] },
      sink,
    );
    await callModel(client, params, log);
    const schema = JSON.stringify(sink.body!.output_config);
    expect(schema).toContain('"enum":["fridge","freezer","pantry","other"]');
    expect(schema).not.toContain("{enum:");
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

describe("strictJsonSchema", () => {
  it("constrains the adjust constraint axis to the enum instead of describing it", () => {
    const schema = buildAdjustRequest(
      { instruction: "Make dinners vegetarian.", currentConstraints: [], planContext: { days: [] } },
      "claude-haiku-5-5",
    ).output_config.format.schema as JSONSchema;
    const edit = schema.properties.edits.items;
    expect(edit.properties.constraint.properties.axis).toEqual({
      type: "string",
      enum: ["medical", "religious", "ethical", "preference", "goal"],
    });
    expect(edit.properties.op.enum).toEqual(["add", "remove", "replace"]);
    expect(edit.properties.scope.properties.slots.items.enum).toEqual(["breakfast", "lunch", "dinner", "snack"]);
  });

  it("restores const and enums inside reused definitions and unions", () => {
    const Slot = z.enum(["lunch", "dinner"]);
    const schema = strictJsonSchema(
      z.object({
        kind: z.literal("meal"),
        first: Slot,
        second: Slot,
        either: z.union([z.literal("a"), z.object({ slot: Slot.nullable() })]),
      }),
    );
    expect(schema.properties.kind).toEqual({ type: "string", const: "meal" });
    const definition = Object.values<Record<string, unknown>>(schema.$defs)[0];
    expect(definition).toEqual({ type: "string", enum: ["lunch", "dinner"] });
    expect(schema.properties.either.anyOf[0]).toEqual({ type: "string", const: "a" });
    expect(JSON.stringify(schema)).not.toMatch(/\{(enum|const):/);
  });

  it("still moves keywords the API cannot enforce into the description", () => {
    const schema = strictJsonSchema(z.object({ note: z.string().max(5) }));
    expect(schema.properties.note).toEqual({ type: "string", description: "{maxLength: 5}" });
  });
});
