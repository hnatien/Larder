# Larder research 05: iOS technology stack, October 2026

Researched 2026-10-16 with local verification on the development Mac.

## 0. Verified locally

- No `xcodebuild`: `xcode-select -p` points at the Command Line Tools; `xcodebuild`, `simctl` and the iphoneos SDK are missing. Xcode.app is mandatory for building or testing the iOS app.
- `swift build` / `swift test` (tools 6.4) under CLT: SwiftUI views, `@Observable`, `.glassEffect()`, imports of HealthKit/StoreKit/FoundationModels/SwiftData, `.defaultIsolation(MainActor.self)` all compile. These fail because Apple's macro plugins ship only with Xcode: `@State` and other SwiftUI property-wrapper macros, `@Generable` (FoundationModelsMacros), `@Model` (SwiftDataMacros), `#Preview`. XCTest is absent. Swift Testing `@Test` works only with `swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`.
- GRDB 7.11.1 builds cleanly under CLT. XcodeGen 2.46.0 generates a project with synced folders and local packages without Xcode present.

## 1. Platform versions

| Item | Value | Confidence |
|---|---|---|
| Shipping OS | iOS 27.0.1 (27.0 on 2026-09-14; 27.0.1 on 09-28); iOS 26.7 still maintained | High (https://developer.apple.com/news/releases/) |
| Xcode | 27.1 (2026-10-15); 27.2 in beta | High |
| Swift | 6.4 (2026-09-15) | High (https://www.swift.org/blog/swift-6.4-released/) |
| Xcode 27 requirements | Apple silicon, macOS 26.6+ | Medium (third party) |
| Submission floor | Since 2026-04-28: Xcode 26+, iOS 26 SDK | High |
| iOS 27 SDK requirement | Probably April 2027 | Low (inference) |
| Adoption | iOS 26 on 79% of all iPhones as of 2026-06-07; no iOS 27 figure yet | High but stale |

WWDC25 (iOS 26): Liquid Glass; Foundation Models with 4096-token context; Swift 6.2 default MainActor isolation; Vision `RecognizeDocumentsRequest`.
WWDC26 (iOS 27, https://www.apple.com/newsroom/2026/06/apple-aids-app-development-with-new-intelligence-frameworks-and-advanced-tools/): Foundation Models provider-agnostic `LanguageModel` protocol with image input, Private Cloud Compute and Dynamic Profiles; Core AI framework; Siri AI with App Intents schemas; agentic coding in Xcode 27; Liquid Glass refresh; Swift 6.4.

Recommendation: Xcode 27.1, Swift 6.4, Swift 6 language mode. Deployment floor iOS 26.0 with `#available` gates for iOS 27 features; revisit in Q1 2027.

## 2. SwiftUI state of the art

- Liquid Glass: standard components adopt it on rebuild; custom surfaces use `.glassEffect(_:in:)`, `GlassEffectContainer`, `.buttonStyle(.glass)` / `.glassProminent` (https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass). Pitfalls: remove custom bar and sheet backgrounds, don't overuse glass, use `scrollEdgeEffectStyle` for legibility, test with Reduce Transparency. No opt-out when building for iOS 27 (`UIDesignRequiresCompatibility` is ignored). iOS 27 adds a user transparency slider and `Tab(role: .prominent)`.
- Navigation: `TabView` with `Tab`, `NavigationStack` with a typed path, `NavigationSplitView` on iPad. iOS 27 adds `.navigationTransition(.crossFade)`, `.reorderable()` / `.reorderContainer(for:)` (useful for plan slots) and `.swipeActionsContainer()`.
- `@Observable` (iOS 17) is the default; Swift 6.4 adds finer-grained observation (SE-0506). Avoid `ObservableObject`.
- Concurrency: `.defaultIsolation(MainActor.self)` plus `NonisolatedNonsendingByDefault` on app and UI targets only; Core, Domain and Persistence stay nonisolated and `Sendable`, with `@concurrent` for heavy work. XcodeGen settings: `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY: YES`.
- SwiftData vs GRDB: SwiftData iOS 27 adds `sectionBy`, `.codable` attributes, `ResultsObserver`, `HistoryObserver`; CloudKit sync forbids unique constraints and non-optional relationships; `@Model` cannot compile without Xcode. GRDB 7.11.1 supports Swift 6, FTS5, background reads and writes, explicit migrations. SQLiteData 1.12.1 (GRDB-based, `@FetchAll`, CloudKit sync and sharing) is an option if sync becomes a launch requirement.
- Swift Testing is the default; Swift 6.4 lets `XCTAssert` run inside Swift Testing and adds repetition and attachments.

Recommendation: GRDB for the store (recipes, pantry, plans, FTS5, migrations testable on macOS); repository protocols so SQLiteData can be added for iCloud sync later; `@Observable` view models; Swift Testing; MainActor default only for UI targets.

## 3. On-device intelligence

Foundation Models (https://developer.apple.com/documentation/foundationmodels): `SystemLanguageModel.default.availability` returns `.available` or `.unavailable(.deviceNotEligible | .modelNotReady)`; three on-device model versions (iOS 26.0-26.3, 26.4, 27.0) so prompts must be versioned; context 4096 on iOS 26.0 and 8192 on iOS 27 (read `contextSize`); good at extraction, classification, tagging, short rewrites, `@Generable` structured output, tool calling, image prompts via `Attachment(image)` on iOS 27; not good at long multi-constraint plans, nutrition math, long context or world knowledge. iOS 27 adds `PrivateCloudComputeLanguageModel` (32K context, reasoning levels, daily per-user quota, managed entitlement `com.apple.developer.private-cloud-compute`, free under 2M first-time downloads), `OCRTool`, `BarcodeReaderTool`, Dynamic Profiles and an Evaluations framework.

Vision: `RecognizeDocumentsRequest` (iOS 26) for receipts and labels; `RecognizeTextRequest`, `DetectBarcodesRequest`, `DataScannerViewController` for live scanning. No first-party food recogniser: use the iOS 27 image-prompted model with a confirmation UI. Core ML and Core AI not needed in v1.

| Task | Where |
|---|---|
| Nutrient totals, scoring, allergen filters | Deterministic Swift; never an LLM |
| Parse "chicken, rice, 20 min, no dairy"; normalise ingredients; tag; swap phrasing | On-device Foundation Models with `@Generable` |
| Receipt or fridge photo to draft pantry list | Vision document or barcode first; image-prompted FM on iOS 27; user confirms |
| Weekly plan explanation, recipe adaptation, long context | Claude via proxy |
| Mid tier | Private Cloud Compute if entitled and evals pass |

Devices without Apple Intelligence: one `IntelligenceProvider` protocol with the order on-device, PCC, Claude, deterministic fallback. Core planning never depends on FM availability.

## 4. System integration

- App Intents + Siri: recipes, plans and "log meal" as `AppEntity` / `AppIntent`; `IndexedEntity` for the semantic index; no food or recipe schema domain exists, so use plain intents plus the Reminders schema for the shopping list. New: `EntityCollection`, `LongRunningIntent`, AppIntentsTesting.
- WidgetKit: a "today's meals" widget and an interactive "mark eaten" toggle; a `ControlWidget` is cheap; widgets customisable through App Intents in iOS 27.
- Live Activities: skip in v1 (cooking timer is the only fit).
- HealthKit: write dietary `HKQuantityType`s (energy, protein, carbohydrates, fat, fibre, sugar, sodium), optionally grouped as an `HKCorrelation`; request share authorisation only for written types; read authorisation is opaque.
- Watch: defer to v2. iPad/Mac: iPhone-first with adaptive `NavigationSplitView`; Mac runs the iPad build.

## 5. Monetisation

StoreKit 2 (`Product`, `Transaction.currentEntitlements`, `Transaction.updates` observed at launch, `appAccountToken` to link the proxy account, `.manageSubscriptionsSheet`, `SubscriptionStoreView` on iOS 17, `SubscriptionOfferView` on iOS 26). Offers: introductory (free trial), promotional, offer codes, win-back (iOS 18). New in 26.5/27: monthly billing on a 12-month commitment (not in the US), offer-code `VerificationResult`, Retention Messaging, Bundles preview. Testing with a `.storekit` config, Transaction Manager and sandbox. RevenueCat 5.95.0: free below $2.5k MTR then 1%; useful for server-side entitlements, webhooks and paywall experiments; no longer needed for correctness.

Recommendation: native StoreKit 2 with trial, annual and monthly, win-back configured; proxy verifies the signed transaction (JWS) and subscribes to App Store Server Notifications V2; consider RevenueCat only for ready-made entitlements and paywall experiments.

## 6. Networking and backend

- Client: `URLSession` async/await (`bytes(for:)` for SSE), an actor-wrapped client behind a protocol, `Codable` models, retry with backoff, cancellation; offline-first from the local DB with queued writes.
- Models (https://platform.claude.com/docs/en/release-notes/overview): `claude-haiku-5-5` (2026-10-07), `claude-sonnet-5-5` (2026-09-28), `claude-opus-5-5`. Pin IDs.
- Never bundle an API key. Two options: (1) direct with App Attest via Anthropic's App Attest flow and the `ClaudeForFoundationModels` 0.2.3 beta package (iOS 27 only, no per-user metering); (2) a thin proxy (Cloudflare Worker, Vercel or Supabase edge function) holding the key, verifying App Attest assertions or Sign in with Apple plus StoreKit JWS, enforcing per-user quotas, token and model caps, a kill switch, prompt caching and content-free logging.

Recommendation: build the proxy for v1; revisit the direct path when the Swift package leaves beta and the floor is iOS 27.

## 7. Project structure and tooling

- Layout: `Packages/` with SwiftPM packages (tools 6.4, platforms iOS 26 and macOS 26): Core (pure domain, nutrition rules, planner, protocols), Persistence (GRDB), Networking, DesignSystem (SwiftUI), Feature modules, LarderIntelligence (Foundation Models, Xcode-only). A thin app target plus widget and App Intents extensions. MainActor default only on UI targets.
- XcodeGen 2.46.0 `project.yml`: `deploymentTarget.iOS: "26.0"`, `packages:` with `path:`, `sources` with `type: syncedFolder`, settings `SWIFT_VERSION`, `SWIFT_DEFAULT_ACTOR_ISOLATION`, `SWIFT_APPROACHABLE_CONCURRENCY`, `GENERATE_INFOPLIST_FILE`, `ENABLE_USER_SCRIPT_SANDBOXING`; entitlements for HealthKit, App Attest, iCloud, PCC; schemes with a StoreKit config. Git-ignore the `.xcodeproj` and regenerate.
- Lint and format: SwiftLint 0.65.1; `swift-format` already ships in the CLT.
- Installing Xcode: `brew install xcodesorg/made/xcodes` then `xcodes install 27.1` (Apple ID prompt), or `mas install 497799835` (App Store sign-in plus admin password). Then `sudo xcode-select -s /Applications/Xcode.app`, `sudo xcodebuild -license accept`, `xcodebuild -runFirstLaunch`, `xcodebuild -downloadPlatform iOS`. `xcodebuild` cannot run on CLT alone.
- CI: GitHub Actions Xcode 27 runner image (public preview, arm64); `swift test` for packages, then `xcodebuild test -scheme Larder -destination 'platform=iOS Simulator,name=iPhone 17' | xcbeautify`. swift-snapshot-testing 1.19.6 for a few key screens, CI only.

## 8. Performance and quality

- Images: `AsyncImage` gains caching only in iOS 27; with an iOS 26 floor use Nuke 13.2.0 (`NukeUI.LazyImage`, prefetching, downsampling).
- Launch: defer everything off the first frame (lazy DB open, no synchronous network, no FM prewarm until idle); measure with the App Launch template and MetricKit.
- Instruments SwiftUI template for body-evaluation cost; Foundation Models instrument for token use.
- `sensoryFeedback(_:trigger:)` for haptics; TipKit for onboarding hints.

## Library verdicts

| Library | Min OS | Verdict |
|---|---|---|
| SwiftUI + Liquid Glass | iOS 26 | Adopt; system components, minimal custom glass |
| `@Observable` | iOS 17 | Adopt |
| Swift Testing | toolchain | Adopt |
| SwiftData | iOS 17 | Avoid for the core store |
| GRDB 7.11.1 | iOS 13 | Adopt |
| SQLiteData 1.12.1 | iOS 16 | Consider for CloudKit sync |
| FoundationModels | iOS 26 (images, PCC iOS 27) | Adopt behind a protocol |
| Private Cloud Compute | iOS 27 | Consider |
| ClaudeForFoundationModels 0.2.3 | iOS 27 | Consider later |
| Vision / DataScanner | iOS 16-26 | Adopt |
| Core ML / Core AI | iOS 11 / 27 | Avoid in v1 |
| App Intents | iOS 16 | Adopt |
| WidgetKit / ControlWidget | iOS 14 / 18 | Adopt |
| ActivityKit | iOS 16.1 | Avoid in v1 |
| HealthKit nutrition | iOS 8 | Adopt |
| watchOS companion | watchOS 27 | Avoid in v1 |
| StoreKit 2 + `SubscriptionStoreView` | iOS 15 / 17 | Adopt |
| RevenueCat | n/a | Consider |
| TipKit / `sensoryFeedback` | iOS 17 | Adopt |
| Nuke 13.2.0 | iOS 16 | Adopt |
| Kingfisher | iOS 15 | Avoid (redundant) |
| XcodeGen 2.46.0 | n/a | Adopt |
| SwiftLint / swift-format | n/a | Adopt one formatter |
| swift-snapshot-testing | n/a | Consider, CI only |

Open items: PCC entitlement terms and quotas are not public; the iOS 27 camera nutrition logging feature is unconfirmed; Foundation Models open-sourcing unconfirmed.
