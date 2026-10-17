# Larder blueprint

Date: 2026-10-16. Decisions made from the five research reports in `docs/research/`. Each decision names the alternative it rejected.

## 1. Product thesis

Larder is the low-effort planner that adapts to what you actually did. It plans loosely, shops once, cooks with swaps, rolls leftovers forward and keeps the pantry current from the grocery list. The 5pm "Tonight" rescue is the primary entry point; the Sunday plan is secondary. No streaks, no scores, no red numbers, calories off by default.

Beachhead segments: busy households and people with decision fatigue; budget and waste-conscious cooks. Medical diets are supported through hard constraints and clear disclaimers, never through advice.

## 2. Feature set and free/paid split

Free forever (safety and the Mealime-orphan wedge):
- Pantry with quantities (counted in pieces when a food has a countable portion), best-by dates, a "Use soon" list, search, an item editor, natural-language quick add with one-tap staples, barcode scan.
- Recipes: seed corpus, private on-device URL import (schema.org JSON-LD), full-text search, scaled ingredients, cooking mode (one step per screen, named timers, keep awake).
- Plan (week plan) with manual planning, add any recipe to any of the next seven days, swap, skip, slide, leftovers that roll forward.
- Tonight: three pantry-first options (deterministic, offline).
- Grocery list with quantities and aisles; checked items land on the shelves with a default best-by date by food group, and the basket and hand-written items survive a relaunch and plan changes. Marking a meal cooked (or Finish in cooking mode) takes its ingredients off the shelves, with Undo; every removal is logged as cooked, eaten, let go or expired for a later waste measure.
- Allergen and dietary constraint engine (five axes). Never paywalled.
- Full JSON export. No ads.
- One generated week to try Plus ("Planning one week is free").

Larder Plus ($7.99/month, $49.99/year, 7-day trial on annual):
- Plan my week: automatic generation and adaptive replanning, with reasons.
- Household profiles with per-person swaps on one shared plate.
- Leftover and batch-cook scheduling.
- Shelf balance: weekly food-group bands against a comfortable range, nutrient targets, optional numbers.
- Photo and receipt pantry updates.
- Assistant: conversational adjustments ("vegetarian Tuesday, under 30 minutes, use the rice").

Rejected: a hard paywall (cuts the top of funnel the Mealime shutdown just opened); paywalling scanning or allergen filters (the most resented pattern in the category); Noom-style dynamic pricing.

## 3. Platform decisions

| Decision | Choice | Rejected alternative |
|---|---|---|
| Toolchain | Xcode 27.1, Swift 6.4, Swift 6 language mode | Waiting for Xcode 27.2 |
| Floor | iOS 26.0, iOS 27 features behind `#available` | iOS 27 floor: four weeks old, small base |
| UI | SwiftUI with Liquid Glass on navigation and controls only; opaque "paper" content | Custom glass everywhere (contrast failures, cliché) |
| State | `@Observable` models; MainActor default isolation on UI targets only | `ObservableObject` |
| Store | GRDB 7 SQLite with FTS5 and explicit migrations, behind repository protocols | SwiftData: `@Model` is macro-only, CloudKit rules forbid unique constraints, weaker search |
| Sync | Deferred; repository protocols leave room for SQLiteData CloudKit sync | SwiftData + CloudKit at launch |
| Tests | Swift Testing everywhere; `swift test` for packages, `xcodebuild test` for the app | XCTest |
| Project | XcodeGen `project.yml`, generated `.xcodeproj` git-ignored, one local SwiftPM package with many targets | Tuist, hand-maintained pbxproj |
| Images | Imported recipe photos downloaded once, downsampled with ImageIO and read from local files | Nuke 13 (nothing loads remotely at display time); `AsyncImage` (caching only on iOS 27) |
| Monetisation | StoreKit 2 with `SubscriptionStoreView`, trial, annual, monthly, win-back; proxy verifies JWS | RevenueCat (reconsider for paywall experiments) |
| System | App Intents (entities for recipes, plans, "what's for dinner"), one interactive widget; a HealthKit nutrition write for cooked meals is deferred, and the entitlement ships only with it (2026-10-17) | Live Activities, Watch, Mac target (v2) |
| On-device AI | Foundation Models behind `AssistantBackend` for pantry parsing, tagging, OCR and barcode flows; deterministic fallback | Depending on Apple Intelligence availability for core planning |
| Cloud AI | Claude through a thin proxy that holds the key, checks App Attest and entitlement, meters per user, caches prompts | Shipping the key; direct App Attest path (iOS 27 only, no metering) |
| Proxy runtime | Cloudflare Worker, TypeScript, `@anthropic-ai/sdk`, Zod structured outputs | Vercel or Supabase edge functions (either works; Workers has KV for quotas and the smallest cold start) |

## 4. Recommendation engine

