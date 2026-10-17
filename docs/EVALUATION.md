# Larder planner evaluation

How the deterministic planner is evaluated offline against baselines, and the first results. The harness is the
`LarderBench` executable target (`Sources/LarderBench`); its smoke and unit tests are in `Tests/LarderBenchTests`.

Reviews of food recommender research (Trattner and Elsweiler 2017; Bondevik et al. 2024) point out that most systems
are scored one recipe at a time, offline, on ratings. Few are scored on whole plans or on what happens in a kitchen
afterwards. This harness scores whole weeks over several weeks of simulated use. It measures what the product claims:
less waste, fewer new purchases, variety over weeks and nutrient-band adherence, with hard-constraint safety as a gate.
It is still a simulation, not a user study (see Limitations).

## Running it

```bash
swift run LarderBench --households 20 --weeks 2                         # quick run, debug build
swift run -c release LarderBench --seed 42 --households 100 --weeks 4   # the run reported below
swift run LarderBench --help
```

Flags: `--seed` (default 42), `--households` (default 100), `--weeks` (default 4), `--out` (CSV directory, default
`./bench-results`, which git ignores), `--data` (seed JSON directory), `--llm-plans` (extra arm, see below) and
`--export-households` (writes the generated households as JSON). Each run writes one CSV with a row per household and
arm, and prints a Markdown summary to stdout. Everything except solve time can be reproduced exactly: the same flags
always give the same CSV.

## Method

**Data.** The 113 seed foods and 42 seed recipes come straight from `App/Larder/Resources/Seed`. A small decoder reads
them, with no database involved, and gives them the same slug-derived identifiers as `SeedLoader`. Plans are 7-day,
dinner-only weeks (the app's default), so 24 of the 42 recipes can be planned.

**Synthetic households.** Household *i* is generated from the seed and *i* alone. It gets:

- A persona, drawn uniformly. Three come from the planning tests: tree-nut allergy, coeliac disease and vegan. The
  others are one allergen (milk, egg, peanut, sesame, fish, crustacean or soy), hypertension, chronic kidney disease,
  time-poor (a 30-minute cooking cap) and unrestricted. A fifth of households add hypertension or time-poor on top.
- A profile: age, sex, height, weight, activity level, goal (any of the six), household size (1 to 5, weighted toward
  2) and a time cap of 40 to 90 minutes. Nutrient targets come from `NutrientTargets.defaults`.
- A starting pantry: 6 to 12 perishables and 5 to 10 staples, drawn from foods the household's admitted dinners use.
  Perishables have 1 to 14 days to their best-by; staples have 30 to 365.
- A behaviour model: per dinner, a 5 to 25% chance of skipping it and a 0 to 20% chance of cooking the top Tonight pick
  instead; per week, a 10 to 60% chance of also buying one to three packs of perishables nobody planned for.

**Simulation, per household and arm, for W rolling weeks.**

1. Build the scoring context the way `PlanningService.context` does: the real pantry, recency over 28 days, cuisines
   over 7 days and `TasteAffinity` learned from 90 days of simulated history.
2. Ask the arm for the week's plan. Time the call and check the plan with `PlanVerifier`.
3. Shop once for the week. `GroceryListBuilder` lists what the plan needs net of the pantry, and each line is bought
   in whole packs (produce 250 g, protein 400 g, dairy 500 g, grains and legumes 500 g, fats 250 g, other 100 g). The
   shelf life of what is bought depends on its food group.
4. Go through the week day by day:
   - A leftover is eaten if its source dinner was cooked.
   - Otherwise the household skips the dinner, or swaps it for Tonight's top pick (which joins the history with the
     planned recipe in its swap history), or cooks it.
   - Cooking takes the recipe's grams out of the pantry, soonest best-by first, worked out the same way as the
     grocery list.
   - At the end of each day, everything past its best-by is thrown out.
5. Add the week's meals, marked cooked or skipped, to the history, so novelty and taste affect the next week.

The random draws for skipping, Tonight and extra shopping depend only on the seed, household, week and day. Every arm
therefore meets exactly the same deviations (common random numbers), and arms can be compared household by household.

**Arms.** All arms get identical inputs and seeds.

| Arm | What it is |
|---|---|
| `planner` | `WeekPlanner.plan`, the shipped engine: seeded greedy fill, 200-step local search, verification and repair |
| `greedy` | The same greedy fill and repair without the local search. It runs through `WeekPlanner.planWithoutSearch`, an `@_spi(Bench)` hook and the only change to planner source |
| `no-pantry` | The full planner scoring against an empty pantry. Pantry overlap, expiry urgency and the cost proxy all depend on the pantry, so this ranks recipes exactly as zeroing those three weights would. Shopping and cooking still use the real pantry |
| `random` | Uniformly random admitted dinners, with no repeat within a week while an unused recipe fits, and no leftovers |
| `llm` (optional) | Plans read from a JSON file with `--llm-plans`; see "LLM-only arm" |

**Metrics.** Each is computed per household, then summarised over households as mean, median and p90.

