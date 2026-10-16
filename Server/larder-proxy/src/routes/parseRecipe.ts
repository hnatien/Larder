import type { ContentBlockParam } from "@anthropic-ai/sdk/resources/messages";
import { outputFormat } from "../model.js";
import { PARSE_RECIPE_SYSTEM_PROMPT } from "../prompts/parseRecipe.js";
import { ParseRecipeRequest, ParseRecipeResponse } from "../schemas.js";
import { cachedSystem, type AssistRoute } from "./route.js";

const format = outputFormat(ParseRecipeResponse);

/** Builds the Messages API request for recipe parsing; the image block, when present, precedes the text. */
export function buildParseRecipeRequest(body: ParseRecipeRequest, model: string) {
  const content: ContentBlockParam[] = [];
  if (body.imageBase64 !== undefined && body.imageMediaType !== undefined) {
    content.push({
      type: "image",
      source: { type: "base64", media_type: body.imageMediaType, data: body.imageBase64 },
    });
  }
  content.push({
    type: "text",
    text: body.text === undefined ? "Extract the recipe from the image." : `Recipe text:\n${body.text}`,
  });
  return {
    model,
    max_tokens: 1024,
    system: cachedSystem(PARSE_RECIPE_SYSTEM_PROMPT),
    messages: [{ role: "user" as const, content }],
    output_config: { effort: "medium" as const, format },
  };
}

/** POST /v1/assist/parse-recipe: Plus only, capable model. */
export const parseRecipeRoute: AssistRoute<ParseRecipeRequest, ParseRecipeResponse> = {
  name: "parse-recipe",
  requiresPlus: true,
  requestSchema: ParseRecipeRequest,
  model: (config) => config.modelCapable,
  buildRequest: buildParseRecipeRequest,
};
