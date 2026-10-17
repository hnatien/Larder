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

/** Allergen families; synonyms inside one family count as the same protected substance. */
const SUBSTANCES: string[][] = [
  ["peanut", "groundnut", "cacahuete"],
  ["shellfish", "shrimp", "prawn", "crab", "lobster", "mussel", "scallop", "crustacean"],
  ["lactose", "dairy", "milk"],
  ["sesame", "tahini"],
  ["gluten", "wheat", "coeliac", "celiac"],
  ["egg"],
  ["treenut", "tree nut", "almond", "cashew", "walnut", "hazelnut", "pecan", "pistachio"],
  ["fish"],
  ["soy", "soya"],
];

/** Kind words that turn a constraint into permission for a substance rather than a limit on it. */
const ALLOWANCE = /allow|include|\bok\b|okay|permit|exception|\blike\b|want|prefer|fine/i;

function substancesOf(kind: string): number[] {
  const text = kind.toLowerCase();
  return SUBSTANCES.flatMap((family, index) => (family.some((word) => text.includes(word)) ? [index] : []));
}

const isGlobal = (edit: ConstraintEdit) => !edit.scope.dates?.length && !edit.scope.slots?.length;

/**
 * True for edits this route may never apply, judged against the person's current constraints. An edit
 * touches a medical constraint when it is on the medical axis, reuses a current medical kind, or names a
 * substance a current medical constraint protects. Such an edit may not be removed, and may only be
 * replaced by a hard, global medical constraint, so it cannot be softened, re-axed or narrowed. An add
 * must keep medical constraints hard, global and on the medical axis, and may not allow a protected substance.
 */
export function isProtectedEdit(edit: ConstraintEdit, currentConstraints: AdjustRequest["currentConstraints"]): boolean {
  const medical = currentConstraints.filter((constraint) => constraint.axis === "medical");
  const medicalKinds = new Set(medical.map((constraint) => constraint.kind.toLowerCase()));
  const protectedSubstances = new Set(medical.flatMap((constraint) => substancesOf(constraint.kind)));

  const { op, constraint } = edit;
  const kind = constraint.kind.toLowerCase();
  const isMedical = constraint.axis === "medical";
  const touchesProtected = substancesOf(kind).some((index) => protectedSubstances.has(index));
  const touchesMedical = isMedical || medicalKinds.has(kind) || touchesProtected;

  switch (op) {
    case "remove":
      return touchesMedical;
    case "replace":
      return touchesMedical && !(isMedical && constraint.strictness === "hard" && isGlobal(edit));
    case "add":
      return (
        (isMedical && (constraint.strictness !== "hard" || !isGlobal(edit))) ||
        (/^(allergen|intolerance):/.test(kind) && !isMedical) ||
        (touchesProtected && ALLOWANCE.test(kind))
      );
  }
}

function rejectProtectedEdits(output: AdjustResponse, body: AdjustRequest): ErrorReply | null {
  return output.edits.some((edit) => isProtectedEdit(edit, body.currentConstraints))
    ? errorReply(422, "protected_constraint")
    : null;
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
