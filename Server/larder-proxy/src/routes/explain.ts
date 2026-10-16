import { outputFormat } from "../model.js";
import { EXPLAIN_SYSTEM_PROMPT } from "../prompts/explain.js";
import { ExplainRequest, ExplainResponse } from "../schemas.js";
import { cachedSystem, type AssistRoute } from "./route.js";

const format = outputFormat(ExplainResponse);

/** Builds the Messages API request for a plan explanation. Per-user data goes only in the user turn. */
export function buildExplainRequest(body: ExplainRequest, model: string) {
  return {
    model,
    max_tokens: 2048,
    system: cachedSystem(EXPLAIN_SYSTEM_PROMPT),
    messages: [
      {
        role: "user" as const,
        content: `Profile summary:\n${JSON.stringify(body.profileSummary)}\n\nPlan:\n${JSON.stringify({ days: body.plan.days, shelfBalance: body.shelfBalance })}`,
      },
    ],
    output_config: { effort: "low" as const, format },
  };
}

/** POST /v1/assist/explain: free tier, fast model. */
export const explainRoute: AssistRoute<ExplainRequest, ExplainResponse> = {
  name: "explain",
  requiresPlus: false,
  requestSchema: ExplainRequest,
  model: (config) => config.modelFast,
  buildRequest: buildExplainRequest,
};
