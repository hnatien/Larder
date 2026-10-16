# Larder status, 2026-10-16

What exists, how it was verified, what is still open. Decisions are in `docs/BLUEPRINT.md`; evidence is in `docs/research/`.

## What was built

| Milestone | Contents | Verification |
|---|---|---|
| Research | Five reports: users and market, visual identity, accessibility, nutrition and recommendation engine, iOS stack | `docs/research/01..05` |
| Scaffold | SwiftPM package `LarderKit` with ten targets, XcodeGen project, scripts, domain model, ports | `swift build`, app builds for simulator |
| Core engine | Units, nutrition calculator, DGA 2025 / WHO targets, shelf balance, two-path allergen engine with lexicon and exceptions, diet and religious filters, grocery list builder, constraint compiler, scorer, Tonight picker, week planner with local search, independent verifier, swap suggester | 221 Swift Testing tests, including zero hard violations over 150 persona-seed cases and a 7-day plan under 0.5 s |
| Persistence | GRDB SQLite schema, FTS5 search, repositories, idempotent seed loader with slug-derived IDs, erase-all | 55 tests |
| Assistant client | Proxy client with session caching, PII-free profile summary, prompt sanitiser, deterministic pantry parser, router (on-device, proxy, deterministic, consent-gated) | 78 tests, including proofs that no sensitive field or network call escapes |
| On-device AI | Foundation Models backend with @Generable types, context guard, error mapping, Vision receipt and barcode readers | 55 tests; the live Foundation Models test ran on this Mac |
| Design system | 22 colour tokens light and dark with high-contrast variants, typography (Fraunces or New York fallback, SF Pro, Commit Mono or SF Mono fallback), spacing, radius, motion with Reduce Motion, Copy catalogue, 12 components | 77 tests, including WCAG ratios for every ink/surface pair and a banned-pattern scan |
| Features | Shelves (pantry), Ledger and Tonight, Recipes with import and cooking mode, Grocery, Account with onboarding, StoreKit 2 entitlements, paywall, settings and export | 49 + 68 + 142 + 23 + 85 tests |
| App | Dependency graph, onboarding gate, five tabs, App Intents and Shortcuts, today widget via App Group snapshot, UI tests with accessibility audits and screenshots | App and widget build warning-free; five UI tests pass (audits on every tab, onboarding, AX3, recipe-to-plan flow, screenshots) |
| Proxy | Cloudflare Worker in TypeScript with session tokens, App Store JWS entitlement verification, KV quotas, four structured-output routes on Haiku 5.5 and Sonnet 5.5, cache-stable prompts | 107 vitest tests, `tsc` clean |
| Seed data | 113 foods (approximate values, flagged), 42 original recipes, validator script | `python3 -I Tools/validate-seed.py` |

Package total: 853 Swift Testing tests across ten targets, all passing on 2026-10-16.

## Commands

```bash
Scripts/test-packages.sh        # swift test for the whole package
Scripts/generate.sh             # xcodegen
Scripts/build-app.sh            # simulator build
Scripts/test-app.sh             # UI tests with accessibility audits
Scripts/screenshots.sh          # regenerates docs/screenshots
cd Server/larder-proxy && npm test && npm run typecheck
```

## Open items

Ordered by importance.

1. App Attest verification in the proxy is an interface with a 501 stub; only dev attestation exists. Needed before any real user traffic.
2. Fonts are not bundled. Drop Fraunces static instances and Commit Mono into `Sources/LarderDesign/Resources/Fonts/` (see its README); until then New York and SF Mono stand in.
3. Seed nutrient values are approximate and labelled `seedApproximate`. Replace through an FDC import (CC0) before launch; the Food model and seed loader already carry FDC IDs and sources.
4. The medical disclaimer, allergen wording and paywall copy need a registered dietitian and counsel review (GDPR Article 9, Washington MHMDA, App Store 1.4.1).
5. Live camera scanning UI (DataScannerViewController) is not wired; image-based barcode and receipt reading exists.
6. Feature modules keep some strings in local `String(localized:)` calls instead of the Design catalogue.
7. The Recipes list uses a card per row; the design brief prefers ledger rows with hairlines.
8. The App Group container for the widget is unverified without code signing; the widget shows "Nothing planned" when the container is unavailable.
9. `ParsedPantryLine` has no best-by field, so model-extracted best-by hints are dropped.
10. The parse-pantry system prompt is under the 512-token caching minimum; it will not cache.
11. Not run: a real StoreKit sandbox purchase, VoiceOver and Voice Control manual passes, a physical device.

## Known audit limitation

`performAccessibilityAudit` reports contrast issues for list content that scrolls beneath the Liquid Glass tab bar or the floating action capsule, sometimes without an element. The UI tests skip only those: issues whose element frame intersects the tab bar, a floating action or the area below the scroll view, and no-element contrast issues while a tab bar is on screen. Every skip is logged with its description. The same text passes when scrolled clear. The one other exclusion is "Text clipped" on Apple's own search field.
