import { errorReply, type ErrorReply } from "../http.js";
import { outputFormat } from "../model.js";
import { ADJUST_SYSTEM_PROMPT } from "../prompts/adjust.js";
import { AdjustRequest, AdjustResponse, type ConstraintEdit } from "../schemas.js";
import { cachedSystem, type AssistRoute } from "./route.js";

const format = outputFormat(AdjustResponse);

/** Builds the Messages API request for a conversational constraint change. */
export function buildAdjustRequest(body: AdjustRequest, model: string) {
  return {
    model,
    max_tokens: 2048,
    system: cachedSystem(ADJUST_SYSTEM_PROMPT),
    messages: [
      {
        role: "user" as const,
        content: `Instruction:\n${body.instruction}\n\nCurrent constraints:\n${JSON.stringify(body.currentConstraints)}\n\nPlan:\n${JSON.stringify(body.planContext.days)}`,
      },
    ],
    output_config: { effort: "medium" as const, format },
  };
}

/** True for edits this route may never apply: removing a medical constraint, or replacing one with anything but hard. */
export function isProtectedEdit(edit: ConstraintEdit): boolean {
  if (edit.constraint.axis !== "medical") return false;
  return edit.op === "remove" || (edit.op === "replace" && edit.constraint.strictness !== "hard");
}

function rejectProtectedEdits(output: AdjustResponse): ErrorReply | null {
  return output.edits.some(isProtectedEdit) ? errorReply(422, "protected_constraint") : null;
}

/** POST /v1/assist/adjust: Plus only, capable model, medical constraints protected in code as well as in the prompt. */
export const adjustRoute: AssistRoute<AdjustRequest, AdjustResponse> = {
  name: "adjust",
  requiresPlus: true,
  requestSchema: AdjustRequest,
  model: (config) => config.modelCapable,
  buildRequest: buildAdjustRequest,
  checkOutput: rejectProtectedEdits,
};
