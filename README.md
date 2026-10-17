# Larder

Larder is a native iOS meal planner that plans loosely, shops once and adapts to what you actually cooked.
A deterministic Swift engine builds every plan from your shelves, constraints and nutrient targets, and a thin Claude proxy only explains, parses and proposes edits.
Allergen and dietary constraints are enforced in code, calories are off by default, and the sensitive profile never leaves the device.

## Prerequisites

- Xcode 27.1 at `/Applications/Xcode.app` with the iOS 27.1 simulator runtime. `Scripts/env.sh` sets `DEVELOPER_DIR` for you, so `xcode-select` can keep pointing at the Command Line Tools.
- XcodeGen 2.46 (`brew install xcodegen`).

## Run the app

1. `Scripts/generate.sh` generates `Larder.xcodeproj` from `project.yml` (the project is git-ignored). Run it again after changing `project.yml`.
2. `Scripts/build-app.sh` builds the app and the Today widget for the first available iPhone simulator.
3. Open `Larder.xcodeproj` and run the `Larder` scheme, or install the built app with `xcrun simctl install booted <path to Larder.app>`.

A fresh install starts at onboarding. The seed foods and recipes load on first launch; bump `AppDependencies.seedVersion` when the files in `App/Larder/Resources/Seed` change.

### Assistant proxy

`LarderProxyBaseURL` in the app's Info.plist comes from the `LARDER_PROXY_BASE_URL` build setting in `project.yml`: Debug uses `http://localhost:8787`, where `npx wrangler dev` in `Server/larder-proxy` serves the proxy (see its README), and Release uses the placeholder `https://proxy.larder.app` until the proxy is deployed.
Devices prove themselves with App Attest: the app attests a Secure Enclave key once, then signs an assertion for each session. The Simulator has no App Attest, so Debug builds there send the development attestation secret from the `LARDER_DEV_CLIENT_SECRET` environment variable instead. `Scripts/generate.sh` puts it in the scheme's Run environment, taking it from that variable or else from `DEV_CLIENT_SECRET` in `Server/larder-proxy/.dev.vars`; the generated project is git-ignored, so the secret never reaches source. Run the app from Xcode to get it; `simctl launch` needs `SIMCTL_CHILD_LARDER_DEV_CLIENT_SECRET` instead. Release builds never send it.
The cloud assistant is only called after the user allows AI help; everything else runs on device.

### StoreKit testing

The `Larder` scheme's Run action uses `App/Larder/Resources/Larder.storekit`, so Larder Plus products, the trial and purchases work in the simulator without App Store Connect. Manage test transactions from Debug > StoreKit > Manage Transactions. The file is not copied into the app bundle.

## Scripts

| Script | What it does |
|---|---|
| `Scripts/test-packages.sh` | `swift test` for every LarderKit target; extra arguments pass through, e.g. `--filter LarderCoreTests` |
| `Scripts/generate.sh` | Generates `Larder.xcodeproj` from `project.yml` |
| `Scripts/build-app.sh` | Builds the Larder app and widget for the first available iPhone simulator |
| `Scripts/test-app.sh` | Runs the UI tests on the same simulator: accessibility audits of every tab, Settings and onboarding, an AX3 Dynamic Type pass and the screenshots; extra arguments pass to `xcodebuild`, e.g. `-only-testing:LarderUITests/LarderUITests/testDynamicTypeAX3` |
| `Scripts/screenshots.sh` | Runs only the screenshot test, writing every screen (welcome, setup, each tab, empty states, the planned week, meal sheet, recipe detail, cooking, adding and editing food, Settings) in light and dark mode to `docs/screenshots/<screen>-<light\|dark>.png` |

UI tests launch the app with `-LarderUITestMode`: an in-memory store with the seed library, eight pantry items and a saved profile, so nothing touches your simulator's data. Add `-LarderUITestOnboarding` to start at the welcome screen instead, or `-LarderUITestEmptyPantry` to start with nothing in the pantry.

## Folders

| Path | Contents |
|---|---|
| `Package.swift`, `Sources/`, `Tests/` | The LarderKit package: core domain, persistence, assistant, design system and feature modules, one test target each |
| `App/` | The iOS app (dependency container, tabs, App Intents), the Today widget, code both share, and UI tests |
| `Scripts/` | Build and test entry points |
| `docs/screenshots/` | Screenshots from `Scripts/screenshots.sh` |
| `docs/BLUEPRINT.md` | Every architectural decision; read this first |
| `docs/research/` | The research reports behind the blueprint |
| `Tools/` | Seed validator, FDC importer and its mapping, font naming helper |

## Data and font credits

- Nutrient data: USDA FoodData Central, Foundation Foods (April 2026) and SR Legacy (April 2018), public domain (CC0).
- Fraunces (Undercase Type) and Commit Mono (Eigil Nikolajsen), SIL Open Font License 1.1; licences sit next to the fonts in `Sources/LarderDesign/Resources/Fonts/`.
