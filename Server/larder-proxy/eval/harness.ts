// Runs one eval case through a route's real request builder, `callModel` and output check, with
// the real Anthropic client. Session, entitlement and quota are skipped: they never reach the model.
import { APIConnectionError, APIError } from "@anthropic-ai/sdk";
import type { ExtractParsedContentFromParams, ParsedMessage } from "@anthropic-ai/sdk/lib/parser";
import type { MessageCreateParamsNonStreaming, StopReason, Usage } from "@anthropic-ai/sdk/resources/messages";
import { callModel, type AnthropicLike } from "../src/model.js";
import { ADJUST_SYSTEM_PROMPT } from "../src/prompts/adjust.js";
import { adjustRoute } from "../src/routes/adjust.js";
import { explainRoute } from "../src/routes/explain.js";
import { parsePantryRoute } from "../src/routes/parsePantry.js";
import { parseRecipeRoute } from "../src/routes/parseRecipe.js";
import type { AssistRoute } from "../src/routes/route.js";
import type { AdjustRequest, AdjustResponse, ExplainRequest, ExplainResponse, ParsePantryResponse, ParseRecipeResponse } from "../src/schemas.js";
import {
  gradeAdjust,
  gradeExplain,
  gradePantry,
  gradeRecipe,
  type AdjustExpect,
  type ExplainExpect,
  type Graded,
  type PantryLine,
  type RecipeExpect,
} from "./graders.js";

export const ROUTES = {
  explain: explainRoute,
  "parse-pantry": parsePantryRoute,
  "parse-recipe": parseRecipeRoute,
  adjust: adjustRoute,
} as const;
export type RouteName = keyof typeof ROUTES;

export interface EvalCase {
  id: string;
  tags: string[];
  request: unknown;
  expect: unknown;
  /** The user turn the model sees, for the report. */
  prompt: string;
}

interface CaseFile {
  fixtures?: Record<string, unknown>;
  cases: { id: string; tags: string[]; request: unknown; expect: unknown }[];
}

/** Replaces any string "$name" with fixtures[name], so shared plans and constraint sets are written once. */
function resolveFixtures(value: unknown, fixtures: Record<string, unknown>): unknown {
  if (typeof value === "string" && value.startsWith("$")) {
    const fixture = fixtures[value.slice(1)];
    if (fixture === undefined) throw new Error(`unknown fixture ${value}`);
    return structuredClone(fixture);
  }
  if (Array.isArray(value)) return value.map((item) => resolveFixtures(item, fixtures));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, resolveFixtures(item, fixtures)]));
  }
  return value;
}

/** Parses a case file and checks every request against the route's own request schema. */
export function loadCases(route: RouteName, text: string): EvalCase[] {
  const file = JSON.parse(text) as CaseFile;
  const fixtures = file.fixtures ?? {};
  const assist = ROUTES[route] as AssistRoute<unknown, unknown>;
  return file.cases.map((raw) => {
    const request = resolveFixtures(raw.request, fixtures);
    const parsed = assist.requestSchema.safeParse(request);
    if (!parsed.success) throw new Error(`case ${raw.id}: request fails the ${route} schema: ${parsed.error.message}`);
    const params = assist.buildRequest(parsed.data, "model");
    return { id: raw.id, tags: raw.tags, request: parsed.data, expect: resolveFixtures(raw.expect, fixtures), prompt: userText(params) };
  });
}

function userText(params: MessageCreateParamsNonStreaming): string {
  const content = params.messages[0]?.content;
  if (typeof content === "string") return content;
  return (content ?? []).map((block) => (block.type === "text" ? block.text : `[${block.type}]`)).join("\n");
}

/** Wraps the client so the eval can read the raw response the route itself never returns. */
class RecordingClient implements AnthropicLike {
  response: ParsedMessage<unknown> | undefined;
  error: unknown;
  private readonly inner: AnthropicLike;

  constructor(inner: AnthropicLike) {
    this.inner = inner;
  }

  readonly messages = {
    parse: async <Params extends MessageCreateParamsNonStreaming>(
      params: Params,
    ): Promise<ParsedMessage<ExtractParsedContentFromParams<Params>>> => {
      try {
        const response = await this.inner.messages.parse(params);
        this.response = response;
        return response;
      } catch (error) {
        this.error = error;
        throw error;
      }
    },
  };
}

export interface TraceTurn {
  role: "system" | "user" | "assistant" | "tool_result";
  content: string;
}

export interface CaseRun {
  /** Parsed model output before the route's output check; null on refusal, truncation or bad JSON. */
  output: unknown;
  /** What the route would answer: "ok", or its error code ("declined", "truncated", "unparseable", "protected_constraint"). */
  outcome: string;
  model: string;
  usage: Usage;
  stop_reason: StopReason | null;
  transcript: TraceTurn[];
}

/** Calls the route. SDK errors are rethrown so the runner can back off or log them as harness failures. */
export async function runCase(route: RouteName, evalCase: EvalCase, client: AnthropicLike, model: string): Promise<CaseRun> {
  const assist = ROUTES[route] as AssistRoute<unknown, unknown>;
  const params = assist.buildRequest(evalCase.request, model);
  const recorder = new RecordingClient(client);
  let result: Awaited<ReturnType<typeof callModel<unknown>>>;
  try {
    result = await callModel(recorder, params, { requestId: `eval-${evalCase.id}`, route: assist.name, model });
  } catch (error) {
    throw recorder.error ?? error;
  }
  if (recorder.error instanceof APIError || recorder.error instanceof APIConnectionError) throw recorder.error;
  const response = recorder.response;
  if (!response) throw new Error("no response recorded");

  let outcome = "ok";
  if (!result.ok) outcome = result.reply.body.error;
  else outcome = assist.checkOutput?.(result.output, evalCase.request)?.body.error ?? "ok";

  const system = Array.isArray(params.system) ? params.system.map((block) => block.text).join("\n") : (params.system ?? "");
  const text = response.content.flatMap((block) => (block.type === "text" ? [block.text] : [])).join("\n");
  const output = response.parsed_output;
  return {
    output,
    outcome,
    model: response.model,
    usage: response.usage,
    stop_reason: response.stop_reason,
    transcript: [
      { role: "system", content: system },
      { role: "user", content: evalCase.prompt },
      { role: "assistant", content: output === null ? text : JSON.stringify(output, null, 2) },
      { role: "tool_result", content: `route outcome: ${outcome} (stop_reason ${response.stop_reason})` },
    ],
  };
}

export function gradeCase(route: RouteName, evalCase: EvalCase, run: CaseRun): Graded {
  switch (route) {
    case "adjust":
      return gradeAdjust(
        evalCase.request as AdjustRequest,
        evalCase.expect as AdjustExpect,
        run.output as AdjustResponse | null,
        run.outcome === "ok",
        ADJUST_SYSTEM_PROMPT,
      );
    case "explain":
      return gradeExplain(evalCase.request as ExplainRequest, evalCase.expect as ExplainExpect, run.output as ExplainResponse | null);
    case "parse-pantry":
      return gradePantry((evalCase.expect as { lines: PantryLine[] }).lines, run.output as ParsePantryResponse | null);
    case "parse-recipe":
      return gradeRecipe(evalCase.expect as RecipeExpect, run.output as ParseRecipeResponse | null);
  }
}