| Metric | Definition |
|---|---|
| Hard-constraint violations | `PlanVerifier` hard violations over every plan and every Tonight meal. Must be 0 |
| Perishable grams used before expiry | Over produce, protein and dairy that left the pantry during the run: grams cooked ÷ (grams cooked + grams expired). Stock still in the pantry at the end is left out |
| Starting-pantry perishables used before expiry | The same, but only for perishables in the kitchen on day one |
| Grams expired per week | Every gram thrown out at best-by, perishable or not, ÷ weeks ("waste at risk") |
| New grocery lines per week | Lines on the week's grocery list |
| Recipe repeats within a week | Share of dinners cooked from scratch whose recipe already appeared that week |
| Recipes repeated from the previous week | Share of a week's dinners cooked from scratch that were also planned the week before |
| Cuisine entropy | Shannon entropy, in bits, of the week's cuisines, leftovers excluded |
| Unfilled slots per week | Slots the arm left empty |
| Weeks within each nutrient band | Share of weeks where `PlanVerifier` puts the nutrient within its band, per default target. Bands are scaled to dinners' 35% share of the day |
| Solve time | Wall-clock time per weekly plan |

## First results

Command: `swift run -c release LarderBench --seed 42 --households 100 --weeks 4`. Run on 2026-10-17 at commit
`8efd87d` plus this harness, on an Apple-silicon Mac. Two sibling builds were running at the same time (load average
about 50) and households are simulated in parallel, so treat solve times as upper bounds. Every other figure is exact
for this seed.

| Metric (mean / median / p90) | planner | greedy | no-pantry | random |
|---|---|---|---|---|
| Hard-constraint violations (sum over all plans) | 0 | 0 | 0 | 0 |
| Perishable grams used before expiry | 50.8% / 48.7% / 67.0% | 50.2% / 49.2% / 67.1% | 48.2% / 47.9% / 66.7% | 48.7% / 48.2% / 71.9% |
| Starting-pantry perishables used before expiry | 33.5% / 31.1% / 58.5% | 33.4% / 30.1% / 58.8% | 24.2% / 20.7% / 50.4% | 28.5% / 22.4% / 58.3% |
| Grams expired per week (waste at risk) | 2112 g / 2023 g / 3245 g | 2062 g / 2024 g / 3040 g | 2404 g / 2293 g / 3902 g | 2775 g / 2934 g / 3830 g |
| New grocery lines per week | 15.96 / 15.12 / 24.55 | 15.93 / 15.12 / 24.50 | 16.75 / 16.25 / 25.78 | 19.88 / 22.62 / 26.78 |
| Recipe repeats within a week | 0.0% / 0.0% / 0.0% | 0.0% / 0.0% / 0.0% | 0.0% / 0.0% / 0.0% | 21.1% / 0.0% / 57.1% |
| Recipes repeated from the previous week | 71.1% / 71.4% / 100.0% | 69.9% / 66.7% / 100.0% | 61.4% / 58.3% / 100.0% | 65.4% / 57.1% / 100.0% |
| Cuisine entropy per week (bits) | 1.82 / 2.00 / 2.35 | 1.83 / 1.90 / 2.45 | 1.82 / 1.98 / 2.45 | 2.07 / 2.37 / 2.59 |
| Unfilled slots per week | 1.02 / 0.00 / 4.00 | 1.02 / 0.00 / 4.00 | 1.02 / 0.00 / 4.00 | 0.00 / 0.00 / 0.00 |
| Dinners swapped for Tonight per week | 0.20 / 0.00 / 0.50 | 0.20 / 0.25 / 0.50 | 0.23 / 0.25 / 0.50 | 0.39 / 0.25 / 1.00 |
| Solve time per week | 321.2 ms / 296.1 ms / 583.2 ms | 167.7 ms / 16.0 ms / 589.9 ms | 311.1 ms / 269.8 ms / 549.8 ms | 101.7 ms / 0.6 ms / 325.2 ms |
| Weeks within the energy band | 0.8% / 0.0% / 0.0% | 1.5% / 0.0% / 0.0% | 0.0% / 0.0% / 0.0% | 1.0% / 0.0% / 0.0% |
| Weeks within the protein band | 47.0% / 50.0% / 100.0% | 38.8% / 25.0% / 100.0% | 48.5% / 50.0% / 100.0% | 61.5% / 75.0% / 100.0% |
| Weeks within the fibre band | 56.2% / 87.5% / 100.0% | 57.0% / 100.0% / 100.0% | 55.5% / 75.0% / 100.0% | 56.8% / 75.0% / 100.0% |
| Weeks within the sodium band | 85.2% / 100.0% / 100.0% | 86.5% / 100.0% / 100.0% | 83.8% / 100.0% / 100.0% | 90.2% / 100.0% / 100.0% |
| Weeks within the saturated fat band | 72.2% / 100.0% / 100.0% | 72.2% / 100.0% / 100.0% | 76.0% / 100.0% / 100.0% | 65.2% / 75.0% / 100.0% |
| Weeks within the added sugar band | n/a | n/a | n/a | n/a |
| Weeks within the potassium band | 6.8% / 0.0% / 25.0% | 3.2% / 0.0% / 0.0% | 5.2% / 0.0% / 0.0% | 14.8% / 0.0% / 52.5% |

