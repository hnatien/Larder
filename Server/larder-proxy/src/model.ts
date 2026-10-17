import {
  AnthropicError,
  APIConnectionError,
  APIError,
  AuthenticationError,
  RateLimitError,
} from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import type {
  AutoParseableOutputFormat,
  ExtractParsedContentFromParams,
  ParsedMessage,
} from "@anthropic-ai/sdk/lib/parser";
import { transformJSONSchema, type JSONSchema } from "@anthropic-ai/sdk/lib/transform-json-schema";
import type { MessageCreateParamsNonStreaming } from "@anthropic-ai/sdk/resources/messages";
import { z } from "zod";
import { errorReply, type ErrorReply } from "./http.js";

/** The slice of the Anthropic client the proxy calls; the real SDK client satisfies it. */
export interface AnthropicLike {
  messages: {
    parse<Params extends MessageCreateParamsNonStreaming>(
      params: Params,
    ): PromiseLike<ParsedMessage<ExtractParsedContentFromParams<Params>>>;
  };
}

/** Parameters an assist route sends, typed by the route's response shape. */
export type AssistParams<T> = MessageCreateParamsNonStreaming & {
  output_config: { effort: "low" | "medium"; format: AutoParseableOutputFormat<T | null> };
};

/**
 * Structured-output format whose parser yields null instead of throwing. The SDK parses inside
 * `messages.parse`, so a refusal or truncated JSON would otherwise throw before `stop_reason`
 * could be read; with this wrapper the caller checks `stop_reason` first and then null output.
 */
export function outputFormat<T>(schema: z.ZodType<T>): AutoParseableOutputFormat<T | null> {
  const strict = zodOutputFormat(schema);
  return {
    ...strict,
    schema: strictJsonSchema(schema),
    parse(content: string): T | null {
      try {
        return strict.parse(content);
      } catch (error) {
        if (error instanceof AnthropicError) return null;
        throw error;
      }
    },
  };
}

/** Keywords structured outputs enforces that the SDK's schema transform still demotes to `description` text. */
const RESTORED_KEYWORDS = ["enum", "const"] as const;

/**
 * The JSON Schema sent as the output format. The SDK transform strips keywords the API cannot
 * enforce, but it strips `enum` and `const` too, which leaves the model free to answer outside an
 * enum (adjust once returned axis "diet"). They are taken out before the transform and put back after.
 */
export function strictJsonSchema(schema: z.ZodType): JSONSchema {
  const source: JSONSchema = z.toJSONSchema(schema, { reused: "ref" });
  const stripped = structuredClone(source);
  forEachNodePair(stripped, stripped, (_from, node) => {
    for (const key of RESTORED_KEYWORDS) delete node[key];
  });
  const strict = transformJSONSchema(stripped);
  forEachNodePair(source, strict, (from, to) => {
    for (const key of RESTORED_KEYWORDS) if (key in from) to[key] = from[key];
  });
  return strict;
}

/** Visits each schema node with its counterpart in a second tree, following the keywords the SDK transform recurses into. */
function forEachNodePair(from: JSONSchema, to: JSONSchema, visit: (from: JSONSchema, to: JSONSchema) => void): void {
  visit(from, to);
  for (const key of ["properties", "$defs"]) {
    for (const [name, child] of Object.entries<JSONSchema>(from[key] ?? {})) {
      const counterpart = to[key]?.[name];
      if (counterpart) forEachNodePair(child, counterpart, visit);
    }
  }
  if (from.items && to.items) forEachNodePair(from.items, to.items, visit);
  const fromVariants: JSONSchema[] | undefined = from.anyOf ?? from.oneOf ?? from.allOf;
  const toVariants: JSONSchema[] | undefined = to.anyOf ?? to.oneOf ?? to.allOf;
  fromVariants?.forEach((variant, index) => {
    const counterpart = toVariants?.[index];
    if (counterpart) forEachNodePair(variant, counterpart, visit);
  });
}

/** One line per model call: sizes and timings only, never prompt or output content. */
export interface CallLog {
  requestId: string;
  route: string;
  model: string;
}

/** Calls the model and maps every outcome to either parsed output or an `ErrorReply`. */
export async function callModel<T>(
  anthropic: AnthropicLike,
  params: AssistParams<T>,
  log: CallLog,
): Promise<{ ok: true; output: T } | { ok: false; reply: ErrorReply }> {
  const started = Date.now();
  const emit = (status: number, usage?: ParsedMessage<unknown>["usage"]) =>
    console.log(
      JSON.stringify({
        event: "model_call",
        requestId: log.requestId,
        route: log.route,
        model: log.model,
        status,
        latencyMs: Date.now() - started,
        inputTokens: usage?.input_tokens ?? null,
        outputTokens: usage?.output_tokens ?? null,
        cacheReadInputTokens: usage?.cache_read_input_tokens ?? null,
        cacheCreationInputTokens: usage?.cache_creation_input_tokens ?? null,
      }),
    );

  let response: ParsedMessage<T | null>;
  try {
    response = await anthropic.messages.parse(params);
  } catch (error) {
    const reply = mapSdkError(error, log);
    emit(reply.status);
    return { ok: false, reply };
  }

  const fail = (reply: ErrorReply) => {
    emit(reply.status, response.usage);
    return { ok: false as const, reply };
  };
  if (response.stop_reason === "refusal") {
    return fail(errorReply(422, "declined", { category: response.stop_details?.category ?? null }));
  }
  if (response.stop_reason === "max_tokens") return fail(errorReply(502, "truncated"));
  const output = response.parsed_output;
  if (output === null) return fail(errorReply(502, "unparseable"));
  emit(200, response.usage);
  return { ok: true, output };
}

function mapSdkError(error: unknown, log: CallLog): ErrorReply {
  if (error instanceof RateLimitError) return errorReply(429, "upstream_rate_limited");
  if (error instanceof AuthenticationError) {
    console.error(JSON.stringify({ event: "upstream_auth_failed", requestId: log.requestId, route: log.route }));
    return errorReply(500, "internal_error");
  }
  if (error instanceof APIConnectionError) return errorReply(503, "upstream_unavailable");
  if (error instanceof APIError) return errorReply(502, "upstream_error", { upstreamStatus: error.status ?? null });
  throw error;
}
