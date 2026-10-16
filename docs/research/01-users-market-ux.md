# Larder research 01: users, market and UX behaviour

Researched 2026-10-16. Evidence caveats: Reddit was not reachable, so complaint evidence comes from App Store listings, unitQ and review roundups (several written by competing vendors, flagged where relevant). Segment behaviour is a synthesis, not measured data.

## 0. Market event: Mealime closes on 2026-10-21

- Mealime's site says it "will be discontinued as of October 21, 2026" (https://www.mealime.com/closing). Owner Albertsons folds it into "Meals Hub", which needs an Albertsons login. All personal data is deleted at shutdown with no export (https://www.eatthismuch.com/switch-from-mealime).
- Mealime's praised strength: it "took the decision away"; its aisle-sorted grocery list was the best-loved feature (https://www.pann-app.com/blog/is-mealime-shutting-down).
- PlateJoy also appears to have closed in 2025 (Trustpilot; https://mealthinker.com/blog/best-ai-meal-planning-apps-2026). Probable, not confirmed.
- Lesson: two heavily used planners died in two years. Users distrust planners that hold data hostage.

Recommendation: ship recipe/plan import (share sheet, URL, photo) and one-tap full data export before launch. Market "your data leaves with you".

## 1. Segments

| Segment | Core job | Moment and frequency | Churn trigger |
|---|---|---|---|
| Busy parents | End the nightly "what's for dinner" negotiation | 5pm rescue plus a 10-minute weekend plan | Setup burden, one plan for people with different needs, rigid grids |
| Fitness-focused | Hit protein/macro targets without logging every meal | Daily, morning | Repetitive meals, paywalled tracking, tedious entry |
| Budget cooks | Spend less, waste less | Weekly, at grocery time | Recipes needing one-off ingredients, ignoring what is at home |
| Medical diet (diabetes, IBS, kidney) | Safe meals, trustworthy "can I eat this" | Constant, high stakes | Wrong or unverifiable answers |
| ADHD / executive function | Remove decisions and working-memory load | Low-friction rescue, visual plan | Anything requiring a maintained system; a missed day causing abandonment |
| Older adults | Simple, legible, repeatable meals | Routine | Small type, account walls, subscription confusion |
| Students | Cheap, fast, minimal equipment | Ad hoc | Price and ingredient sprawl |

Supporting data:
- 68% say deciding what to eat is their biggest mealtime challenge (Wakefield/Factor, https://www.gourmetnews.com/factor/); about 16 minutes a day (Talker Research, https://www.aol.com/articles/whats-cooking-dinner-decisions-complicated-125823000.html).
- 86% of adults are at least occasional "meal repeaters" (HelloFresh/Wakefield); 43% repeat the same meals several times a week, only 13% follow recipes consistently (https://www.questionpro.com/research/americas-real-eating-habits/).
- Planners have better guideline adherence (OR about 1.13) and variety (OR about 1.25) in 40,554 French adults, cross-sectional (https://pubmed.ncbi.nlm.nih.gov/28153017/).
- ADHD evidence is thin; consistent advice: move the decision off the hungry moment, keep the plan external and visual, use fixed defaults and staple rotations (https://www.getinflow.io/post/meal-planning-adhd).

Recommendation: make the 5pm "rescue" the primary entry point; the Sunday plan is secondary. Design for households that repeat meals. Beachheads: busy parents / overload, and budget / waste. Medical-diet users are a later, carefully scoped tier.

## 2. Competitor teardown (US prices from cited sources; conflicts flagged)

| App | Does well | Main complaints | Pricing |
|---|---|---|---|
| Mealime (closing) | Fast curated recipes, aisle-sorted list, scaling | Small free catalogue, thin nutrition customisation, no pantry | Free; Pro $2.99-5.99/mo |
| Paprika 3 | Best web clipper, lists, calendar, pantry; one-time purchase | Fully manual, abandoned after weeks; sold per platform | About $4.99-5.99 per platform |
| Samsung Food | 240k+ recipes, strong import, 4.8 stars | Recipes link out, ads, forced account, list has no quantities, Health Score criticised for diet-culture language | Free; Food+ $6.99/mo or $59.99/yr |
| Eat This Much | Macro-targeted plans, grocery list, spending cap | Repetition by week 3, tedious exclusions, weak for households | Daily plans free; weekly and lists paid; $8.99-$84.99 tiers |
| PlateJoy | Onboarding-heavy personalisation | Billing complaints; site apparently closed | Was about $12/mo or $99/yr |
| Noom | Psychology framing | $56M auto-renew class settlement (https://journals.law.unc.edu/ncjolt/?p=8616); colour-coded foods criticised | About $42-70/mo, dynamic |
| MyFitnessPal | 20M foods, integrations; acquired Cal AI Dec 2025 | Barcode scanner paywalled, crowd-sourced inaccuracy | Premium $19.99/mo or $79.99/yr |
| Yuka | Instant scan to score, 85M users | Opaque scoring (60/30/10 weighting) | Pay-what-you-want $10/15/20 per year |
| Cronometer | Micronutrient depth | Free tier ads, 7-day report window | Gold $10.99/mo or $59.99/yr |
| Pestle | Clean organiser, social-video import | Little planning | About $24.99-29.99/yr, lifetime option |
| Crouton | Polished Apple-native, 2024 ADA winner | Narrow scope | Plus $24.99 one-time; Discover $14.99/yr |
| Mela | Minimal, iCloud-synced | Apple-only | Mela+ macOS $14.99 one-time |
| Kitchen Stories | Editorial quality | Not a planner | About $34.99-79.99/yr |

AI-first entrants 2025-26: Ollie (pantry photo scan, Instacart ordering, about $9.99/mo; complaints: variety, scan is a stale snapshot), AI Menu4You (launched 2026-10-12), retailer planners using purchase history (Tesco, Albertsons), SuperCook fridge-photo scan.

Pattern: automation apps get repetition complaints; manual apps get abandoned; trackers get friction and paywall complaints; scanners get trust complaints. Nobody owns "low effort, adapts to what you actually did".

Recommendation: differentiate on adaptive planning plus pantry memory plus transparency. Don't compete on recipe count or macro depth. Avoid Noom-style trial opacity.

## 3. Retention and behaviour

- Dutch research (40 focus groups, 1,420 survey): time burden was the top quit reason (36.8%); patronising or rigid feedback and repetitive advice drove disengagement; gamification and social ranked lowest; value faded once habits formed (https://pmc.ncbi.nlm.nih.gov/articles/PMC10337335).
- Food-diary app with 189,770 users: only 2.58% became active (https://jmir.org/2014/4/e109).
- No controlled study isolates plan rigidity as a dropout cause. Adjacent dietary-restraint literature: flexible control associates with lower BMI and less disinhibited eating (https://hpr.termedia.pl/Interactive-effects-between-flexible-and-rigid-control-of-eating-behavior-on-body,75777,0,2.html). Supports "flexible" as the safer bet.

Habit loops that fit the evidence: pantry-first "what can I make now"; cook once, eat twice (leftovers); grocery list as the stickiest artefact (with quantities and aisles); plan as a suggestion that can be swapped, skipped or slid without a failure state.

Recommendation: build around "plan loosely, shop once, cook with swaps, roll leftovers forward, update pantry from the list". Success metric: week-4 grocery lists generated, not plans created. No streaks or gamification.

## 4. Monetisation

RevenueCat State of Subscription Apps 2026, Health and Fitness (https://www.revenuecat.com/state-of-subscription-apps): median download-to-paid at day 35 is 2.9% (top quartile above 6.2%); trial-to-paid 37.7% median; median prices $9.99/mo and $39.94/yr; first renewal 57% monthly, 25% annual.

Category annual prices: Plan to Eat $49, Eat This Much about $48-60, Samsung Food+ $59.99, Cronometer $59.99, Ollie about $80, MyFitnessPal $79.99. Trials are typically 7 days; Eat This Much and Plan to Eat give 14.

Users accept paying for: weekly automation, grocery list generation, multi-person profiles, advanced nutrition reports, ad-free. Users resent: barcode scanning paywalled, ads over recipes, hidden auto-renew trials, per-platform repurchase, being locked out of their own data.

Recommended split:
- Free forever: manual week planner, recipes and import, grocery list with quantities and aisle sort, pantry list, "what can I cook now", allergen and avoid filters (safety is never paywalled), data export, no ads.
- Paid (Larder Plus): AI full-week generation and adaptive replanning, household profiles, leftover and batch-cook scheduling, nutrient targets and reports, photo or receipt pantry updates, price optimisation and delivery hand-off.
- Price: $7.99/mo and $49.99/yr with a 7-day trial on annual. Undercuts Samsung and Cronometer, equals Plan to Eat, sits above the category median because inference has real cost.

## 5. Risks

- Eating-disorder sensitivity: a 38-article review links diet/fitness apps with disordered-eating symptoms (https://pubmed.ncbi.nlm.nih.gov/39671845/); qualitative work flags red/green over-target colouring, low calorie floors and streaks. Rules: calories off by default; no "good/bad", "clean", "cheat", "earn", "burn off", "guilt"; no red over-limit states; reject goals below a safe floor; a "no numbers" mode; never ask target weight.
- FDA revised General Wellness guidance (2026-01-06) keeps enforcement discretion for low-risk wellness claims (https://www.cov.com/en/news-and-insights/insights/2026/01/fda-issues-revised-guidance-on-general-wellness-products). Apple guideline 1.4.1: health recommendations need cited sources and a consult-a-doctor reminder.
- Boundary: "supports" and "helps you plan around" a condition is wellness. "Treats", "manages your diabetes", dosing or insulin advice is not.

Recommendation: wellness positioning only; exclusion filters and sodium/carb/FODMAP tags sourced to named references; persistent "not medical advice" note at condition setup; dietitian and ED-sensitivity copy review before launch.

## Five non-obvious product ideas

1. "Dinner rescue" lock-screen widget at the learned decision time with 3 options using what you have.
2. Plan-by-exception: next week pre-filled from what you really cooked; you edit the deltas.
3. Receipt-reconciled pantry: snap the receipt to add groceries; cooking subtracts; the pantry never goes stale like a photo scan.
4. Orphan import from closed apps plus a guaranteed export.
5. Per-person cards on one shared plate: one base dish with a visible swap per household member.