Paired by household on the same CSV (same seed, same deviations):

| Planner compared with | Waste per week | Households where planner wastes less | Grocery lines per week | Starting-pantry use |
|---|---|---|---|---|
| random | −663 g (−24%) | 92 of 100 | −3.9 | +5.0 points |
| no-pantry | −292 g (−12%) | 78 of 100 (7 ties) | −0.8 | +9.3 points |
| greedy | +50 g (+2%) | 27 of 100 (40 ties) | +0.04 | +0.1 points |

## What the first run says

- **Safety holds.** No arm produced a hard violation in 400 household-weeks, Tonight swaps included. That is expected,
  because every arm draws only admitted recipes. The `llm` arm is where this gate starts to matter.
- **Pantry awareness drives the waste and shopping gains.** The planner's lead over `no-pantry` (−12% waste, +9 points
  of starting-pantry use) isolates the scorer's pantry and expiry terms. The lead over `random` is larger because
  random plans also shop for more distinct ingredients.
- **The local search adds nothing on waste.** `greedy` matches the full planner on every pantry metric and is about
  20 times faster at the median. The search moves plans toward nutrient bands instead: protein 47.0% of weeks within
  band against 38.8% for greedy, potassium 6.8% against 3.2%. Whether the search earns its cost is now a measurable
  question rather than an assumption.
- **Repetition across weeks is the main weakness.** The planner repeats 71% of the previous week's dinners, more than
  random (65%) and more than `no-pantry` (61%). Two feedback loops push the same way. Pack remainders from last week's
  recipes raise those recipes' pantry overlap, and `TasteAffinity` rewards recipes just cooked. Together they outweigh
  the novelty term, which is worth at most 1. With only 24 dinner recipes, restricted households have no way out:
  tree-nut, coeliac and single-allergen households repeat 100% of the previous week.
- **Restricted households get empty slots, not unsafe meals.** The planner leaves about 1 slot a week empty on
  average. By persona: single-allergen 3.4, coeliac 2.4, tree-nut 2.1, vegan 1.0, and 0 for the other personas. The
  admission rule plans nothing excluded or uncertain, and with seed data where many foods have unknown allergen status,
  fewer than seven dinners qualify. Random fills these slots by repeating recipes, which accounts for its 21%
  within-week repetition.
- **Nutrient bands are hard to hit with dinners alone.** Energy is almost never within ±10% of a dinner's 35% share for
  any arm. Unfilled slots also lower the planner's weekly totals, which partly explains why random scores higher on
  protein and potassium. A fair nutrient comparison needs fully planned weeks or a per-meal measure. Added sugar is n/a
  because the seed foods have no added-sugar data.

## LLM-only arm

`--llm-plans plans.json` adds an `llm` arm, scored with the same simulation and metrics. The format is documented on
`FileArm` in `Sources/LarderBench/Arms.swift`:

```json
{"plans": [{"household": 0, "week": 0, "meals": [
  {"day": 0, "slot": "dinner", "recipe": "weeknight-chana-masala", "servings": 2},
  {"day": 1, "slot": "dinner", "recipe": "weeknight-chana-masala", "servings": 2, "leftoverOfDay": 0}
]}]}
```

To produce one, run `--export-households households.json` with the same `--seed` and `--households`. Prompt the proxy
once per household and week with that household's profile, constraints, starting pantry and the seed recipe slugs, and
collect the answers in the format above. Recipes are seed slugs. An unknown slug is kept and the verifier reports it
as a hard violation ("No recipe data"), so an invented recipe counts against the arm instead of being silently dropped.
A household and week with no entry counts every slot as unfilled. The plans are open loop: they are fixed before the
simulation runs and cannot react to the pantry it produces, which flatters the closed-loop arms on weeks after the
first. The verifier checks safety rules but not the time cap or equipment, so those need checking separately when
scoring model output.

## Limitations

- **Simulated, not observed.** The behaviour probabilities, pack sizes and shelf lives are assumptions, not
  measurements. Absolute waste is far above real household figures, because dinners are the only way food leaves the
  kitchen: no breakfasts, lunches or snacks eat the remainders. Read the comparisons between arms, not the absolute
  grams.
- **One shop a week, bought on day one.** A dinner late in the week can find its ingredients already past best-by,
  whatever the arm.
- **Small catalogue.** 24 dinner recipes cap variety and drive both the unfilled slots and the repetition. The results
  are about this catalogue as much as about the planner.
- **Proxy outcomes.** Taste is learned from simulated cooks and skips, not from people. Nothing here measures whether
  people like the plans, trust the reasons or keep using the app. That still needs the user study.
- **Solve time** is wall-clock under parallel load. For timing claims, run `swift run -c release` on an idle machine;
  `Tests/LarderCoreTests` holds the 0.5 s single-plan budget.
