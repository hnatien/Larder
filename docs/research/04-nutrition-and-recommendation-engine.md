# Larder research 04: nutrition data, recommendation engine, LLM integration

Researched 2026-10-16. "[unverified]" means the claim could not be confirmed in a primary source. Not legal advice.

## 1. Nutrition data sources

| Source | License / terms | Bundle offline? | Cost |
|---|---|---|---|
| USDA FoodData Central (FDC) | CC0, attribution requested. API key, 1,000 req/hour/IP (http://fdc.nal.usda.gov/api-guide/) | Yes | Free |
| Open Food Facts (OFF) | Database ODbL, contents DbCL, images CC BY-SA (https://world.openfoodfacts.org/data) | Only with share-alike consequences | Free |
| Spoonacular | Only id, title, image URL may be stored; 1-hour cache | No | Free tier then $29-149/mo |
| Edamam | Charged per analysed recipe; ETag must be stored | Unclear | Not listed |
| FatSecret | Basic free for evaluation; Premier contact sales | Unknown | Contact sales |
| Nutritionix | Could not verify current tiers | Unknown | Unknown |

FDC details: Foundation (3.7 MB), SR Legacy (6.7 MB, final 04/2018), FNDDS (200 MB), Branded (428 MB, monthly, industry-supplied label data searchable by GTIN). Foundation and Branded re-released 04/2026. Foundation and SR Legacy are the only small, analytically derived sets.

OFF details: attribution mandatory ("Contains data from Open Food Facts, available under the Open Database License"); 15 req/min reads, 10/min search; volunteer-contributed with no accuracy assurance. Showing live results is a "produced work" (attribution only); merging rows into a shipped database is a derivative database (share-alike). Counsel before bulk ingest.

Recommendation: primary FDC Foundation + SR Legacy plus trimmed FNDDS portions, bundled as SQLite with attribution. Barcodes via FDC Branded GTIN lookup through the backend proxy (key server-side, rows cached). Fallback OFF live lookup labelled "community data, unverified", kept in a separate table. Skip paid APIs in v1.

## 2. Recipe data

- Law: a mere list of ingredients or simple directions is uncopyrightable; creative prose and photos are protected (https://www.copyright.gov/circs/circ33.pdf).
- Datasets: Recipe1M+ (CC BY-NC-SA) and RecipeNLG (non-commercial) are excluded. No CC0/CC-BY recipe corpus suitable for commercial use was found.
- USDA MyPlate Kitchen (900+ recipes with nutrition) and Child Nutrition Recipe Box are federal works, generally public domain [page-level notices unverified]; institutional style.
- LLM-generated originals are the cheapest, cleanest option: about $6 for 500 recipes via Batch on Sonnet 5.5. Risk is quality, not copyright. Every recipe must pass a deterministic validator: ingredient-to-FDC match, nutrient computation, allergen tagging, plausibility bounds, de-duplication, editorial spot-check. Never trust LLM-stated nutrients: a 2026 study found LLM meal plans 284-546 kcal under target, 63-94% outside ±10% (https://pmc.ncbi.nlm.nih.gov/articles/PMC13415864/).
- User import via schema.org/Recipe JSON-LD: no authoritative ruling; risk is site terms and copying prose or photos. Fetch on-device only when the user asks; store structured fields plus source URL; don't copy images; never feed imports into a shared corpus.

Recommendation: seed v1 with 300-500 LLM-generated, validator-gated recipes plus USDA public recipes after a licence check. Ship private, on-device JSON-LD import as a feature. Lawyer review before launch.

## 3. Dietary guidance to encode

DGA 2025-2030 (released 2026-01-07, https://cdn.realfood.gov/DGA.pdf): protein at every meal, 1.2-1.6 g/kg/day; dairy 3, vegetables 3, fruit 2, whole grains 2-4 servings at 2,000 kcal; saturated fat ≤10% kcal; added sugar no recommended amount and ≤10 g per meal; sodium <2,300 mg (14+), children 1,200 / 1,500 / 1,800 by age; "highly processed" undefined; chronic disease: consult a clinician. Critique: full-fat dairy plus butter can exceed 22 g saturated fat (Harvard).

WHO: free sugars <10% energy (<5% better); saturated fat <10%, trans <1%; salt <5 g (sodium <2 g); at least 400 g fruit and vegetables.

HEI-2020 (https://epi.grants.cancer.gov/hei/hei-2020-table1.html): 13 components, 100 points, per 1,000 kcal. Full-credit thresholds: fruit ≥0.8 cup-eq, vegetables ≥1.1, whole grains ≥1.5 oz-eq, dairy ≥1.3, refined grains ≤1.8 oz-eq, sodium ≤1.1 g, added sugars <6.5% energy, saturated fat ≤8%, unsaturated:saturated ≥2.5. Needs ingredient-to-food-group mapping.

Patterns: Mediterranean (PREDIMED-Plus diabetes HR 0.67), DASH (BP down about 3.3/2.1 mmHg; largest effect in an umbrella review). Fibre AI 14 g per 1,000 kcal; protein RDA 0.8 g/kg (DGA's 1.2-1.6 is a policy shift, not a new RDA). Ultra-processed food: UPDATE trial 2.06% vs 1.05% weight loss; NOVA "lacks sufficient precision" for individual foods.

Serving conventions: grams canonical; household measures from FDC portions; targets per 1,000 kcal or % energy.

Recommendation: drive recommendations with energy, sodium, saturated fat %, added sugar (where data exists), fibre, protein as a range, HEI-style food-group density. Protein floor 0.8 g/kg, goal up to 1.2-1.6 for adults; never auto-raise for kidney disease or under 18. Tag each NutrientTarget with its source (DGA2025, WHO, custom). NOVA only as a soft flag on packaged items. Avoid glycaemic index, superfood logic, micronutrient-completeness scoring from recipe-level estimates, weight-loss targets for minors, pregnancy or ED history.

## 4. Recommendation engine architecture

| Approach | Strength | Weakness |
|---|---|---|
| Rules / constraint solver | Guarantees allergies, nutrient bands, pantry, budget, time | Needs a taste signal; infeasible for narrow diets |
| Collaborative filtering | Taste discovery | Cold start, optimises popularity (hurts healthiness), privacy |
| Content embeddings | Works day 1 | Taste bubble, no nutrition guarantees |
| LLM-driven planning | Flexible, conversational | Nutritionally unreliable, not auditable, violates constraints |
| Hybrid | Solver guarantees, LLM explains | More engineering |

Research basis: Trattner and Elsweiler (https://arxiv.org/pdf/1711.02760): standard recommenders yield unhealthy lists; per-item recommendation "will not lead to healthy nutrition", so compose at plan level; their plan generator found plans for 63% of personas. 2025 IEEE Access review: recommenders' direct effect is limited, nudges help. 2026 JMIR review: 6 of 15 chronic-disease recommenders constraint-based, 4 hybrid.

Design:
- Allergies are hard constraints in code with two independent checks: a SQL pre-filter on ingredient allergen masks, and a post-hoc verifier on the final plan and every LLM-originated edit, using synonym and derivative lists (tahini is sesame, ghee is milk). US top 9 plus EU 14. The LLM never holds the allergen list as its guard; it only receives pre-filtered candidates.
- Plan composition: beam search or swap-based local search in Swift over a pruned pool of about 200 recipes. Objective: taste + pantry overlap and expiry + cost + time − HEI-style deviation. Daily energy within ±10-15%; micronutrients as weekly averages.
- Explainability: the solver emits reason codes and subscore deltas; the LLM only verbalises them.
- Cold start: hard constraints do most of the work; about 12 swipe-to-pick recipes spanning cuisines and proteins; content scoring with population priors; no collaborative filtering until logs exist.
- Monotony: decay on recently planned recipes, 14-day cooldown, protein and cuisine quotas, MMR diversity, deliberate leftover slots.
- Offline evaluation: zero hard-constraint violations on an adversarial suite; nutrient-band adherence and HEI score vs baselines; diversity and repeat rate; pantry use and cost; feasibility across 100+ personas; explanation faithfulness via template slots plus an LLM judge; nDCG once logs exist. Online: plan acceptance, swaps per plan, cooked rate, 4-week retention.

Recommendation: hybrid. v1 is deterministic filter, content scoring, local-search planner and verifier; the LLM explains, ranks solver-provided swaps and parses input.

## 5. LLM integration

LLM-suitable: plan explanations and swap rationale (ranking the solver's top 5-10 candidates); "use up these 3 ingredients" phrasing; natural-language pantry entry; recipe parsing from photo or URL text; conversational adjustments producing a structured constraint change the solver re-plans from.

Deterministic: nutrient math, allergen filtering, totals, unit conversion, scaling, scheduling, any number shown to users.

Prompt structure: static system prompt (role, safety rules, schema, tone), then a stable profile summary, then the volatile request; cache breakpoint after the static prefix (512-token minimum on Sonnet 5.5 and Haiku 5.5). The 5-minute TTL means a per-user profile rarely hits at 30 requests/month, but the shared system prompt hits across users.

Structured output: `output_config.format` JSON Schema (no minimum/maximum, no recursion, 24 optional parameters), so validate ranges client-side. Forced `tool_choice` returns 400 on Sonnet 5.5; use structured outputs or auto with strict. Every mutating tool re-runs the allergen verifier; the user confirms before commit. Keep schemas static.

Budgets: input capped at 3k tokens (a 21-meal compact plan is about 800); max_tokens 300 for parsing, 800 for explanation; low effort for extraction. Latency targets (estimates): parsing under 1.5 s, explanation first token under 1 s and complete under 6 s, chat streamed.

Cost per user-month at 30 requests × 3k in + 800 out, list prices, no thinking:

| Model | No cache | 1.5k shared prefix cached |
|---|---|---|
| Haiku 5.5 ($0.10 / $0.50) | $0.021 | $0.017 |
| Sonnet 5.5 ($2 / $10) | $0.42 | $0.33 |
| Opus 5.5 ($4 / $20) | $0.84 | about $0.67 |

Output dominates. Adaptive thinking at about 1,500 tokens per request would lift Sonnet 5.5 to roughly $0.80. Batch is 50% off but not eligible for zero data retention; use it only for offline recipe generation.

Small vs mid-tier: with the solver grounding everything, Haiku 5.5 should suffice for pantry parsing, ingredient-line parsing, tagging and explanations from reason codes. Sonnet 5.5 should earn its cost on messy photo or OCR recipes, multi-constraint chat edits, clarifying questions and tone around sensitive conditions. No public benchmark exists for this use case; run an eval of about 200 labelled cases per task. Opus is unnecessary.

Apple Foundation Models (https://developer.apple.com/videos/play/wwdc2026/241/): on-device context 8,192 tokens on iOS 27 (4,096 on iOS 26.0); guided generation, tool calling, image input, `BarcodeReaderTool`, `OCRTool`; Private Cloud Compute model with 32K context, free under 2M first-time downloads; a `LanguageModel` protocol lets Anthropic's Swift package slot in. Needs Apple Intelligence devices.

Recommendation: an `AssistantBackend` protocol; on-device Foundation Models for pantry parsing and barcode/OCR flows; Haiku 5.5 as server default for structured tasks; Sonnet 5.5 for explanations, photo parsing and chat; everything through the backend proxy; plan for about $0.40 per user-month at default usage.

## 6. Privacy and compliance

- HIPAA: a consumer app is likely not covered unless contracting with providers or insurers.
- FTC Health Breach Notification Rule applies to non-HIPAA health apps; "breach" includes unauthorised disclosure to ad or analytics SDKs; notice within 60 days (https://www.ftc.gov/news-events/news/press-releases/2024/04/ftc-finalizes-changes-health-breach-notification-rule).
- GDPR: allergies and conditions are Article 9 health data (explicit consent); religious diets may reveal religion; Ireland's DPC treated "Coeliac Mailing" labelling as a breach. Separate granular consent screen, on-device by default, no analytics on these fields.
- App Store: 5.1.2(i) disclosure and permission before sharing with third-party AI; 5.1.3 no health data for advertising or mining; 1.4.1 methodology disclosure and see-a-doctor reminder; privacy label depends on retention.
- Anthropic (https://platform.claude.com/docs/en/manage-claude/api-and-data-retention): API inputs and outputs deleted within 30 days; not used for training without permission; zero data retention per organisation by agreement (covers Messages API and prompt caching; Batch not eligible; Fable and Mythos require 30-day retention).
- Keeping PII out of prompts: compute targets on-device and send only codes and numbers (no name, email, location, exact weight, date of birth); send derived flags like "avoid_sodium_high", not "hypertension"; scrub free text on-device before sending; never put user data in JSON schemas; random per-request IDs; don't forward IPs; don't log prompts against user IDs.

Recommendation: day-one requirements are a consent screen before the first AI call, on-device-first storage, a PII-free prompt builder, a medical disclaimer, a zero-data-retention request once on a paid plan, and counsel review for GDPR and Washington before launch there.

## Data model sketch (v1)

- Food: id, fdcId?, gtin?, source (fdc_foundation | sr_legacy | fdc_branded | off_unverified), name, nutrientsPer100g (energy, protein, fat, satFat, mono/poly, carbs, fibre, totalSugar, addedSugar?, sodium, potassium, calcium, iron, vitD, B12), portions[(label, grams)], foodGroup, allergenMask, dietFlags, novaHint?, licenseTag.
- Recipe: id, title, origin (generated | usda | user_import), sourceURL?, license, servings, prepMin, cookMin, steps[], tags (cuisine, mealType, equipment), dietFlags, allergenMask (derived), nutritionPerServing (cached with engineVersion), validationState, createdAt.
- Ingredient (recipe line): recipeId, rawText, quantity, unit, foodId, gramsResolved, matchConfidence, optional, isGarnish.
- PantryItem: id, foodId?, rawName, quantityGrams, unit, location, expiresOn?, source (manual | barcode | nl).
- UserProfile (local only): id, birthYear, sex, heightCm, weightKg, activityLevel, goal, householdSize, budgetPerWeek, maxCookMin, equipment, consents{aiProcessing, cloudSync}.
- DietaryConstraint: id, type (allergen | intolerance | diet | medical | dislike | religious), code, severity (hard | soft), foodId?, source (user | derived), note.
- NutrientTarget: nutrientCode, basis (per_day | per_meal | per_1000kcal | pct_energy), min, target, max, tolerance, priority, sourceTag (DGA2025 | WHO | custom | clinician).
- MealPlan: id, startDate, days, constraintsSnapshot, solverVersion, seed, scoreBreakdown, status.
- PlannedMeal: id, planId, date, slot, recipeId, servings, leftoverOfId?, locked, status (planned | cooked | skipped), reasonCodes[], nutritionSnapshot, swapHistory[].

## Recommendation pipeline

```
UserProfile + DietaryConstraint + NutrientTarget (on-device)
  -> [1] Compile constraints (hard vs soft; targets per day/week)
  -> [2] HARD FILTER (SQL): allergens, diet, medical, equipment, time    <- no LLM
  -> [3] SCORE: taste (content features + likes/skips) + pantry/expiry + cost + novelty decay
  -> [4] PLAN SEARCH (beam/local search): nutrient bands, variety quotas, leftovers
  -> [5] VERIFY (independent code path): allergen re-check, nutrient totals, HEI-style score.
         Fail -> repair swap or re-run [4]
  -> [6] LLM LAYER (via backend, PII-free, structured output): explain from reason codes,
         rank solver swap candidates, parse NL/photo input, turn chat into constraint edits
  -> [7] POST-LLM VALIDATE: schema check, numbers via template slots; any new or edited
         recipe re-enters the ingestion validator + [5]
  -> UI: plan + "why" + user confirm; cooked/skipped logs feed [3]
```
