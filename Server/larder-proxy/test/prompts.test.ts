import { describe, expect, it } from "vitest";
import { ADJUST_SYSTEM_PROMPT } from "../src/prompts/adjust.js";
import { EXPLAIN_SYSTEM_PROMPT } from "../src/prompts/explain.js";
import { PARSE_PANTRY_SYSTEM_PROMPT } from "../src/prompts/parsePantry.js";
import { PARSE_RECIPE_SYSTEM_PROMPT } from "../src/prompts/parseRecipe.js";
import { buildAdjustRequest } from "../src/routes/adjust.js";
import { buildExplainRequest } from "../src/routes/explain.js";
import { buildParsePantryRequest } from "../src/routes/parsePantry.js";
import { buildParseRecipeRequest } from "../src/routes/parseRecipe.js";
import type { ExplainRequest } from "../src/schemas.js";

const explainFor = (title: string, date: string, goal: ExplainRequest["profileSummary"]["goal"]): ExplainRequest => ({
  plan: { days: [{ date, meals: [{ slot: "dinner", recipeTitle: title, minutes: 20, reasonCodes: [] }] }] },
  shelfBalance: { groupsLight: [], groupsHeavy: ["grains"] },
  profileSummary: { goal, householdSize: 3, maxCookMinutes: 40, showsNumbers: true },
});

const systemText = (system: unknown) => JSON.stringify(system);

describe("prompt caching invariants", () => {
  const a = buildExplainRequest(explainFor("Zucchini fritters", "2026-10-16", "eatBetter"), "m");
  const b = buildExplainRequest(explainFor("Lamb hotpot", "2027-02-01", "saveMoney"), "m");

  it("keeps the first system block identical across users and dates, with a cache breakpoint", () => {
    expect(a.system[0]).toEqual(b.system[0]);
    expect(a.system).toHaveLength(1);
    expect(a.system[0]).toEqual({ type: "text", text: EXPLAIN_SYSTEM_PROMPT, cache_control: { type: "ephemeral" } });
  });

  it("puts no user-provided string in system and all of it in the user turn", () => {
    for (const needle of ["Zucchini fritters", "2026-10-16", "eatBetter"]) {
      expect(systemText(a.system)).not.toContain(needle);
      expect(JSON.stringify(a.messages)).toContain(needle);
    }
  });

  it("passes the same output format object on every call", () => {
    expect(a.output_config.format).toBe(b.output_config.format);
  });

  it("holds for every route", () => {
    const pantry = [buildParsePantryRequest({ text: "kimchi jar" }, "m"), buildParsePantryRequest({ text: "oat milk" }, "m")] as const;
    const recipe = [
      buildParseRecipeRequest({ text: "Grandma Rosa's gnocchi" }, "m"),
      buildParseRecipeRequest({ imageBase64: "AAAA", imageMediaType: "image/png" }, "m"),
    ] as const;
    const adjust = [
      buildAdjustRequest({ instruction: "no okra", currentConstraints: [], planContext: { days: [] } }, "m"),
      buildAdjustRequest({ instruction: "more tofu", currentConstraints: [], planContext: { days: [] } }, "m"),
    ] as const;
    for (const [first, second] of [pantry, recipe, adjust]) {
      expect(first.system).toEqual(second.system);
      expect(first.output_config.format).toBe(second.output_config.format);
    }
    for (const needle of ["kimchi jar", "Grandma Rosa", "no okra"]) {
      expect(systemText([pantry[0].system, recipe[0].system, adjust[0].system])).not.toContain(needle);
    }
  });

  it("keeps system prompts free of volatile content", () => {
    for (const prompt of [EXPLAIN_SYSTEM_PROMPT, PARSE_PANTRY_SYSTEM_PROMPT, PARSE_RECIPE_SYSTEM_PROMPT, ADJUST_SYSTEM_PROMPT]) {
      expect(prompt).not.toMatch(/\$\{|undefined|\d{4}-\d{2}-\d{2}/);
      expect(prompt).not.toMatch(/[–—!]/);
    }
  });

  it("states the protected-constraint rule in the adjust prompt", () => {
    expect(ADJUST_SYSTEM_PROMPT).toMatch(/can be added but never removed/);
  });

  it("states the dozen and same-unit merge rules in the pantry prompt", () => {
    expect(PARSE_PANTRY_SYSTEM_PROMPT).toMatch(/A dozen is a count, not a unit/);
    expect(PARSE_PANTRY_SYSTEM_PROMPT).toMatch(/Singular and plural forms are the same unit/);
    expect(PARSE_PANTRY_SYSTEM_PROMPT).toMatch(/Keep separate lines when the units differ/);
  });
});
