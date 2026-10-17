import { APIConnectionError, APIError, AuthenticationError, RateLimitError } from "@anthropic-ai/sdk";
import { beforeAll, describe, expect, it, vi } from "vitest";
import { ENTITLEMENT_HEADER } from "../src/auth/entitlement.js";
import { makeChain, signTransaction, type TestChain } from "./helpers/certs.js";
import { authed, BUNDLE_ID, makeHarness, NOW, post, sessionToken } from "./helpers/fixtures.js";

const explainBody = {
  plan: {
    days: [
      {
        date: "2026-10-19",
        meals: [
          {
            slot: "dinner",
            recipeTitle: "Spinach dal",
            minutes: 25,
            reasonCodes: [{ code: "usesExpiring", params: { food: "spinach", bestBy: "2026-10-20" } }],
          },
        ],
      },
    ],
  },
  shelfBalance: { groupsLight: ["produce"], groupsHeavy: [] },
  profileSummary: { goal: "lessWaste", householdSize: 2, maxCookMinutes: 30, showsNumbers: false },
};

const explainOutput = {
  headline: "Two nights use up the spinach.",
  perDay: [{ date: "2026-10-19", sentence: "Spinach is best by Tuesday. Dinner uses it." }],
  swapsOffered: [],
};

const pantryOutput = {
  lines: [{ rawName: "chickpeas", quantity: 2, unit: "tin", location: "pantry", bestByHint: null }],
};

const recipeOutput = {
  title: "Spinach dal",
  servings: 4,
  prepMinutes: 10,
  cookMinutes: 25,
  ingredients: [{ rawText: "200 g red lentils", quantity: 200, unit: "g", name: "red lentils", optional: false }],
  steps: [{ text: "Simmer the lentils.", timerSeconds: 1200 }],
  tags: { cuisine: "Indian", mealType: "dinner" },
};

const adjustBody = {
  instruction: "No fish on weeknights",
  currentConstraints: [{ axis: "medical", kind: "allergen:peanut", strictness: "hard" }],
  planContext: { days: explainBody.plan.days },
};

const adjustOutput = (edits: unknown[]) => ({ edits, clarifyingQuestion: null });

let chain: TestChain;
let plusHeader: Record<string, string>;

beforeAll(async () => {
  chain = await makeChain();
  const jws = await signTransaction(chain, {
    bundleId: BUNDLE_ID,
    productId: "com.larder.plus.monthly",
    expiresDate: NOW.getTime() + 86_400_000,
  });
  plusHeader = { [ENTITLEMENT_HEADER]: jws };
});

const plusHarness = () => makeHarness({ trustedRootPEMs: [chain.rootPem] });

describe("routing", () => {
  it("returns JSON 404 with a request id for unknown paths", async () => {
    const { app } = makeHarness();
    const response = await post(app, "/v1/nope", {});
    expect(response.status).toBe(404);
    expect(response.headers.get("content-type")).toBe("application/json");
    expect(response.headers.get("x-request-id")).toMatch(/^[0-9a-f-]{36}$/);
  });

  it("returns 405 for GET on a known path", async () => {
    const { app } = makeHarness();
    const response = await app.fetch(new Request("https://proxy.test/v1/assist/explain"));
    expect(response.status).toBe(405);
    expect(await response.json()).toEqual({ error: "method_not_allowed" });
  });

  it("gives every response a distinct request id", async () => {
    const { app } = makeHarness();
    const a = await post(app, "/v1/nope", {});
    const b = await post(app, "/v1/nope", {});
    expect(a.headers.get("x-request-id")).not.toBe(b.headers.get("x-request-id"));
  });
});

