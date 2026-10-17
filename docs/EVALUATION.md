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
swift run LarderBench --households 20 --weeks 2                                   # quick run, debug build
swift run -c release LarderBench --seed 42 --seeds 5 --households 100 --weeks 4   # the run reported below
Scripts/bench-gate.sh                                                             # regression gate, see below
swift run LarderBench --help
```

Flags: `--seed` (default 42), `--seeds` (runs seeds `seed`, `seed + 1`, … each with its own households; default 1),
`--households` (default 100), `--weeks` (default 4), `--out` (CSV directory, default `./bench-results`, which git
ignores), `--data` (seed JSON directory), `--llm-plans` (extra arm, see below), `--export-households` (writes the
generated households as JSON), and `--check-baseline` / `--write-baseline` (the regression gate). `--llm-plans` and
`--export-households` take a single seed, because both files are keyed by household index. Each run writes one CSV
with a row per seed, household and arm, and prints two Markdown tables to stdout: each arm's summary and the planner
paired against every other arm. Everything except solve time can be reproduced exactly: the same flags always give the
same CSV.

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

**Metrics.** Each is computed per household. "Cooked from scratch" means a planned dinner whose status is cooked and
that is not a leftover: skipped dinners, dinners swapped for Tonight and leftovers are all left out. Tonight's
replacement dinners are not part of the plan, so they are not counted either.

| Metric | Definition |
|---|---|
| Hard-constraint violations | `PlanVerifier` hard violations over every plan and every Tonight meal. Must be 0 |
| Perishable grams used before expiry | Over produce, protein and dairy that left the pantry during the run: grams cooked ÷ (grams cooked + grams expired). Stock still in the pantry at the end is left out |
| Starting-pantry perishables used before expiry | The same, but only for perishables in the kitchen on day one |
| Grams expired per week | Every gram thrown out at best-by, perishable or not, ÷ weeks ("waste at risk") |
| New grocery lines per week | Lines on the week's grocery list |
| Recipe repeats within a week | Share of dinners cooked from scratch whose recipe was already cooked from scratch that week |
| Recipes repeated from the previous week | Share of a week's dinners cooked from scratch whose recipe was also cooked from scratch the week before |
| Cuisine entropy | Shannon entropy, in bits, of the cuisines of the week's dinners cooked from scratch |
| Unfilled slots per week | Slots the arm left empty |
| Weeks within each nutrient band, per filled dinner | Share of weeks where `PlanVerifier` puts the plan's average filled dinner within the nutrient's band, per default target. Bands are scaled to dinners' 35% share of the day. Empty slots are left out of the average, and a week with no filled dinner has no value |
| Solve time | Wall-clock time per weekly plan |

Two definitions changed on 2026-10-17, so earlier CSVs are not comparable on these columns. The repeat and cuisine
metrics used to drop only leftovers, so a skipped dinner counted as cooked from scratch; they now filter on the cooked
status, and the labels stayed because they now say what is measured. The nutrient bands used to be checked on the
week's total over all seven days, so every empty slot pulled the totals down and arms that leave slots empty looked
low on protein and potassium; they are now checked per filled dinner.

**Summaries and intervals.** Each arm's table gives the mean, median and p90 over households, every seed pooled. Arms
are compared in pairs: for every seed and household, the planner's value minus the other arm's, summarised as the mean
difference and a 95% percentile bootstrap interval (2,000 resamples, fixed resampling seed, so the interval is
reproducible too). Each seed draws its own households, and nothing in the simulation is shared between households of
one seed, so every seed and household is an independent unit. The bootstrap resamples households with replacement
within each seed, keeping each seed's count. A household without a value under either arm is left out of that pair,
and one household gives a zero-width interval. An interval that excludes 0 is a difference this many households can
resolve; one that spans 0 is not.

## Results

Command: `swift run -c release LarderBench --seed 42 --seeds 5 --households 100 --weeks 4`, 500 households in all.
Run on 2026-10-17 at commit `d174c09` plus the multi-seed and gate changes, on an Apple-silicon Mac with sibling builds
running (load average 8 to 14) and households simulated in parallel, so treat solve times as upper bounds. Every other
figure is exact for these seeds. The first run, on seed 42 alone and the old metric definitions, is in this file's
history.

| Metric (mean / median / p90) | planner | greedy | no-pantry | random |
|---|---|---|---|---|
| Hard-constraint violations (sum over all plans) | 0 | 0 | 0 | 0 |
| Perishable grams used before expiry | 51.7% / 51.8% / 69.1% | 51.6% / 51.6% / 69.2% | 49.3% / 48.6% / 67.0% | 50.3% / 48.7% / 73.0% |
| Starting-pantry perishables used before expiry | 34.0% / 32.6% / 59.6% | 34.1% / 32.3% / 60.0% | 26.8% / 23.0% / 56.3% | 30.7% / 26.1% / 62.8% |
| Grams expired per week (waste at risk) | 2083 g / 2012 g / 3165 g | 2022 g / 1979 g / 2976 g | 2351 g / 2240 g / 3699 g | 2740 g / 2813 g / 3969 g |
| New grocery lines per week | 15.93 / 15.25 / 24.00 | 15.83 / 15.25 / 24.00 | 16.66 / 16.00 / 25.25 | 19.66 / 21.62 / 26.50 |
| Recipe repeats within a week | 0.0% / 0.0% / 0.0% | 0.0% / 0.0% / 0.0% | 0.0% / 0.0% / 0.0% | 18.3% / 0.0% / 51.8% |
| Recipes repeated from the previous week | 60.3% / 61.1% / 91.7% | 59.1% / 61.1% / 91.7% | 53.0% / 55.6% / 91.7% | 58.7% / 60.0% / 100.0% |
| Cuisine entropy per week (bits) | 1.50 / 1.56 / 2.05 | 1.51 / 1.54 / 2.12 | 1.51 / 1.58 / 2.07 | 1.83 / 1.96 / 2.39 |
| Unfilled slots per week | 1.10 / 0.00 / 4.00 | 1.10 / 0.00 / 4.00 | 1.10 / 0.00 / 4.00 | 0.01 / 0.00 / 0.00 |
| Dinners swapped for Tonight per week | 0.23 / 0.25 / 0.75 | 0.24 / 0.25 / 0.75 | 0.26 / 0.25 / 0.75 | 0.46 / 0.25 / 1.00 |
| Solve time per week | 94.7 ms / 83.4 ms / 173.4 ms | 55.1 ms / 3.6 ms / 172.9 ms | 94.0 ms / 81.4 ms / 173.8 ms | 34.6 ms / 0.3 ms / 117.5 ms |
| Weeks within the energy band, per filled dinner | 0.8% / 0.0% / 0.0% | 1.1% / 0.0% / 0.0% | 0.6% / 0.0% / 0.0% | 0.9% / 0.0% / 0.0% |
| Weeks within the protein band, per filled dinner | 64.3% / 100.0% / 100.0% | 57.6% / 75.0% / 100.0% | 64.9% / 100.0% / 100.0% | 62.0% / 75.0% / 100.0% |
| Weeks within the fibre band, per filled dinner | 63.8% / 100.0% / 100.0% | 64.9% / 100.0% / 100.0% | 60.6% / 100.0% / 100.0% | 62.2% / 75.0% / 100.0% |
| Weeks within the sodium band, per filled dinner | 88.5% / 100.0% / 100.0% | 89.2% / 100.0% / 100.0% | 87.2% / 100.0% / 100.0% | 91.9% / 100.0% / 100.0% |
| Weeks within the saturated fat band, per filled dinner | 76.3% / 100.0% / 100.0% | 76.0% / 100.0% / 100.0% | 78.3% / 100.0% / 100.0% | 64.4% / 75.0% / 100.0% |
| Weeks within the added sugar band, per filled dinner | n/a | n/a | n/a | n/a |
| Weeks within the potassium band, per filled dinner | 18.8% / 0.0% / 100.0% | 17.1% / 0.0% / 100.0% | 17.3% / 0.0% / 100.0% | 16.7% / 0.0% / 75.0% |

Planner minus each other arm, paired by household (mean difference and bootstrap 95% interval over the 500
households):

| planner minus (mean [95% CI]) | greedy | no-pantry | random |
|---|---|---|---|
| Perishable grams used before expiry | +0.2 pt [-0.2 pt, +0.5 pt] | +2.4 pt [+1.9 pt, +2.9 pt] | +1.4 pt [+0.5 pt, +2.4 pt] |
| Starting-pantry perishables used before expiry | -0.1 pt [-0.6 pt, +0.3 pt] | +7.2 pt [+6.2 pt, +8.3 pt] | +3.3 pt [+1.9 pt, +4.7 pt] |
| Grams expired per week (waste at risk) | +61 g [+39 g, +84 g] | -268 g [-302 g, -237 g] | -657 g [-704 g, -607 g] |
| New grocery lines per week | +0.10 [+0.02, +0.17] | -0.74 [-0.86, -0.63] | -3.73 [-4.04, -3.40] |
| Recipe repeats within a week | +0.0 pt [+0.0 pt, +0.0 pt] | +0.0 pt [+0.0 pt, +0.0 pt] | -18.3 pt [-20.5 pt, -16.0 pt] |
| Recipes repeated from the previous week | +1.2 pt [+0.0 pt, +2.5 pt] | +7.3 pt [+5.7 pt, +8.9 pt] | +1.6 pt [-0.5 pt, +3.6 pt] |
| Cuisine entropy per week (bits) | -0.01 [-0.02, +0.01] | -0.00 [-0.02, +0.01] | -0.33 [-0.36, -0.30] |
| Unfilled slots per week | +0.00 [+0.00, +0.00] | +0.00 [+0.00, +0.00] | +1.08 [+0.93, +1.23] |
| Dinners swapped for Tonight per week | -0.01 [-0.02, +0.01] | -0.03 [-0.05, -0.01] | -0.23 [-0.26, -0.20] |
| Weeks within the energy band, per filled dinner | -0.3 pt [-0.9 pt, +0.3 pt] | +0.2 pt [-0.2 pt, +0.6 pt] | -0.1 pt [-0.5 pt, +0.3 pt] |
| Weeks within the protein band, per filled dinner | +6.7 pt [+4.7 pt, +8.8 pt] | -0.6 pt [-2.1 pt, +0.9 pt] | +2.3 pt [-0.5 pt, +5.2 pt] |
| Weeks within the fibre band, per filled dinner | -1.1 pt [-2.6 pt, +0.4 pt] | +3.3 pt [+1.8 pt, +4.8 pt] | +1.6 pt [-1.4 pt, +4.5 pt] |
| Weeks within the sodium band, per filled dinner | -0.7 pt [-2.3 pt, +0.9 pt] | +1.3 pt [-0.5 pt, +3.0 pt] | -3.5 pt [-5.9 pt, -1.3 pt] |
| Weeks within the saturated fat band, per filled dinner | +0.3 pt [-1.8 pt, +2.3 pt] | -2.1 pt [-4.0 pt, -0.2 pt] | +11.9 pt [+8.8 pt, +14.8 pt] |
| Weeks within the added sugar band, per filled dinner | n/a | n/a | n/a |
| Weeks within the potassium band, per filled dinner | +1.8 pt [+0.9 pt, +2.7 pt] | +1.6 pt [+0.4 pt, +2.8 pt] | +2.1 pt [+0.1 pt, +4.2 pt] |

On waste per week the planner is lower than `greedy` in 103 households, tied in 209 and higher in 188; lower than
`no-pantry` in 363 (35 ties) and lower than `random` in 450 (1 tie).

## What the results say

- **Safety holds.** No arm produced a hard violation in 2,000 household-weeks, Tonight swaps included. That is
  expected, because every arm draws only admitted recipes. The `llm` arm is where this gate starts to matter.
- **Pantry awareness drives the waste and shopping gains.** Against `no-pantry` the planner wastes 268 g a week less
  (interval −302 to −237 g) and uses 7.2 more points of the starting pantry (+6.2 to +8.3), which isolates the scorer's
  pantry and expiry terms. The lead over `random` is larger on waste (−657 g) because random plans also shop for more
  distinct ingredients (−3.7 grocery lines a week).
- **The local search costs a little on waste.** Against `greedy` the planner wastes 61 g a week more (+39 to +84 g)
  and buys 0.1 more grocery lines, with no difference in pantry use; `greedy` is also about 20 times faster at the
  median. The single-seed run showed the same +50 g but could not say whether it was noise; 500 households can. What
  the search buys is nutrient fit: 6.7 more points of weeks within the protein band (+4.7 to +8.8) and 1.8 more within
  potassium. Whether that is worth the waste and the solve time is now a measured trade-off.
- **Repetition across weeks is the main weakness.** 60% of the planner's dinners cooked from scratch are recipes also
  cooked the week before, 7.3 points more than `no-pantry` (+5.7 to +8.9) and about the same as `random` (+1.6, interval
  spanning 0). Two feedback loops push the same way. Pack remainders from last week's recipes raise those recipes'
  pantry overlap, and `TasteAffinity` rewards recipes just cooked. Together they outweigh the novelty term, which is
  worth at most 1. With only 24 dinner recipes, restricted households have little way out: tree-nut, coeliac and
  single-allergen households repeat about 80% of the previous week, against 37 to 51% for kidney-disease,
  hypertension, unrestricted and time-poor households.
- **Restricted households get empty slots, not unsafe meals.** The planner leaves about 1.1 slots a week empty on
  average. By persona: single-allergen 3.1, coeliac 2.6, tree-nut 2.4, vegan 0.3, and 0 for the other personas. The
  admission rule plans nothing excluded or uncertain, and with seed data where many foods have unknown allergen status,
  fewer than seven dinners qualify. Random fills these slots by repeating recipes, which accounts for its 18%
  within-week repetition.
- **Nutrient bands, measured per filled dinner.** With empty slots out of the average, the planner is no longer
  behind `random` on protein (+2.3 points, interval spanning 0) or potassium (+2.1), and is well ahead on saturated
  fat (+11.9), while random keeps a small lead on sodium (−3.5). Energy is still almost never within ±10% of a
  dinner's 35% share for any arm. Added sugar is n/a because the seed foods have no added-sugar data.

## Regression gate

`Scripts/bench-gate.sh` runs a release build with `--seed 42 --seeds 3 --households 40 --weeks 4` (120 households,
about 25 s on an Apple-silicon Mac) and checks the planner against the committed `Scripts/bench-baseline.json`. It
prints the usual tables and a gate table, and exits 1 when any of these holds:

- The planner has a hard-constraint violation, in a plan or a Tonight swap.
- Grams expired per week has a mean above the baseline's 95% interval.
- Starting-pantry use has a mean below the baseline's 95% interval.
- Recipes repeated from the previous week has a mean above the baseline's 95% interval.
- One of those three has a value in the baseline and none in the run, or the reverse.

A baseline written with other flags is refused before the run starts. The simulation is deterministic, so an
unchanged planner reproduces the baseline exactly, and the interval is the tolerance. On the committed baseline that
is about ±140 g of waste per week (7%), ±3.5 points of starting-pantry use and ±4.5 points of repetition across weeks.
A smaller regression passes: the gate catches clear regressions before a release, it does not prove small gains. For
scale, on the gate's households the `no-pantry` arm would fail it on waste (2,250 g against an upper bound of 2,159 g)
and on starting-pantry use (27.2% against a lower bound of 30.4%), while `greedy` would pass. For smaller effects,
compare the multi-seed report before and after the change.

After an intended change in the planner's figures, run `Scripts/bench-gate.sh --update` to rewrite the baseline, and
commit it with the change, saying why it moved. The repository has no CI, so run the gate by hand before a release
and on any change to `LarderCore/Planning`.

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