Hybrid: a deterministic Swift pipeline produces and verifies the plan; the model explains, parses and ranks.

```
Profile + Constraints + Targets
  -> ConstraintCompiler (hard filters, soft weights, DGA 2025 and WHO targets tagged by source)
  -> HardFilter (allergens, diet, medical, equipment, time)      no model involved
  -> RecipeScorer (pantry overlap, expiry urgency, time, cost, taste, novelty decay)
  -> WeekPlanner (local search: nutrient bands per week, variety quotas, leftover slots)
  -> PlanVerifier (independent allergen recheck, nutrient totals, shelf balance)
  -> Assistant (explain from reason codes, rank solver swaps, parse input, chat to constraint edits)
  -> Post-model validation (schema, numbers from template slots, edits re-verified)
```

Allergen safety is two independent code paths with a contains / may contain / unknown / verified-free state per ingredient; unknown is never shown as safe. The model never holds the allergen list as its guard.

## 5. Model choice for personalised recommendations

Answer to "is Haiku 5.5 enough": yes for most of it, because the engine does the hard part deterministically.

| Route | Model | Effort | Why |
|---|---|---|---|
| Explain a plan or a swap from reason codes | `claude-haiku-5-5` | low | Verbalising structured facts; output dominates cost ($0.10 / $0.50 per MTok) |
| Parse natural-language pantry entry | On-device Foundation Models, fallback `claude-haiku-5-5` | low | Short extraction with a fixed schema |
| Tag or normalise ingredients | `claude-haiku-5-5` | low | Classification |
| Parse a recipe from a photo or messy page | `claude-haiku-5-5` | medium | Vision plus noisy input; Haiku-only routing keeps cost flat |
| Conversational adjustments to constraints | `claude-haiku-5-5` | medium | Multi-constraint reasoning and tone around sensitive conditions |
| Offline recipe generation (batch, no user data) | `claude-haiku-5-5` via Batch | medium | 50% off; every recipe passes the deterministic validator |

Expected cost at 30 requests per user-month (3k in, 800 out): about $0.02 with every route on Haiku 5.5, well inside the $4.17/month annual price. Opus is unnecessary. Routes are configurable in the proxy so an eval of about 200 labelled cases per task can move a route up or down.

API rules that apply (from the claude-api skill): adaptive thinking is on by default on both models, control depth with `output_config.effort`; no `temperature`; no assistant prefill; structured outputs via `output_config.format` with `client.messages.parse`; no `fallbacks` on Haiku 5.5, so handle `stop_reason == "refusal"` client-side; static system prompt first with a cache breakpoint, user profile summary after it, volatile request last; prompts carry derived flags and numbers, never names, emails, locations, exact weight or birth dates.

## 6. Architecture and folder layout

```
Larder/
  project.yml                      XcodeGen
  Package.swift                    local package "LarderKit" with these targets:
  Sources/
    LarderCore/                    pure Swift, nonisolated, Sendable; no UI, no I/O
      Domain/                      Food, Recipe, Ingredient, PantryItem, MealPlan, PlannedMeal, UserProfile, DietaryConstraint, NutrientTarget
      Units/                       UnitConverter, Quantity
      Nutrition/                   NutritionCalculator, Targets (DGA2025, WHO), ShelfBalance
      Allergens/                   Allergen taxonomy, derivatives, AllergenEngine
      Planning/                    ConstraintCompiler, RecipeScorer, WeekPlanner, PlanVerifier, ReasonCode
      Grocery/                     GroceryListBuilder, Aisle
      Ports/                       repository and AssistantBackend protocols
    LarderPersistence/             GRDB schema, migrations, repositories, FTS5, seed loader
    LarderAssistant/               proxy client, prompt builder, PII scrubber, response schemas
    LarderOnDeviceAI/              Foundation Models adapter (@Generable), Vision scanners
    LarderDesign/                  tokens, typography, components, Copy catalogue, motion, a11y helpers
    FeatureShelves/                pantry
    FeatureLedger/                 week plan and Tonight
    FeatureRecipes/                library, import, detail, cooking mode
    FeatureGrocery/                list
    FeatureAccount/                onboarding, settings, paywall, entitlements
  Tests/                           one test target per source target
  App/
    Larder/                        app entry, tabs, dependency container, App Intents
    LarderWidgets/                 today widget
    Resources/                     Assets.xcassets (colour sets), seed data, Larder.storekit (fonts live in Sources/LarderDesign/Resources/Fonts)
  Server/larder-proxy/             Cloudflare Worker (TypeScript)
  Tools/                           import-fdc.py + fdc-mapping.json, validate-seed.py, name-fraunces-statics.py
  Scripts/                         test-packages.sh, generate.sh, lint.sh
  docs/
```

Rules: Core compiles and tests on macOS with `swift test`. Nothing in Core imports SwiftUI, GRDB or Foundation Models. Feature modules depend on Core, Design and Persistence protocols, never on each other. The app target wires concrete types.