describe("POST /v1/assist/explain", () => {
  it("returns the parsed explanation using the fast model, low effort and 2048 max tokens", async () => {
    const { app, anthropic } = makeHarness();
    anthropic.replyJson(explainOutput);
    const response = await post(app, "/v1/assist/explain", explainBody, await authed());
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("application/json");
    expect(await response.json()).toEqual(explainOutput);
    const call = anthropic.calls[0];
    expect(call?.model).toBe("claude-haiku-5-5");
    expect(call?.max_tokens).toBe(2048);
    expect(call?.output_config?.effort).toBe("low");
    expect(call).not.toHaveProperty("thinking");
    expect(call).not.toHaveProperty("temperature");
  });

  it("reads output after a leading thinking block", async () => {
    const { app, anthropic } = makeHarness();
    anthropic.reply({ text: JSON.stringify(explainOutput), leadingThinking: true });
    const response = await post(app, "/v1/assist/explain", explainBody, await authed());
    expect(await response.json()).toEqual(explainOutput);
  });

  it("returns 401 without a session and never calls the model", async () => {
    const { app, anthropic } = makeHarness();
    const response = await post(app, "/v1/assist/explain", explainBody);
    expect(response.status).toBe(401);
    expect(anthropic.calls).toHaveLength(0);
  });

  it("returns 401 for an expired session", async () => {
    const { app } = makeHarness();
    const stale = await sessionToken(new Date(NOW.getTime() - 2 * 3_600_000));
    const response = await post(app, "/v1/assist/explain", explainBody, await authed(stale));
    expect(response.status).toBe(401);
  });

  it("checks the session before reading the body", async () => {
    const { app } = makeHarness();
    const response = await post(app, "/v1/assist/explain", "{broken");
    expect(response.status).toBe(401);
  });

  it("returns 400 with Zod issues for an invalid body", async () => {
    const { app, anthropic } = makeHarness();
    const bad = { ...explainBody, profileSummary: { ...explainBody.profileSummary, householdSize: 0 } };
    const response = await post(app, "/v1/assist/explain", bad, await authed());
    expect(response.status).toBe(400);
    const body = (await response.json()) as { error: string; issues: Array<{ path: string }> };
    expect(body.error).toBe("invalid_request");
    expect(body.issues.map((issue) => issue.path)).toContain("profileSummary.householdSize");
    expect(anthropic.calls).toHaveLength(0);
  });

  it("rejects an unknown meal slot", async () => {
    const { app } = makeHarness();
    const day = { date: "2026-10-19", meals: [{ ...explainBody.plan.days[0]!.meals[0]!, slot: "brunch" }] };
    const response = await post(app, "/v1/assist/explain", { ...explainBody, plan: { days: [day] } }, await authed());
    expect(response.status).toBe(400);
  });

  it("returns 400 for a body that is not JSON", async () => {
    const { app } = makeHarness();
    const response = await post(app, "/v1/assist/explain", "{broken", await authed());
    expect(await response.json()).toEqual({ error: "invalid_json" });
  });

  it("returns 429 with resetsAt once the free daily limit is used", async () => {
    const { app, anthropic } = makeHarness();
    const headers = await authed();
    for (let i = 0; i < 3; i++) {
      anthropic.replyJson(explainOutput);
      expect((await post(app, "/v1/assist/explain", explainBody, headers)).status).toBe(200);
    }
    const response = await post(app, "/v1/assist/explain", explainBody, headers);
    expect(response.status).toBe(429);
    expect(await response.json()).toEqual({ error: "quota_exceeded", resetsAt: "2026-10-17T00:00:00.000Z" });
    expect(anthropic.calls).toHaveLength(3);
  });

  it("gives Plus subscribers the Plus daily limit on free routes", async () => {
    const { app, anthropic } = makeHarness({ env: { PLUS_DAILY_LIMIT: "4" }, trustedRootPEMs: [chain.rootPem] });
    const headers = { ...(await authed()), ...plusHeader };
    for (let i = 0; i < 4; i++) {
      anthropic.replyJson(explainOutput);
      expect((await post(app, "/v1/assist/explain", explainBody, headers)).status).toBe(200);
    }
    expect((await post(app, "/v1/assist/explain", explainBody, headers)).status).toBe(429);
  });

  it("counts quota per session subject", async () => {
    const { app, anthropic } = makeHarness({ env: { FREE_DAILY_LIMIT: "1" } });
    anthropic.replyJson(explainOutput).replyJson(explainOutput);
    expect((await post(app, "/v1/assist/explain", explainBody, await authed())).status).toBe(200);
    expect((await post(app, "/v1/assist/explain", explainBody, await authed())).status).toBe(200);
  });

  it("maps a refusal to 422 declined with its category and does not count it", async () => {
    const { app, anthropic, kv } = makeHarness();
    anthropic.reply({ text: "", stopReason: "refusal", refusalCategory: "cyber" });
    const response = await post(app, "/v1/assist/explain", explainBody, await authed());
    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "declined", category: "cyber" });
    expect(kv.store.size).toBe(0);
  });

  it("maps max_tokens to 502 truncated and does not count it", async () => {
    const { app, anthropic, kv } = makeHarness();
    anthropic.reply({ text: '{"headline": "Two ni', stopReason: "max_tokens" });
    const response = await post(app, "/v1/assist/explain", explainBody, await authed());
    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: "truncated" });
    expect(kv.store.size).toBe(0);
  });

  it("maps output that fails the response schema to 502 unparseable", async () => {
    const { app, anthropic, kv } = makeHarness();
    anthropic.replyJson({ ...explainOutput, headline: "x".repeat(91) });
    const response = await post(app, "/v1/assist/explain", explainBody, await authed());
    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: "unparseable" });
    expect(kv.store.size).toBe(0);
  });

  it("logs one structured line with token counts and no content", async () => {
    const { app, anthropic } = makeHarness();
    anthropic.replyJson(explainOutput);
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    await post(app, "/v1/assist/explain", explainBody, await authed());
    const lines = spy.mock.calls.map((args) => String(args[0]));
    spy.mockRestore();
    expect(lines).toHaveLength(1);
    const entry = JSON.parse(lines[0]!);
    expect(entry).toMatchObject({
      event: "model_call",
      route: "explain",
      model: "claude-haiku-5-5",
      status: 200,
      inputTokens: 1200,
      outputTokens: 300,
      cacheReadInputTokens: 900,
      cacheCreationInputTokens: 0,
    });
    expect(typeof entry.latencyMs).toBe("number");
    expect(lines[0]).not.toContain("Spinach");
  });
});

