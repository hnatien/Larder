# Larder research 03: accessibility and inclusive UX

Researched 2026-10-16. Items marked [unverified] come from a single secondary source or the researcher's recollection.

## 1. Apple requirements and tooling

Accessibility Nutrition Labels (App Store, iOS 26+): voluntary now, Apple says they will become required (no date). Declarable: VoiceOver, Voice Control, Larger Text, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion, Captions, Audio Descriptions (https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels). The rule for every feature: users must complete all common tasks with it (primary functions plus first launch, sign-in, purchase, settings; WWDC25 224). Accuracy matters more than breadth; don't claim Captions or Audio Descriptions (no video).

Per-label criteria:
- VoiceOver: every element has a concise label, role and value; state in traits not label text; logical cursor movement on screen change; transient banners via `AccessibilityNotification`; drag and multi-touch have alternatives; modals trap focus and are escapable; charts have a text alternative.
- Voice Control: every tappable works with "Show numbers" and "Show names"; label contains the visible text (`accessibilityInputLabels` for variants); swipe and long-press have custom actions; dictation works in every field.
- Larger Text: text and meaningful icons reach at least 200%; wrap or stack rather than truncate; tab bar uses the Large Content Viewer.
- Sufficient Contrast: 4.5:1 text, 3:1 controls and state; test with Bold Text, Increase Contrast, Reduce Transparency, light and dark.
- Differentiate Without Color Alone: shape, icon or text in addition to colour; the Grayscale filter is the test.
- Reduced Motion: drop parallax, spinning, zoom and depth; swap in dissolves.

Tooling: Accessibility Inspector for contrast and audits; `performAccessibilityAudit` in UI tests since Xcode 15 (WWDC23 10035) with `XCUIAccessibilityAuditType` scoping and an issue handler for known false positives; Assistive Access scene in iOS 26 (`AssistiveAccess` scene beside `WindowGroup`, `accessibilityAssistiveAccessEnabled` environment; WWDC25 238) which maps well to a "just tell me what to cook" mode.

OS 26/27: Accessibility Reader (systemwide reading mode) rewards plain semantic text; Liquid Glass is altered by Reduce Transparency, Increase Contrast and Reduce Motion with no full off switch, so never put text on glass over busy imagery; iOS 27 (September 2026) adds Voice Control acting on unlabeled elements and richer VoiceOver image descriptions (label everything anyway).

Recommendation: v1 label targets are VoiceOver, Voice Control, Larger Text, Sufficient Contrast, Differentiate Without Color Alone, Reduced Motion, Dark Interface. `performAccessibilityAudit` in CI on every primary screen. Assistive Access scene in v1.x.

## 2. SwiftUI implementation checklist (WWDC24 10073)

- Prefer styles (`toggleStyle`, `buttonStyle`) over custom views so labels, traits and actions survive.
- `.accessibilityElement(children: .combine)` on cards; a meal card reads as one element ("Chicken stir fry, 25 minutes, contains peanuts") with custom actions Swap, Remove, Mark cooked via `accessibilityActions`.
- Labels are text only, never "button" or "selected" (traits). Voice Control label must contain the visible text.
- `accessibilityValue` and `.isSelected` traits updated on change.
- `accessibilityRotor` to jump between days, meals and cooking steps.
- `accessibilityRepresentation` for custom controls (servings stepper, drag-sort list).
- Dynamic Type to AX5: text styles only, `@ScaledMetric` for icons and padding, `ViewThatFits` or `dynamicTypeSize.isAccessibilitySize` to switch HStack to VStack, Large Content Viewer for the tab bar, no `lineLimit(1)` or fixed heights.
- Environment flags: `accessibilityReduceMotion`, `accessibilityReduceTransparency`, `colorSchemeContrast`, `accessibilityDifferentiateWithoutColor`, `legibilityWeight`, `accessibilityShowButtonShapes`, `accessibilityVoiceOverEnabled`, `accessibilitySwitchControlEnabled`. `.accessibilityIgnoresInvertColors()` on food photos.
- 44x44pt targets via `.contentShape` and padding.
- `sensoryFeedback` as a parallel channel only; timer-done pairs haptic with sound and a visual flash.
- `@AccessibilityFocusState` to move the cursor to the new heading after navigation, sheet or error.
- `AccessibilityNotification.Announcement("Plan updated: 5 dinners").post()` on async results.
- Modals dismissible with the VoiceOver escape gesture.

## 3. Disability-specific needs

