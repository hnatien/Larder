import type { TextBlockParam } from "@anthropic-ai/sdk/resources/messages";
import type { z } from "zod";
import type { Config } from "../env.js";
import type { ErrorReply } from "../http.js";
import type { AssistParams } from "../model.js";

/** Declarative description of one assist route; `app.ts` runs the shared auth, quota and model flow. */
export interface AssistRoute<Req, Res> {
  name: string;
  requiresPlus: boolean;
  requestSchema: z.ZodType<Req>;
  model(config: Config): string;
  buildRequest(body: Req, model: string): AssistParams<Res>;
  checkOutput?(output: Res, body: Req): ErrorReply | null;
}

/** The static system prompt as the first and only system block, marked as the cache breakpoint. */
export function cachedSystem(prompt: string): TextBlockParam[] {
  return [{ type: "text", text: prompt, cache_control: { type: "ephemeral" } }];
}