describe("SDK error mapping", () => {
  const cases: Array<[string, Error, number, string]> = [
    ["RateLimitError", new RateLimitError(429, undefined, "slow down", new Headers()), 429, "upstream_rate_limited"],
    ["AuthenticationError", new AuthenticationError(401, undefined, "bad key", new Headers()), 500, "internal_error"],
    ["APIConnectionError", new APIConnectionError({ message: "offline" }), 503, "upstream_unavailable"],
    ["APIError", new APIError(529, undefined, "overloaded", new Headers()), 502, "upstream_error"],
  ];

  it.each(cases)("maps %s", async (_name, error, status, code) => {
    const { app, anthropic, kv } = makeHarness();
    anthropic.reply(error);
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const response = await post(app, "/v1/assist/parse-pantry", { text: "2 tins chickpeas" }, await authed());
    errorSpy.mockRestore();
    logSpy.mockRestore();
    expect(response.status).toBe(status);
    expect(((await response.json()) as { error: string }).error).toBe(code);
    expect(kv.store.size).toBe(0);
  });

  it("returns a generic 500 for unexpected errors", async () => {
    const { app, anthropic } = makeHarness();
    anthropic.reply(new TypeError("boom"));
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    const response = await post(app, "/v1/assist/parse-pantry", { text: "milk" }, await authed());
    spy.mockRestore();
    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({ error: "internal_error" });
  });
});