## 7. Design system summary

Idea: a pantry ledger. Paper, ink, stamped labels, a shelf. Not a dashboard. The identity lives in colour, type and illustration; structure is native iOS (2026-10-17 redesign, from `docs/research/06-ui-ux-audit.md` and `07-meal-planner-ux-best-practices.md`).

- Navigation: five tabs with plain task words, Tonight, Plan, Pantry, Recipes, Groceries (code names stay `ledger`, `shelves`, `grocery`); every tab root has a Fraunces large title, a one-line subtitle saying what the screen is for, Settings at the leading edge and its add or share action as a toolbar button at the trailing edge. No floating action buttons over content.
- First run: one welcome screen (promise plus four "how it works" rows, one Get started), then three optional questions (allergies, diet and health, household and weeknight time) with a progress bar, Back, Continue and "Set up later". Moving on or leaving early never clears an answer. Goal, equipment, birth year, numbers, timers and AI help live in Settings.
- Components: capsule buttons (filled brand, brand-tinted, text), capsule choice chips with a check, paper cards with an outline and 18 pt continuous corners, dish tiles in a food-group tint in place of stock photos (an imported recipe's own photo replaces its tile), icon-and-words meta labels, pill badges, toasts with Undo, centred empty states with an illustration and the screen's main action.
- Typography: Fraunces (static instances, upright 500-700) for display at 22pt and above, scaling fully with Dynamic Type (an earlier cap at `.accessibility2` was removed because Xcode's accessibility audit flags any capped text and Apple's Larger Text criterion needs at least 200% growth); SF Pro for body and UI; Commit Mono for stamps and quantities. Never italic or light Fraunces, never Inter.
- Colour tokens (light / dark): canvas #F5F1E6 / #161915, raised #FFFDF7 / #20241E, sunken #EBE5D4 / #10120F, hairline #D6CEB8 / #363B32, strong line #8C8570 / #7C7866, ink primary #1F2620 / #F0ECDD, secondary #4F5448 / #BDBAA8, tertiary #5F6256 / #9A9885, brand paprika #A83F18 / #F0875A, second verdigris #2C6B5B / #6FC0A8, spot mustard #E3A82B (fill only), success #2F6B34 / #8FCB84, warning #8A5700 / #E5B04A, danger beet #9C1F43 / #EE8CA6, info #2F5D7C / #8DB9D8; food groups produce #4A8A3C / #86C46F, grains #B07F1E / #E0AE4A, protein #3E6F8E / #78AECF, dairy #B05A78 / #E48FAE, fats #76772A / #B9BA52, legumes #8A5A3A / #C99572.
- Shape: radii 2 (stamps), 8 (fields), 10 (tiles), 12 (cards and notices), 18 (paper panels), 24 (sheets), capsules for buttons, chips and badges. Hairline rules and flat tint steps; no shadows, no nested cards, no gradients, no glow, no emoji, no stock photos.
- Motion: 120 / 220 / 360 ms; `.snappy` taps, `.smooth` layout, one `.bouncy` "stamped" save; Reduce Motion swaps to crossfades.
- Voice: dry, no exclamation marks, no em dashes, no moralising; every recommendation gives a reason and one alternative.

## 8. Accessibility bar

WCAG 2.2 AA written bar, Apple's Nutrition Label criteria as the release gate. Must-haves: every element labelled with role and state; Voice Control names match visible text; AX5 without truncation; 4.5:1 text and 3:1 controls in every mode; no colour-only meaning; Reduce Motion honoured; tap alternatives for every drag or swipe; 44pt targets; allergen "unknown" never shown as safe; calories and weight goals off by default; focus moves to new headings and async results are announced; sound cues have visual and haptic twins. `performAccessibilityAudit` runs in UI tests on every primary screen.

## 9. Privacy

On-device-first storage; the sensitive profile (medical, religious) never leaves the device and never enters analytics; a consent screen before the first cloud assistant call; PII-free prompt builder; medical disclaimer at condition setup; HealthKit, when it ships, writes only user-logged data; request zero data retention from Anthropic once on a paid plan.

## 10. Risks and the checks that catch them

| Risk | Caught by |
|---|---|
| Allergen leak through a model edit | PlanVerifier tests with adversarial fixtures; proxy never receives the allergen list as a guard |
| Nutrient maths wrong | NutritionCalculator golden tests against hand-computed recipes |
| Planner infeasible for narrow diets | Feasibility test across simulated personas; graceful "could not fill Thursday" state |
| UI unreadable at AX sizes or on glass | Accessibility audit UI tests; snapshot tests at AX3 |
| Cache misses blow up cost | Proxy test asserts a byte-identical static prefix; `cache_read_input_tokens` logged |
| Xcode-only code written blind | Wave 3 compiles and tests with `xcodebuild` before review |
