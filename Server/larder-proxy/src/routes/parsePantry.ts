import { outputFormat } from "../model.js";
import { PARSE_PANTRY_SYSTEM_PROMPT } from "../prompts/parsePantry.js";
import { ParsePantryRequest, ParsePantryResponse } from "../schemas.js";
import { cachedSystem, type AssistRoute } from "./route.js";

const format = outputFormat(ParsePantryResponse);

/** Builds the Messages API request for natural-language pantry entry. */
export function buildParsePantryRequest(body: ParsePantryRequest, model: string) {
  return {
    model,
    max_tokens: 1024,
    system: cachedSystem(PARSE_PANTRY_SYSTEM_PROMPT),
    messages: [{ role: "user" as const, content: `Note:\n${body.text}` }],
    output_config: { effort: "low" as const, format },
  };
}

/** POST /v1/assist/parse-pantry: free tier, fast model. */
export const parsePantryRoute: AssistRoute<ParsePantryRequest, ParsePantryResponse> = {
  name: "parse-pantry",
  requiresPlus: false,
  requestSchema: ParsePantryRequest,
  model: (config) => config.modelFast,
  buildRequest: buildParsePantryRequest,
};