describe("POST /v1/assist/parse-pantry", () => {
  it("parses a note with the fast model and 1024 max tokens", async () => {
    const { app, anthropic } = makeHarness();
    anthropic.replyJson(pantryOutput);
    const response = await post(app, "/v1/assist/parse-pantry", { text: "2 tins chickpeas" }, await authed());
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(pantryOutput);
    expect(anthropic.calls[0]).toMatchObject({ model: "claude-haiku-5-5", max_tokens: 1024 });
    expect(anthropic.calls[0]?.output_config?.effort).toBe("low");
  });

  it.each([
    ["empty", { text: "   " }],
    ["too long", { text: "a".repeat(501) }],
    ["missing", {}],
  ])("rejects %s text with 400", async (_label, body) => {
    const { app } = makeHarness();
    expect((await post(app, "/v1/assist/parse-pantry", body, await authed())).status).toBe(400);
  });

  it("rejects a location outside the schema as unparseable", async () => {
    const { app, anthropic } = makeHarness();
    anthropic.replyJson({ lines: [{ ...pantryOutput.lines[0], location: "garage" }] });
    const response = await post(app, "/v1/assist/parse-pantry", { text: "milk" }, await authed());
    expect(response.status).toBe(502);
  });
});

describe("POST /v1/assist/parse-recipe", () => {
  it("returns 402 for the free tier without calling the model", async () => {
    const { app, anthropic } = plusHarness();
    const response = await post(app, "/v1/assist/parse-recipe", { text: "Dal" }, await authed());
    expect(response.status).toBe(402);
    expect(await response.json()).toEqual({ error: "plus_required" });
    expect(anthropic.calls).toHaveLength(0);
  });

  it("returns 402 when the entitlement header is invalid", async () => {
    const { app } = plusHarness();
    const headers = { ...(await authed()), [ENTITLEMENT_HEADER]: "not.a.jws" };
    expect((await post(app, "/v1/assist/parse-recipe", { text: "Dal" }, headers)).status).toBe(402);
  });

  it("parses text for Plus with the capable model at medium effort", async () => {
    const { app, anthropic } = plusHarness();
    anthropic.replyJson(recipeOutput);
    const headers = { ...(await authed()), ...plusHeader };
    const response = await post(app, "/v1/assist/parse-recipe", { text: "Spinach dal for 4" }, headers);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(recipeOutput);
    const call = anthropic.calls[0];
    expect(call).toMatchObject({ model: "claude-sonnet-5-5", max_tokens: 1024 });
    expect(call?.output_config?.effort).toBe("medium");
  });

  it("puts the image block before the text block", async () => {
    const { app, anthropic } = plusHarness();
    anthropic.replyJson(recipeOutput);
    const headers = { ...(await authed()), ...plusHeader };
    const body = { text: "from grandma", imageBase64: "iVBORw0KGgo=", imageMediaType: "image/png" };
    expect((await post(app, "/v1/assist/parse-recipe", body, headers)).status).toBe(200);
    const content = anthropic.calls[0]?.messages[0]?.content as Array<{ type: string }>;
    expect(content.map((block) => block.type)).toEqual(["image", "text"]);
    expect(content[0]).toEqual({
      type: "image",
      source: { type: "base64", media_type: "image/png", data: "iVBORw0KGgo=" },
    });
  });

  it("accepts an image without text", async () => {
    const { app, anthropic } = plusHarness();
    anthropic.replyJson(recipeOutput);
    const headers = { ...(await authed()), ...plusHeader };
    const body = { imageBase64: "iVBORw0KGgo=", imageMediaType: "image/jpeg" };
    expect((await post(app, "/v1/assist/parse-recipe", body, headers)).status).toBe(200);
  });

  it.each([
    ["neither text nor image", {}],
    ["image without media type", { imageBase64: "iVBORw0KGgo=" }],
    ["unsupported media type", { imageBase64: "iVBORw0KGgo=", imageMediaType: "image/gif" }],
    ["text over 20000 characters", { text: "a".repeat(20_001) }],
    ["image that is not base64", { imageBase64: "not base64!", imageMediaType: "image/png" }],
  ])("rejects %s with 400", async (_label, body) => {
    const { app } = plusHarness();
    const headers = { ...(await authed()), ...plusHeader };
    expect((await post(app, "/v1/assist/parse-recipe", body, headers)).status).toBe(400);
  });
});