Blind and low vision (study of 20 cooks, https://arxiv.org/html/2407.19065): recipes lean on visual cues ("golden brown"); steps too long; hands are wet so touch-only is impractical; voice-only loses the user's place. Cooking mode: one action per step, short summary first, non-visual doneness cues, large type, voice and button navigation that keeps place, multiple named timers with sound + haptic + visual, screen kept awake.

Motor: single-tap alternative for every drag (WCAG 2.5.7), no long-press-only actions, no precise reorder, dictation in standard fields, primary actions at the bottom.

Cognitive, ADHD, executive dysfunction (evidence thin; design rules are inference): a "Pick for me" single primary action, at most 3 options, defaults pre-filled, few short steps, no time pressure, unmade meals roll over silently with no red "failed" state, Simple mode mapped to Assistive Access.

Dyslexia: no dyslexia typeface has reliable evidence (https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5629233/); spacing evidence is stronger. System font, left-aligned, generous spacing, never justified; optional spacing control.

Deaf and hard of hearing: every audible cue gets a visual and haptic twin (full-screen flash, Live Activity timer).

Colourblindness: pair every status colour with an icon or word.

Older adults: larger default text, lower density, plain language, Bold Text and Button Shapes support.

Eating-disorder safety: calorie-tracker users reported higher restraint (Simpson and Mazzeo 2017); 73% of tracker users with eating disorders felt the app contributed (Levinson et al. 2017); red/green budget visuals drive reward and shame (BJPsych Open qualitative). Numbers opt-in, no weight goals, no daily budgets, no good/bad/clean/cheat language, no red/green scoring, variety and balance framing, a "numbers off" switch reachable without disclosing why.

Diabetes: people with type 1 err by about 21 g (71%) estimating carbs (https://pubmed.ncbi.nlm.nih.gov/39058316/); apps range 13-21 g mean absolute error (https://pubmed.ncbi.nlm.nih.gov/41424217/). Label carbs as estimates with a range; no insulin advice; consult-a-doctor reminder (guideline 1.4.1); never write non-user data to HealthKit.

Chewing and swallowing: IDDSI levels 0-7 are CC BY-SA 4.0 with derivative works not permitted (https://iddsi.org/framework). Model IDDSI level as a clinician-set constraint; never infer texture from a recipe; v1 informational only.

Allergies: US 9 major allergens (sesame since 2023), EU 14 (Regulation 1169/2011); "may contain" is unstandardised. Per ingredient: contains / may contain / unknown / verified free; "unknown" is never shown as safe; constraint severity intolerance / allergy / anaphylaxis; show match reasons ("Excluded: contains sesame (tahini)"); "Check the label on every product." Never let an LLM decide allergen safety; compute deterministically with provenance.

## 4. WCAG 2.2 criteria that matter on mobile (https://www.w3.org/TR/wcag2mobile-22/)

2.5.8 Target Size (use Apple's stricter 44pt), 1.4.11 Non-text Contrast 3:1, 3.3.7 Redundant Entry (carry restrictions forward, never re-ask), 2.4.11 Focus Not Obscured (sticky bars must not cover focused controls), 2.5.7 Dragging Movements, 3.3.8 Accessible Authentication (passkeys / Sign in with Apple), 1.4.10 Reflow and 1.4.4 Resize Text (Dynamic Type to AX5), 1.4.1 Use of Color, 2.2.1 Timing Adjustable, 2.5.4 Motion Actuation.

Recommendation: WCAG 2.2 AA as the written bar, Apple's criteria as the release gate, stricter wins.

## 5. Inclusive data modelling and privacy

Five separate constraint axes, never one "diet" enum: medical/safety (allergy, intolerance, coeliac, diabetes, IDDSI, renal; hard, with severity), religious (hard, user-defined strictness), ethical (hard or soft), preference (soft, no explanation needed), goals (soft, never weight loss by default). Each stores strictness, source (user or clinician) and last-confirmed date. Never infer a condition from a preference; never ask why.

Onboarding: never ask about disability; detect system settings and adapt silently; a skippable "Make Larder easier to use" screen (bigger text, simpler layout, voice, timers with sound and flash, numbers off); prompts phrased "What should we always leave out?" and "Anything we should be careful with?" with "Prefer not to say"; everything changeable later.

Privacy: health and religious data are GDPR Article 9 sensitive; Washington My Health My Data Act reaches inferences (https://www.manatt.com/washingtons-my-health-my-data-act-what-to-know). Apple: HealthKit data never for advertising or mining (5.1.3), no false HealthKit writes, no personal health information in iCloud (5.1.3(ii); ask App Review before CloudKit-syncing an allergy profile), in-app account deletion (5.1.1(v)). HealthKit hides denied reads (empty looks like no data). Process on device by default; keep medical and religious fields out of analytics and out of any cloud LLM prompt.

## Deliverable (a): v1 acceptance checklist

MUST: 1 every interactive element labelled with role and state (manual VoiceOver run of all primary flows); 2 `performAccessibilityAudit()` passes in CI; 3 Voice Control "Show names" matches visible text; 4 usable at AX5 with no overlap or lossy truncation; 5 contrast 4.5:1 text and 3:1 controls in all modes; 6 no meaning by colour alone; 7 Reduced Motion removes parallax, zoom, spinning; 8 every drag or swipe has a tap alternative; 9 44x44pt targets; 10 allergen engine never shows unknown as safe and shows reasons (unit tests); 11 calories and weight goals off by default, no good/bad wording; 12 focus moves to the new heading and async results are announced; 13 all sound cues have visual and haptic twins.

SHOULD: 14 cooking mode as specified; 15 rotors for days and steps; 16 "Pick for me" primary action with at most 3 choices; 17 Assistive Access scene; 18 Nutrition Labels only for tested features; 19 dictation for pantry; 20 Accessibility Reader-friendly structure; 21 food photos opt out of Smart Invert.

LATER: 22 IDDSI display with clinician workflow; 23 non-visual doneness database; 24 Live Activity timers; 25 carb ranges with uncertainty; 26 study with blind, low-vision and ADHD users.

## Deliverable (b): eight SwiftUI pitfalls and fixes

1. Fixed font sizes and `lineLimit(1)`: use text styles and `@ScaledMetric`, allow wrapping.
2. Unlabelled icon-only buttons and images: `.accessibilityLabel`; `.accessibilityHidden(true)` for decoration.
3. Voice Control label differs from visible text: include visible words, add `accessibilityInputLabels`.
4. Custom controls from raw gestures: real `Button`/`Toggle`/`Stepper` or `accessibilityRepresentation`.
5. Drag-only reorder or swipe-only delete: `accessibilityActions`, Move Up/Down, Edit mode.
6. Colour-only status: icon and text, read `accessibilityDifferentiateWithoutColor`.
7. Text over Liquid Glass or images: solid backing, test under Reduce Transparency and Increase Contrast.
8. VoiceOver focus left behind: `@AccessibilityFocusState` and `AccessibilityNotification.Announcement`.
