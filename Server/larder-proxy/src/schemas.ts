// Request and response contracts for every assist route. The iOS client mirrors these types.
import { z } from "zod";

export const IsoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Expected YYYY-MM-DD");
export const MealSlot = z.enum(["breakfast", "lunch", "dinner", "snack"]);
export const FoodGroup = z.enum(["produce", "grains", "protein", "dairy", "fats", "legumes", "other"]);
export const Goal = z.enum(["eatBetter", "moreVariety", "lessWaste", "saveMoney", "moreProtein", "maintain"]);
export const ConstraintAxis = z.enum(["medical", "religious", "ethical", "preference", "goal"]);
export const Strictness = z.enum(["hard", "soft"]);
export const PantryLocation = z.enum(["fridge", "freezer", "pantry", "other"]);

export const ReasonCode = z.object({
  code: z.string().min(1).max(40),
  params: z.record(z.string().max(40), z.union([z.string().max(80), z.number(), z.boolean()])),
});

export const PlannedMeal = z.object({
  slot: MealSlot,
  recipeTitle: z.string().min(1).max(120),
  minutes: z.number().int().min(0).max(1440),
  reasonCodes: z.array(ReasonCode).max(12),
});

export const PlanDay = z.object({
  date: IsoDate,
  meals: z.array(PlannedMeal).max(6),
});

export const Constraint = z.object({
  axis: ConstraintAxis,
  kind: z.string().min(1).max(80),
  strictness: Strictness,
});

// POST /v1/assist/explain

export const ExplainRequest = z.object({
  plan: z.object({ days: z.array(PlanDay).min(1).max(14) }),
  shelfBalance: z.object({
    groupsLight: z.array(FoodGroup).max(7),
    groupsHeavy: z.array(FoodGroup).max(7),
  }),
  profileSummary: z.object({
    goal: Goal,
    householdSize: z.number().int().min(1).max(12),
    maxCookMinutes: z.number().int().min(5).max(480),
    showsNumbers: z.boolean(),
  }),
});

export const ExplainResponse = z.object({
  // 90 characters is the prompt's target, not a limit: structured outputs cannot enforce maxLength,
  // so a cap here turned a two-character overrun into a 502. The client wraps the text.
  headline: z.string().describe("One sentence of at most 90 characters."),
  perDay: z.array(z.object({ date: IsoDate, sentence: z.string() })),
  swapsOffered: z.array(
    z.object({ date: IsoDate, slot: MealSlot, alternativeTitle: z.string(), reason: z.string() }),
  ),
});

// POST /v1/assist/parse-pantry

export const ParsePantryRequest = z.object({ text: z.string().trim().min(1).max(500) });

export const ParsePantryResponse = z.object({
  lines: z.array(
    z.object({
      rawName: z.string(),
      quantity: z.number().nullable(),
      unit: z.string().nullable(),
      location: PantryLocation.nullable(),
      bestByHint: z.string().nullable(),
    }),
  ),
});

// POST /v1/assist/parse-recipe

export const ImageMediaType = z.enum(["image/jpeg", "image/png", "image/webp"]);

/** Roughly 5 MB of image bytes once base64 encoded, the Messages API per-image ceiling. */
export const MAX_IMAGE_BASE64_LENGTH = 7_000_000;

export const ParseRecipeRequest = z
  .object({
    text: z.string().trim().min(1).max(20_000).optional(),
    imageBase64: z
      .string()
      .min(1)
      .max(MAX_IMAGE_BASE64_LENGTH)
      .regex(/^[A-Za-z0-9+/]+={0,2}$/, "Expected base64")
      .optional(),
    imageMediaType: ImageMediaType.optional(),
  })
  .refine((body) => body.text !== undefined || body.imageBase64 !== undefined, {
    message: "Provide text, an image, or both",
  })
  .refine((body) => (body.imageBase64 === undefined) === (body.imageMediaType === undefined), {
    message: "imageBase64 and imageMediaType go together",
    path: ["imageMediaType"],
  });

export const ParseRecipeResponse = z.object({
  title: z.string(),
  servings: z.number().int().nullable(),
  prepMinutes: z.number().int().nullable(),
  cookMinutes: z.number().int().nullable(),
  ingredients: z.array(
    z.object({
      rawText: z.string(),
      quantity: z.number().nullable(),
      unit: z.string().nullable(),
      name: z.string(),
      optional: z.boolean(),
    }),
  ),
  steps: z.array(z.object({ text: z.string(), timerSeconds: z.number().int().nullable() })),
  tags: z.object({ cuisine: z.string().nullable(), mealType: MealSlot.nullable() }),
});

// POST /v1/assist/adjust

/** One earlier turn of the adjust chat: what the person said, or what Larder asked or proposed back. */
export const AdjustTurn = z.object({
  role: z.enum(["person", "larder"]),
  text: z.string().trim().min(1).max(300),
});

export const AdjustRequest = z.object({
  instruction: z.string().trim().min(1).max(300),
  conversation: z.array(AdjustTurn).max(8).optional(),
  currentConstraints: z.array(Constraint).max(60),
  planContext: z.object({ days: z.array(PlanDay).max(14) }),
});

export const ConstraintEdit = z.object({
  op: z.enum(["add", "remove", "replace"]),
  constraint: Constraint,
  scope: z.object({ dates: z.array(IsoDate).optional(), slots: z.array(MealSlot).optional() }),
});

export const AdjustResponse = z.object({
  edits: z.array(ConstraintEdit),
  clarifyingQuestion: z.string().nullable(),
});

export type ExplainRequest = z.infer<typeof ExplainRequest>;
export type ExplainResponse = z.infer<typeof ExplainResponse>;
export type ParsePantryRequest = z.infer<typeof ParsePantryRequest>;
export type ParsePantryResponse = z.infer<typeof ParsePantryResponse>;
export type ParseRecipeRequest = z.infer<typeof ParseRecipeRequest>;
export type ParseRecipeResponse = z.infer<typeof ParseRecipeResponse>;
export type AdjustRequest = z.infer<typeof AdjustRequest>;
export type AdjustResponse = z.infer<typeof AdjustResponse>;
export type ConstraintEdit = z.infer<typeof ConstraintEdit>;