describe("POST /v1/assist/adjust", () => {
  it("returns 402 for the free tier", async () => {
    const { app } = plusHarness();
    expect((await post(app, "/v1/assist/adjust", adjustBody, await authed())).status).toBe(402);
  });

  it("returns edits for Plus with the capable model and 2048 max tokens", async () => {
    const { app, anthropic } = plusHarness();
    const output = adjustOutput([
      {
        op: "add",
        constraint: { axis: "preference", kind: "dislike:fish", strictness: "soft" },
        scope: { slots: ["dinner"] },
      },
    ]);
    anthropic.replyJson(output);
    const response = await post(app, "/v1/assist/adjust", adjustBody, { ...(await authed()), ...plusHeader });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(output);
    expect(anthropic.calls[0]).toMatchObject({ model: "claude-sonnet-5-5", max_tokens: 2048 });
  });

  it("allows adding a medical constraint", async () => {
    const { app, anthropic } = plusHarness();
    anthropic.replyJson(
      adjustOutput([{ op: "add", constraint: { axis: "medical", kind: "allergen:sesame", strictness: "hard" }, scope: {} }]),
    );
    const response = await post(app, "/v1/assist/adjust", adjustBody, { ...(await authed()), ...plusHeader });
    expect(response.status).toBe(200);
  });

  it("rejects removing a medical constraint with 422 protected_constraint", async () => {
    const { app, anthropic } = plusHarness();
    anthropic.replyJson(
      adjustOutput([{ op: "remove", constraint: { axis: "medical", kind: "allergen:peanut", strictness: "hard" }, scope: {} }]),
    );
    const response = await post(app, "/v1/assist/adjust", adjustBody, { ...(await authed()), ...plusHeader });
    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "protected_constraint" });
  });

  it("rejects softening a medical constraint through replace", async () => {
    const { app, anthropic } = plusHarness();
    anthropic.replyJson(
      adjustOutput([{ op: "replace", constraint: { axis: "medical", kind: "allergen:peanut", strictness: "soft" }, scope: {} }]),
    );
    const response = await post(app, "/v1/assist/adjust", adjustBody, { ...(await authed()), ...plusHeader });
    expect(response.status).toBe(422);
  });

  it("rejects the whole response when any one edit is protected", async () => {
    const { app, anthropic } = plusHarness();
    anthropic.replyJson(
      adjustOutput([
        { op: "add", constraint: { axis: "preference", kind: "dislike:fish", strictness: "soft" }, scope: {} },
        { op: "remove", constraint: { axis: "medical", kind: "intolerance:lactose", strictness: "hard" }, scope: {} },
      ]),
    );
    const response = await post(app, "/v1/assist/adjust", adjustBody, { ...(await authed()), ...plusHeader });
    expect(response.status).toBe(422);
  });

  it("allows removing a non-medical constraint", async () => {
    const { app, anthropic } = plusHarness();
    anthropic.replyJson(
      adjustOutput([{ op: "remove", constraint: { axis: "preference", kind: "dislike:fish", strictness: "soft" }, scope: {} }]),
    );
    const response = await post(app, "/v1/assist/adjust", adjustBody, { ...(await authed()), ...plusHeader });
    expect(response.status).toBe(200);
  });

  it.each([
    ["re-axes a medical kind to a soft preference", { op: "replace", constraint: { axis: "preference", kind: "allergen:peanut", strictness: "soft" }, scope: {} }],
    ["narrows a medical constraint to some dates", { op: "replace", constraint: { axis: "medical", kind: "allergen:peanut", strictness: "hard" }, scope: { dates: ["2026-10-19"] } }],
    ["narrows a medical constraint to some slots", { op: "replace", constraint: { axis: "medical", kind: "allergen:peanut", strictness: "hard" }, scope: { slots: ["dinner"] } }],
    ["adds an allowance for a protected substance", { op: "add", constraint: { axis: "preference", kind: "allow:peanut", strictness: "soft" }, scope: { dates: ["2026-10-19"] } }],
    ["adds an allowance under a synonym of a protected substance", { op: "add", constraint: { axis: "preference", kind: "ok:groundnut", strictness: "soft" }, scope: {} }],
    ["removes a medical kind under another axis", { op: "remove", constraint: { axis: "preference", kind: "allergen:peanut", strictness: "soft" }, scope: {} }],
  ])("rejects an edit that %s with 422 protected_constraint", async (_name, edit) => {
    const { app, anthropic } = plusHarness();
    anthropic.replyJson(adjustOutput([edit]));
    const response = await post(app, "/v1/assist/adjust", adjustBody, { ...(await authed()), ...plusHeader });
    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "protected_constraint" });
  });

  it("allows strengthening, adding allergens and editing preferences around a medical constraint", async () => {
    const { app, anthropic } = plusHarness();
    const body = {
      ...adjustBody,
      currentConstraints: [
        { axis: "medical", kind: "allergen:peanut", strictness: "hard" },
        { axis: "preference", kind: "dislike:coriander", strictness: "soft" },
        { axis: "preference", kind: "dislike:mushroom", strictness: "soft" },
      ],
    };
    const output = adjustOutput([
      { op: "replace", constraint: { axis: "medical", kind: "allergen:peanut", strictness: "hard" }, scope: {} },
      { op: "replace", constraint: { axis: "preference", kind: "dislike:coriander", strictness: "hard" }, scope: {} },
      { op: "add", constraint: { axis: "medical", kind: "allergen:sesame", strictness: "hard" }, scope: {} },
      { op: "remove", constraint: { axis: "preference", kind: "dislike:mushroom", strictness: "soft" }, scope: {} },
      { op: "add", constraint: { axis: "preference", kind: "exclude:fish", strictness: "hard" }, scope: { slots: ["dinner"] } },
    ]);
    anthropic.replyJson(output);
    const response = await post(app, "/v1/assist/adjust", body, { ...(await authed()), ...plusHeader });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(output);
  });

  it("rejects an unknown constraint axis in the request", async () => {
    const { app } = plusHarness();
    const body = { ...adjustBody, currentConstraints: [{ axis: "allergen", kind: "peanut", strictness: "hard" }] };
    expect((await post(app, "/v1/assist/adjust", body, { ...(await authed()), ...plusHeader })).status).toBe(400);
  });

  it("rejects an instruction over 300 characters", async () => {
    const { app } = plusHarness();
    const body = { ...adjustBody, instruction: "a".repeat(301) };
    expect((await post(app, "/v1/assist/adjust", body, { ...(await authed()), ...plusHeader })).status).toBe(400);
  });
});

describe("quota accounting", () => {
  it("increments only after a successful model call", async () => {
    const { app, anthropic, kv } = makeHarness();
    const headers = await authed();
    anthropic.reply({ text: "", stopReason: "refusal" });
    await post(app, "/v1/assist/parse-pantry", { text: "milk" }, headers);
    expect(kv.store.size).toBe(0);
    anthropic.replyJson(pantryOutput);
    await post(app, "/v1/assist/parse-pantry", { text: "milk" }, headers);
    expect([...kv.store.values()].map((entry) => entry.value)).toEqual(["1"]);
  });

  it("does not count requests rejected before the model call", async () => {
    const { app, kv } = makeHarness();
    await post(app, "/v1/assist/parse-pantry", { text: "" }, await authed());
    await post(app, "/v1/assist/parse-pantry", { text: "milk" });
    expect(kv.store.size).toBe(0);
  });
});
