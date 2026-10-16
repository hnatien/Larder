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

`LarderProxyBaseURL` in the app's Info.plist (set under `info.properties` in `project.yml`) is a placeholder, `https://proxy.larder.app`, until the proxy is deployed; point it at your own Worker for development.
Devices prove themselves with App Attest: the app attests a Secure Enclave key once, then signs an assertion for each session. The Simulator has no App Attest, so Debug builds there send the development attestation secret from the `LARDER_DEV_CLIENT_SECRET` environment variable instead: set it in the scheme's Run environment, never in source. Release builds never send it.
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
| `Scripts/screenshots.sh` | Runs only the screenshot test, writing each tab in light and dark mode to `docs/screenshots/<tab>-<light\|dark>.png` |

UI tests launch the app with `-LarderUITestMode`: an in-memory store with the seed library, eight shelf items and a saved profile, so nothing touches your simulator's data. Add `-LarderUITestOnboarding` to start at onboarding instead.

## Folders

| Path | Contents |
|---|---|
| `Package.swift`, `Sources/`, `Tests/` | The LarderKit package: core domain, persistence, assistant, design system and feature modules, one test target each |
| `App/` | The iOS app (dependency container, tabs, App Intents), the Today widget, code both share, and UI tests |
| `Scripts/` | Build and test entry points |
| `docs/screenshots/` | Screenshots from `Scripts/screenshots.sh` |
| `docs/BLUEPRINT.md` | Every architectural decision; read this first |
| `docs/research/` | The research reports behind the blueprint |
