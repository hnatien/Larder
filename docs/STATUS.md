# Larder status, 2026-10-17

What exists, how it was verified, what is still open. Decisions are in `docs/BLUEPRINT.md`; evidence is in `docs/research/`.

## What was built

| Milestone | Contents | Verification |
|---|---|---|
| Research | Seven reports: users and market, visual identity, accessibility, nutrition and recommendation engine, iOS stack, a UI/UX audit, and meal-planner UX best practices | `docs/research/01..07` |
| Scaffold | SwiftPM package `LarderKit` with ten targets, XcodeGen project, scripts, domain model, ports | `swift build`, app builds for simulator |
| Core engine | Units, nutrition calculator, DGA 2025 / WHO targets, shelf balance, two-path allergen engine with lexicon and exceptions, diet and religious filters, grocery list builder, constraint compiler, scorer, Tonight picker, week planner with local search, independent verifier, swap suggester | 221 Swift Testing tests, including zero hard violations over 150 persona-seed cases and a 7-day plan under 0.5 s |
| Persistence | GRDB SQLite schema, FTS5 search, repositories, idempotent seed loader with slug-derived IDs and FDC ids, erase-all | 61 tests |
| Assistant client | Proxy client with App Attest sessions (attest once, assert after, re-attest on a lost key, dev-secret fallback on the Simulator), session caching, PII-free profile summary, prompt sanitiser, deterministic pantry parser, router (on-device, proxy, deterministic, consent-gated) | 90 tests, including proofs that no sensitive field or network call escapes |
| On-device AI | Foundation Models backend with @Generable types, context guard, error mapping, Vision receipt and barcode readers | 55 tests; the live Foundation Models test ran on this Mac |
| Design system | 22 colour tokens light and dark with high-contrast variants, typography (bundled Fraunces static instances, SF Pro, bundled Commit Mono), spacing, radius, motion with Reduce Motion, one Copy catalogue for every feature string, 15 components plus a chip flow layout and optional illustrations | 81 tests, including WCAG ratios for every ink/surface pair, a banned-pattern scan, font registration by PostScript name and catalogue coverage of feature strings |
| Features | Pantry, Plan and Tonight, Recipes with import, add-to-plan by day and cooking mode, Groceries, Account with welcome screen and three-question setup, StoreKit 2 entitlements, paywall, settings and export | 56 + 72 + 142 + 24 + 83 tests |
| App | Dependency graph, onboarding gate, five tabs, app icon and launch screen, App Intents and Shortcuts, today widget via App Group snapshot, UI tests with accessibility audits and screenshots | App and widget build warning-free; six UI tests pass (audits on every tab and Settings, welcome and setup, AX3, recipe-to-plan-by-day flow, "Set up later" keeps allergens, screenshots of 21 screens in light and dark) |
| Proxy | Cloudflare Worker in TypeScript with App Attest attestation and assertion verification (stateless challenges, key-derived session subjects), session tokens, App Store JWS entitlement verification, KV quotas, four structured-output routes on Haiku 5.5 and Sonnet 5.5, cache-stable prompts | 165 vitest tests, `tsc` clean |
| Seed data | 113 foods: 33 from FDC Foundation Foods (2026-04), 77 from SR Legacy (2018-04), 3 approximate and flagged; 42 original recipes; reviewable mapping, importer and validator | `python3 -I Tools/validate-seed.py`; the importer is byte-for-byte reproducible |

Package total: 886 Swift Testing tests across ten targets, all passing on 2026-10-17.

## Commands

```bash
Scripts/test-packages.sh        # swift test for the whole package
Scripts/generate.sh             # xcodegen
Scripts/build-app.sh            # simulator build
Scripts/test-app.sh             # UI tests with accessibility audits
Scripts/screenshots.sh          # regenerates docs/screenshots
cd Server/larder-proxy && npm test && npm run typecheck
python3 -I Tools/import-fdc.py --foundation <foundation json> --sr-legacy <sr legacy json>   # rewrites seed-foods.json
```

The FDC JSON comes from https://fdc.nal.usda.gov/download-datasets (CC0) and is not stored in the repository. Matching rules and one decision per food are in `Tools/fdc-mapping.json`.

## Open items

Ordered by importance.

1. App Attest has not run against a genuine Apple attestation. The Simulator has no App Attest, so the verifier is tested with a generated chain of Apple's structure. Before launch: set `APPLE_TEAM_ID` in `wrangler.toml`, run once on a physical device, and keep `ALLOW_DEV_ATTESTATION` off. Fraud-metric receipts are not used.
2. Three seed foods have no defensible FDC match and stay `seedApproximate`: cream (FDC has no double cream), mixed seeds (no fixed blend) and vinegar (no white wine vinegar). Added sugar is `null` for every food because neither dataset reports it.
3. `Tools/validate-seed.py` allows FDC foods a 20% energy tolerance (15% for approximate foods), sugar up to 5% above carbohydrate, and no energy check for foods tagged `alcohol`, because FDC's own records need it.
4. The medical disclaimer, allergen wording and paywall copy need a registered dietitian and counsel review (GDPR Article 9, Washington MHMDA, App Store 1.4.1).
5. Live camera scanning UI (DataScannerViewController) is not wired; image-based barcode and receipt reading exists. Add food offers typing and one-tap staples only.
6. `App/Larder/RootView.swift` and the App Intents (`WhatsForDinnerIntent`, `OpenTonightIntent`, `LarderShortcuts`) still use local strings; App Intents strings probably belong in an app-target catalogue.
7. The App Group container for the widget is unverified without code signing; the widget shows "Nothing planned" when the container is unavailable.
8. `ParsedPantryLine` has no best-by field, so model-extracted best-by hints are dropped.
9. The parse-pantry system prompt is under the 512-token caching minimum; it will not cache.
10. Not run: a real StoreKit sandbox purchase, VoiceOver and Voice Control manual passes, a physical device.
11. Recipes have no photos; dish tiles in a food-group tint stand in. Recipe import does not read the page's image yet.
12. Pantry amounts are stored in grams; counts such as "6 eggs" are derived from the food's countable portion, so an item without one shows grams.
13. Cooking timers do not schedule local notifications, so a timer that finishes while Larder is in the background is silent.

## Known audit limitation

`performAccessibilityAudit` reports contrast issues for list content that scrolls beneath the Liquid Glass tab bar, sometimes without an element, and for filter chips partly past the side of the window. The UI tests skip only those: issues whose element frame intersects the tab bar, the area below the scroll view or the area beyond the window's sides, and no-element contrast issues while a tab bar is on screen. Every skip is logged with its description. The same text passes when scrolled clear. The one other exclusion is "Text clipped" on Apple's own search fields (Recipes and Pantry).
