# Larder research 06: UI/UX audit

Audited 2026-10-17 against commit `51e43d9`. Read-only review: no source files were changed.

**Method.** I read `docs/BLUEPRINT.md`, `docs/STATUS.md`, research 01/02/03, opened all 12 screenshots in `docs/screenshots/`, and read every view in `App/Larder`, `Sources/LarderDesign`, `Sources/FeatureAccount`, `FeatureLedger`, `FeatureShelves`, `FeatureRecipes`, `FeatureGrocery`, plus `App/LarderUITests` and `App/LarderWidgets`.

**Limits.** I did not run the app. Onboarding, paywall, settings, recipe detail, cooking mode, quick add, import, the meal sheet and every error state have **no screenshot**, so those findings come from code reading and are labelled "code". Screenshot findings cite the file name. The screenshots use UI-test fixtures (seeded shelves, a saved profile), so they show the app at its best; a real first launch lands on empty states.

Reference apps compared: Apple Reminders / Notes / Health / Fitness (structure and native controls), Mela, Crouton, Paprika (recipe library, photos, cooking mode), Mealime and Yummly (onboarding and plan), Things 3 (restraint, empty states, haptics), Structured (day timeline), Apple's iOS 26 Liquid Glass guidance.

---

## 1. Executive summary

The owner's three complaints are all confirmed. The root cause is one decision applied everywhere: the "pantry ledger" metaphor was implemented as a **custom, mostly flat, text-only component set** (hairlines, mono stamps, outlined rectangles) layered over SwiftUI with very few native iOS patterns. The result reads as a styled prototype, not a polished iOS 26 app. Specifics below.

### Top 10 problems, ranked by user impact

1. **First run is a seven-step questionnaire with no value proposition.** A `welcome` step exists (`OnboardingFlow.swift:77-89`) but it is three plain sentences, a medical disclaimer and an AI-consent switch under a 22 pt heading and a "1 of 7" stamp. No logo, hero, illustration, product preview, or promise of time to value. Then six dense forms (allergens, diets, medical conditions, goal, household, cook time, birth year, equipment, four accessibility toggles). A new user is asked for medical and religious data before seeing anything useful. (Complaint 1.)
2. **"Skip" silently wipes the answers on the current step, including allergens.** `OnboardingModel.skip()` calls `resetAnswers(for:)` (`OnboardingModel.swift:118-126, 210-239`). A user who ticks "Peanuts" and then taps Skip instead of Next loses the allergen. This is a safety defect, and the Skip button sits next to Next in the footer (`OnboardingFlow.swift:217-225`).
3. **After onboarding the user lands in a dead empty app.** Tonight shows "Nothing on the shelves" with a button that merely switches tab to Shelves (`RootView.swift:73-75`), which shows another empty state, whose button opens a sheet, whose first action is a free-text field and a button called **"Parse"**. Four taps and a jargon word before any value. There is no sample data, no "start with a sample week", no recipe-first path. Barcode, photo and receipt entry exist as engines but have **no UI at all** (`docs/STATUS.md` open item 5), although `INFOPLIST_KEY_NSCameraUsageDescription` promises scanning (`project.yml`).
4. **Visual design looks like a prototype, not a top-ranked app.** No imagery anywhere (zero `Image`/photo code outside SF Symbols; `Recipe` has no image field, `Recipe.swift:5-14`), recipe rows are text lines, hairline-only cards almost vanish on the cream canvas (`tonight-light.png`), controls are three different shapes (8 pt rectangle buttons, capsule FABs, glass circle toolbar buttons), and the mono "stamp" is used for every kind of metadata so nothing has hierarchy. No app icon exists in the repo (no `AppIcon`, no app `.xcassets`), and the launch screen is a blank auto-generated one (`project.yml`: `UILaunchScreen_Generation`). (Complaint 2.)
5. **Navigation vocabulary is internal jargon.** Tabs are "Tonight / Ledger / Shelves / Recipes / Grocery". "Ledger" (the week plan) and "Shelves" (pantry) are metaphor words, not tasks; "Eat first", "Let it go", "Eat it", "Parse", "Replan", "Why this week?", "Pick for me", "Shelf balance" all need explaining and none is explained. Nothing on any screen says what the screen is for. (Complaint 3.)
6. **Primary actions do not do what their labels say.** "Cook this" on Tonight does not start cooking; it writes the recipe into today's dinner slot and disables itself (`TonightModel.cookTonight`, `TonightView.swift:138-140`). "Add to Ledger" on recipe detail always replaces **today's** dinner, offers no day choice, and jumps to another tab (`RootView.swift:154-165`, `AppDependencies.swift:276-287`). "Pick for me" re-highlights one of the three cards already on screen (`TonightView.swift:80-85`). "Finish" in cooking mode just closes the cover. (Complaint 3.)
7. **Screens are inconsistent in structure, so the app feels unfinished.** Tonight and Ledger draw a Fraunces `largeTitle` as scroll content (`TonightView.swift:26-29`, `LedgerView.swift:112-115`) with an empty nav bar above; Shelves, Recipes and Grocery use native `.navigationTitle` in SF bold (all three screenshots). The Settings gear exists on Tonight, Ledger and Shelves but not on Recipes or Grocery (`RootView.swift:71-97`). The gear is labelled "Account" and opens "Settings" (`Copy.Tab.account`). The floating action button is centred on Ledger and Shelves and right-aligned on Recipes, and covers list text on all three (`shelves-light.png`, `recipes-light.png`).
8. **Several flows are dead ends or missing basic edit/delete.** Shelf items cannot be edited or tapped (`ShelfRow.swift` has no tap action; only swipe/context menu), and "Eat it" removes the whole quantity. Hand-written grocery items cannot be deleted from the UI (`GroceryModel.removeManual` exists, `GroceryView` never calls it). Recipe import failure says "You can paste the recipe in yourself" but no paste-text path exists (`RecipesCopy.swift` `.noStructuredRecipe`, `ImportModel` has only a URL). Quantities are stored and shown in grams only, so eggs read "300 G" (`ShelvesCopy.quantity(grams:)`).
9. **Settings that do nothing, and promises not kept.** "Simpler layout" is saved but no view reads it (grep shows only `SettingsModel`, `OnboardingModel`, `TrialWeekGate`). "Timers flash and vibrate" is implemented only as an in-app flash plus one `.success` haptic (`CookingModeView.swift:45`) and there are no local notifications, so a timer finishing in the background is silent. Marking a meal cooked does not subtract from the shelves (`LedgerModel.markCooked`, `:331`), which breaks the app's own "pantry ledger" loop. HealthKit usage strings exist but nothing writes to Health.
10. **Recipe browsing and cooking lack the table stakes of Mela/Crouton/Paprika.** No photos, no favourites, no collections, no sort, no "have / missing ingredients" on the detail, no add-ingredients-to-grocery, no checkable ingredients or steps, no step progress bar, no ingredient peek in cooking mode, a single flat filter strip mixing meal type, diet, time and cuisine (about 20 chips, `FilterChips.swift:10-31`), and redundant tags ("Vegan · Vegetarian").

---

## 2. Per-screen findings

Severity: **S1** blocks or misleads, **S2** clearly hurts, **S3** polish. "Shot" = screenshot name in `docs/screenshots/`.

### 2.1 App shell, launch and first run

| # | Sev | Issue | Evidence | Fix |
|---|---|---|---|---|
| 1 | S1 | No app icon or branded launch. App has no `.xcassets` (only `Sources/LarderDesign/Resources/Colors.xcassets`) and `UILaunchScreen_Generation: YES`. On a real device the first frame is a blank screen and a placeholder icon. | `project.yml` settings; `find . -name AppIcon*` empty | Add `App/Larder/Resources/Assets.xcassets` with an Icon Composer `.icon` (iOS 26) and an `AccentColor` set equal to `accent.brand`. Add a launch screen colour set `surface.canvas` plus the wordmark. |
| 2 | S2 | `hasProfile == nil` shows a bare `ProgressView` on white. | `RootView.swift:56-58` | Show the canvas colour and wordmark, no spinner, for the (very short) read. |
| 3 | S2 | Startup failure is the only global error and it says "Close Larder and open it again", which is not an actionable fix. | `RootView.swift:169-177` | Add a "Try again" button that re-runs `dependencies.start()`; keep "Close and reopen" as the fallback line. |
| 4 | S2 | Five tabs with metaphor names. Icons: `sun.horizon`, `list.bullet.rectangle` (reads as an invoice, not a week plan), `cabinet`, `book`, `basket`. | `RootView.swift:71-97`; all shots | Rename to task words (see section 5 P0-4): Tonight, Plan (or Week), Pantry, Recipes, Shopping (or Groceries). Use `calendar` for Plan, `refrigerator` or `cabinet` for Pantry, `checklist` or `cart` for Shopping. |
| 5 | S2 | The tab bar is the system Liquid Glass bar, but content scrolls under it with visible ghost text (see "hicken and potatoes" in `tonight-light.png`, `ledger-planned-dark.png`). No scroll edge effect is applied. | all tab shots | On iOS 26 add `.scrollEdgeEffectStyle(.soft, for: .bottom)` on scroll views and bottom padding; set `tabBarMinimizeBehavior(.onScrollDown)` so the bar gets out of the way on long lists. |
| 6 | S3 | Orientation locked to portrait on iPhone; iPad is declared (`TARGETED_DEVICE_FAMILY "1,2"`) but every screen is a single phone column. | `project.yml` | Either drop iPad for v1 or add `NavigationSplitView`/sidebar adaptable `TabView` (`.tabViewStyle(.sidebarAdaptable)`). |

### 2.2 Onboarding (no screenshot; code)

Flow: `welcome` -> `leaveOut` -> `eatBy` -> `goal` -> `household` -> `equipment` -> `easierToUse`, one custom `ScrollView` plus footer (`OnboardingFlow.swift:19-37`).

| # | Sev | Issue | Evidence | Fix |
|---|---|---|---|---|
| 1 | S1 | Welcome screen is not a welcome. Title is `SectionHeading` (22 pt), body is three plain sentences, then the medical disclaimer and the AI-consent toggle. No brand, picture, benefit headline, or "how it works". | `OnboardingFlow.swift:77-89`, `AccountCopy.swift:23-37` | Replace with a real intro (section 5 P0-1): full-height canvas, wordmark, one-line promise ("Dinner sorted from what's already in your kitchen"), a 3-card swipeable "how it works" (Add what you have / Get tonight's ideas / Shop once), one big "Get started" button and a quiet "I already have an account" only if relevant. Move the disclaimer to the Health step and the AI toggle to its own step later (or default to the system-prompted flow at first AI use). |
| 2 | S1 | Skip clears the step (allergens, diets, medical, goal, household, equipment). Footer shows Back, Skip and Next together. | `OnboardingModel.swift:118-126, 210-239`; `OnboardingFlow.swift:208-228` | Never reset on skip; skip must keep existing selections or be hidden when selections exist. Better: remove per-step Skip, make every question optional with a primary "Continue" that works with nothing selected, and a single "Set up later" at the top trailing edge. |
| 3 | S1 | Seven steps before value, with the heaviest data (medical flags, religion, birth year) first. Research 01 itself cites onboarding-heavy PlateJoy as a failure pattern (`01-users-market-ux.md:42`). | `OnboardingModel.Step` | Cut to a 3-step minimum: (1) "Anything you can't eat?" (allergens + diets in one grouped screen), (2) "How many are you cooking for?" (stepper), (3) done. Everything else (goal, equipment, cook time, birth year, accessibility toggles, conditions) moves to a "Finish setting up" card on Tonight and to Settings, asked in context. |
| 4 | S2 | Custom checkbox list (`square` / `checkmark.square.fill` / `largecircle.fill.circle`) is macOS-like and only shows 4 of 15 allergens until "Show all 15" is tapped. Safety-critical choices are hidden by default. | `ChoiceList.swift:11, 20-25, 51-57` | Use native `List` with `.insetGrouped`, `Toggle` rows or tappable rows with trailing checkmark; show all allergens (they are a short, known list) grouped "Most common" / "Other". Keep search for diets. |
| 5 | S2 | Progress is a mono stamp "1 OF 7" in the scroll content; no progress bar; headings are 22 pt. No large display type, so the screens look like settings forms. | `OnboardingFlow.swift:23-26` | Use a thin top `ProgressView(value:)`, `largeTitle` Fraunces question headings, and generous spacing; one question per screen, one control group. |
| 6 | S2 | Jargon and unexplained asks: "Anything we eat by?" (diet), "Anything we should be careful with?" (medical), "What matters most?" (goal), "Year you were born" with "Used only for nutrient ranges" on the Household step. | `AccountCopy.swift:41-52` | Plain questions: "Do you follow a diet?", "Any health conditions we should plan around?" (optional, with disclaimer), "Birth year" only inside Settings > Nutrition. Explain why each question is asked in one line under the title. |
| 7 | S2 | Accessibility step is a generic list of toggles plus a non-interactive "Larger text" info row; includes "Show numbers" (nutrition) under "Make Larder easier to use". | `OnboardingFlow.swift:180-199` | Drop from onboarding. Move to Settings > Accessibility; link to iOS Settings for text size. |
| 8 | S2 | The AI-consent toggle is on the first screen, on the same page as the disclaimer, defaulting off with a 60-word paragraph. | `AccountCopy.swift:31-37` | Ask in context at the first AI feature with a standard sheet (title, 2 bullets, Allow / Not now). Keep the default off. |
| 9 | S3 | Footer buttons: secondary rectangle, quiet text, primary rectangle, laid out in a bar on `surface.raised`. Standard iOS onboarding uses one full-width capsule `Continue` with a text link below. | `OnboardingFlow.swift:201-229` | Single full-width prominent button (`.buttonStyle(.glassProminent)` or Larder primary) + quiet "Back" in the nav bar. |

### 2.3 Tonight (shots: `tonight-light`, `tonight-dark`; empty state is code)

| # | Sev | Issue | Evidence | Fix |
|---|---|---|---|---|
| 1 | S1 | "Cook this" does not cook. It schedules the recipe as today's dinner and then the button greys out with no replacement action. To actually cook the user must go "See recipe" -> sheet -> "Start cooking". | `TonightView.swift:57-63, 137-143`; `TonightModel.swift:83-97` | Rename to "Make this tonight" (adds to plan) and, once added, replace the button with "Start cooking" that opens cooking mode directly. Keep "See recipe" as a tap on the whole card. |
| 2 | S1 | Empty state button "Add what you have" only switches the tab (`onAddToPantry` -> `state.selectedTab = .shelves`), landing on a second empty state. | `RootView.swift:73-75`; `TonightView.swift:47-51` | Open the Add sheet directly (shared sheet presented from the root), or offer "Browse recipes" as an alternative path. Add a second action, "See what people cook" (seed recipes), so the first-run user is never forced to type a pantry. |
| 3 | S2 | "Pick for me" is a full-width primary button above three suggestions that already exist. It only highlights one of them. It looks like the screen's main action but adds almost nothing. | `TonightView.swift:57-63, 80-85`; `LedgerCopy.pickedAnnouncement` | Remove, or turn into "Surprise me" that reshuffles to three new ideas (a real second action). Make "Make this tonight" the only filled button per card. |
| 4 | S2 | Cards are flat `surface.raised` (#FFFDF7) on `canvas` (#F5F1E6) with hairline only at top and bottom and 12 pt radius, so they barely separate. Inside, a 600-weight title, a boxed "35 MIN" stamp, two verdigris-barred reason lines and two buttons all share similar visual weight. | `tonight-light.png`; `PaperCard.swift:25-33` | Add the recipe photo (or a tinted placeholder) at top, put time as an SF-symbol caption ("clock 35 min"), reduce to one reason line with a pantry-use summary, one filled button. Use a stronger card fill/line or system `.regularMaterial`-free grouped background. |
| 5 | S2 | Reason copy is vague: "Uses 4 things you have" without naming them. | `tonight-light.png` | Name two items ("Uses spinach, lentils and 2 more") and mark the "use soon" ingredient with the freshness icon. |
| 6 | S2 | Title is content, not nav title; nav bar is empty except the gear in a glass circle; the page has 120 pt of dead space above the content. | `TonightView.swift:26-29`; `tonight-light.png` | Use `.navigationTitle` with `.navigationBarTitleDisplayMode(.large)` and `.toolbar` for the gear; apply the Fraunces display via `UINavigationBarAppearance`/`.toolbarTitleDisplayMode` or accept SF for titles (see 3.5). Keep one approach on all tabs. |
| 7 | S3 | There is no sense of "today": no date, greeting or time of day, even though the research frames 5pm rescue as the primary entry point. | `01-users-market-ux`, `BLUEPRINT.md` section 1 | Under the title show the date and the household size; if tonight's dinner is already set, show it as a hero card ("Tonight: Spinach red lentil dal") with "Start cooking" and "Change". |
| 8 | S3 | `isPicked` outlines the card with 2 pt brand stroke, `isCooking` shows "On for tonight" stamp; both depend on stamps and colour. | `TonightView.swift:108-133` | Use a filled "checkmark.circle" label plus text for "On for tonight". |

### 2.4 Ledger (shots: `ledger-*`, `ledger-planned-*`; meal sheet is code)

| # | Sev | Issue | Evidence | Fix |
|---|---|---|---|---|
| 1 | S1 | Name "Ledger" tells the user nothing; the empty state's primary action floats at the bottom, a long way from the explanation, with a decorative shelf-and-jar drawing that has nothing to do with calendars. | `ledger-light.png`; `LedgerView.swift:60-67, 129-131` | Tab title "Plan". Empty state: calendar illustration, "Plan your week", one line of value, and the **Plan my week** button inside the empty state (centred), with "Or add dinners yourself" as secondary. |
| 2 | S2 | Day rows: left tab, mono date, a content-hugging "jar label" whose width follows the title, so labels are ragged, today's is solid paprika with white text, other days are outlined boxes, leftovers are rotated mustard strips. Tap target and affordance are unclear (no chevron, no photo). | `ledger-planned-light.png`; `JarLabel.swift:40-58`; `TapeLabel.swift:27` | Standard row: leading 56 pt thumbnail, title (headline), subtitle "Dinner, 35 min", trailing chevron or menu; full width. Today = a highlighted day header, not a filled label. Leftover = a small `arrow.2.squarepath` badge plus text "Leftovers, day 2 of 4". Remove the -1 degree rotation: it reads as a rendering bug. |
| 3 | S2 | Swipe actions (Mark cooked / Skip / Swap) apply only to `day.meals.first`; the row has no visible hint that it swipes. Meal-sheet duplicates the same actions as five stacked secondary buttons plus a Picker. | `LedgerView.swift:187-200`; `MealSheet.swift:90-121` | One consistent action model: context menu + swipe + a compact toolbar `Menu` in the meal sheet. Show swipe hint once via a first-use tip (`TipKit`). In the sheet, lead with "Swap" and "Mark as cooked", put Lock/Move/Skip in a "More" menu. |
| 4 | S2 | "Replan" is a bare nav-bar button that regenerates the whole week with no confirmation or undo. Locked meals are preserved but this is invisible. | `LedgerView.swift:51-58`; `LedgerModel.replan` | Confirmation sheet ("Replan the week? Locked meals stay.") and an undo snackbar; show a lock glyph on locked rows. |
| 5 | S2 | "Why this week?" is a verdigris text button with 12 pt indent that does not align with the title, and it triggers an AI explanation call (consent-gated) with no indication of cost or connectivity. | `ledger-planned-light.png`; `LedgerView.swift:132-142` | Make it a visible `DisclosureGroup`/button with an info icon, left-aligned with the title, and show per-meal reasons by default (they are local reason codes). Only the "summary" needs AI. |
| 6 | S2 | Only dinner is ever planned (`Self.plannedSlots`), but the UI repeats the word "Dinner" on every row and shows "Nothing fits here yet" for open slots. No way to add a snack or a breakfast. | `LedgerView.swift:181-183`; `OpenSlotLabel` (`:270-296`) | If dinner-only for v1, drop the slot word and the open-slot concept; offer "Add a meal" per day. |
| 7 | S2 | Shelf balance card is a long bar-chart-like card at the end of a 7-day list, titled "This week's shelf" (a pun on pantry shelves); the dotted bracket legend is never explained. Under Plus it is also paywalled by the same word. | `ShelfBalanceCard.swift:15`; `ShelfBand.swift:45-77` | Title "Nutrition balance"; add a one-line legend ("Dotted bracket = a comfortable range"); place near the top as a collapsible summary, not at the bottom. |
| 8 | S3 | The "ledger" metaphor leaks: stamps for dates (`SAT, 17 OCT` in mono caps), `TODAY` in paprika mono. Mono uppercase at caption size is hard to scan and runs against Dynamic Type. | `LedgerRow.swift:25-34`; shot | Use `Text(date, format: .dateTime.weekday(.wide).day())` in `.headline`; reserve mono for numbers. |
| 9 | S3 | Meal sheet (code): title is a 22 pt `SectionHeading`, three stamps (slot, minutes, status), then "See recipe" as a quiet link, reasons, then a stack of 4 outlined buttons and a Picker. It is a settings list in sheet form. | `MealSheet.swift:58-123` | Detents `.medium/.large`, drag indicator, hero image, primary "Start cooking", then a grouped `List` of actions. |

### 2.5 Shelves / pantry (shots: `shelves-light`, `shelves-dark`; add sheet is code)

| # | Sev | Issue | Evidence | Fix |
|---|---|---|---|---|
| 1 | S1 | Name "Shelves" (pantry) and "Eat first" are metaphors; nothing explains that this list drives Tonight and the grocery list. | `ShelvesView.swift:20`; `shelves-light.png` | Rename "Pantry". Add a one-line header card on first visit ("Tonight's ideas use what's here"). |
| 2 | S1 | Items are read-only: `ShelfRow` has no tap action, so quantity, date and location cannot be corrected. Swipe "Eat it" removes the whole item; there is no partial use. | `ShelfRow.swift:22-50` | Tap opens an item sheet (name, amount + unit, location, best-by, notes) with Delete; swipe actions: "Used up" (full), "Use some" (stepper), "Throw away" with Undo (already present, keep). |
| 3 | S1 | Quantities display in grams for everything (`ShelvesCopy.quantity(grams:)`), e.g. "Eggs 300 G". Piece-based items (eggs, onions) and volume (milk) are wrong in the primary list. | `shelves-light.png`; `ShelfRow.swift:12` | Store and show the user's unit (the draft editor already has units, `DraftLineEditor.swift:56-63`); show "6 eggs" not "300 G". |
| 4 | S2 | The same item appears twice: Spinach is both in the "Eat first" card and under Fridge. | `shelves-light.png` | Show Eat first as a highlighted section **instead of** duplicating; or keep in-list with a badge. |
| 5 | S2 | Every row carries two bordered mono boxes (quantity + freshness). "Fresh 23 OCT" on healthy items is noise; the right edge of the stamps is ragged between rows; rows are 80 pt tall because of default List insets plus padding. | `shelves-light.png`; `FreshnessStamp.swift`; `ShelfRow.swift:22-29` | One line: name (headline), subtitle "300 g . Fridge", trailing a coloured dot/word only for use soon / today / past. Hide freshness for Fresh. Target 52-60 pt rows. Section headers as native `Section` headers. |
| 6 | S2 | Section headers are 22 pt Fraunces rows inside the list (`SectionHeading` as a row) while the large title is SF Bold: two display faces in one screen. | `ShelvesView.swift:85-93`; `shelves-light.png` | One display strategy (3.5); use real `Section` headers. |
| 7 | S2 | FAB "Add what you have" is centred, overlays the Garlic row text with no backing, and sits above the tab bar so there are two floating pills stacked. | `shelves-light.png`; `FloatingAction.swift`; `ShelvesView.swift:134-147` | Use a toolbar `+` (primary action) plus a bottom-aligned search; on iOS 26 use a `ToolbarItem(.bottomBar)` glass button or `.toolbar { ToolbarSpacer }`; remove the capsule over content. |
| 8 | S2 | No search, no sort, no filter; no scan button. Barcode, photo and receipt engines exist (`BarcodeReader`, `ReceiptToPantry`) with no UI; the camera usage string promises it. | `STATUS.md` item 5; `project.yml` | Add `.searchable`, and a "+" menu: Type it, Scan barcode, Scan receipt, Choose from list. Build `DataScannerViewController` wrapper (STATUS item 5). |
| 9 | S2 | Quick add sheet: a `Form` with a text field, a primary button called "Parse", then draft editors with six controls per line (name, qty, unit, location, "Best by" toggle + date picker), three buttons in the last section ("Add a line by hand", "Add N items", "Not now"). | `QuickAddSheet.swift:38-95`, `DraftLineEditor.swift:27-46` | Name it "Add food". Single text field with placeholder "2 onions, a bag of rice, milk" and a keyboard-accessory "Add"; parse on submit; show results as compact editable rows with unit and location chips; one primary "Add 3 items" in the toolbar `confirmationAction`. Default best-by from shelf-life data instead of asking per line. Never use the word "Parse". |
| 10 | S3 | Row accessibility is excellent, but the swipe "Eat it" / "Let it go" labels are the only way to remove; discoverability is nil without a first-run tip. | `ShelfRow.swift:34-48` | TipKit tip on the first row; add the actions to the item sheet. |
| 11 | S3 | The best-by year is not shown (`13 AUG`, `23 OCT`); dates years apart read the same. In the screenshot "Fresh 13 AUG" next to a 17 Oct "today" reads as an expired item. | `shelves-light.png`; `FreshnessStamp.swift:16-18` | Use relative text ("in 6 days", "Aug 2027") for far dates. |

### 2.6 Recipes (shots: `recipes-light`, `recipes-dark`; detail, import and cooking are code)

| # | Sev | Issue | Evidence | Fix |
|---|---|---|---|---|
| 1 | S1 | No images. Recipes are a text list ("Avocado chickpea toast / 10 MIN / American . Vegan . Vegetarian"). Imported recipes ignore `image` in JSON-LD (no model field). This is the single biggest gap versus Mela, Crouton and Paprika. | `recipes-light.png`; `Recipe.swift:5-14`; `JSONLDRecipeParser.swift` | Add `imageURL`/`imageData` to `Recipe` (JSON-LD `image`), use Nuke (already a blueprint decision) for caching, show 64 pt thumbnails in rows and a 16:9 hero in detail; for seed recipes without photos use a coloured tile with an SF Symbol or a food-group illustration so the list has rhythm. |
| 2 | S2 | Large dead band above "Recipes" title (about 110 pt) because the nav bar has no items; the search field is not in the nav bar. | `recipes-light.png` | Use `.searchable(placement: .navigationBarDrawer(displayMode: .automatic))` or the iOS 26 bottom search (`.searchToolbarBehavior(.minimize)` in a bottom-bar `DefaultToolbarItem(kind: .search)`); add toolbar items (Import, sort) so the bar earns its space. |
| 3 | S2 | One horizontal chip strip mixes four categories (meal type, 5 diets, "30 min or less", ~10 cuisines) in a single scroll row. First 5 chips are all meal types; the user can't tell filters exist beyond the fold (cut off "Vegeta"). Chips are 44 pt tall, 8 pt radius with a heavy border. | `FilterChips.swift:10-31, 51-60`; `recipes-light.png` | Single "Filters" button in the toolbar opening a sheet with grouped sections, plus up to 4 quick chips (Dinner, Under 30 min, Vegetarian, Favourites). Chips should be capsule, 32-36 pt visual with a 44 pt hit area. |
| 4 | S2 | Row subtitle repeats tags ("Vegan . Vegetarian") and omits the one thing a cook wants: does Larder have the ingredients? No "You have 6 of 8", no rating, no favourite. | `RecipeRow.swift:13-16` | Show "Have 6 of 8" in `status.success` text with icon, and a heart for favourites; dedupe diets (vegan implies vegetarian). |
| 5 | S2 | Library is alphabetical only; no sections, favourites, recents or collections. | `RecipesView.swift:81-89` | Add a segmented control (All / Favourites / Imported), sort menu (Name / Time / Recently cooked), alphabetical index. |
| 6 | S2 | FAB "Import a recipe" is right-aligned here (centred on other tabs) and covers "Chicken shawarma pitas". Import is URL-only. | `recipes-light.png`; `RecipesView.swift:33-41`; `ImportSheet.swift:53-86` | Toolbar `+` menu: "From a web page", "Paste text", "Scan or photo", "Write your own". Support the iOS Share Sheet extension (Share > Larder) so the user never copies URLs. |
| 7 | S2 | Detail (code): 34 pt Fraunces title in the scroll content, two stamps, a Stepper, plain text ingredient lines (no checkboxes, no pantry status), method as numbered mono text, then "Start cooking" and "Add to Ledger" **below the ingredients and only after loading finishes**; the primary action is off-screen on iPhone. | `RecipeDetailView.swift:33-72, 116-149` | Sticky bottom bar with "Start cooking" (primary) and a `Menu` (Add to plan, Add missing to grocery, Favourite, Delete). Ingredient rows with leading have/missing icon; "Add 3 missing to Shopping" button. Hero photo, source link and time chips under title. |
| 8 | S2 | "Add to Ledger" always replaces today's dinner and switches tab; no date choice. | `RecipeDetailView.swift:140-147`; `RootView.swift:154-165`; `AppDependencies.swift:276-287` | Open a day picker (this week's days with existing meals shown), confirm with a toast "Added to Wednesday" and stay on the recipe. |
| 9 | S2 | Import failures: `.noStructuredRecipe` says "You can paste the recipe in yourself" but there is no paste field; "Larder Plus can read pages without structured data" appears as an error message, i.e., an upsell inside a failure. | `RecipesCopy.swift` `message(for: ImportError)`; `ImportSheet.swift` | Add a "Paste the recipe text" editor on failure; put the Plus offer as a separate secondary card. |
| 10 | S3 | Import preview is the whole recipe in the sheet (ingredients and every step), with Save at the bottom of a long scroll. | `ImportSheet.swift:21-24, 105-120` | Pin "Save recipe" in the bottom bar, collapse method to the first 3 steps. |
| 11 | S3 | Delete shows a confirmation dialog (good, `RecipeDetailView.swift:59-67`) but only for imports; for seed recipes the trash simply isn't there, with no explanation. | `:53-57` | Offer "Hide recipe" for seed recipes. |

### 2.7 Cooking mode (code only; **not screenshotted**)

| # | Sev | Issue | Evidence | Fix |
|---|---|---|---|---|
| 1 | S2 | One step per screen, large Back/Next, timers, wake lock. Good bones. Missing: step progress bar (only a mono "STEP 1 OF 6" at top-left and a text "Close" at top-right), ingredient list/peek, ability to check off ingredients, jump to step list, screen dimming. | `CookingModeView.swift:65-78, 94-105, 119-144` | Add a segmented progress capsule, an "Ingredients" bottom sheet (detents), and a step list menu. Replace the text "Close" with an `xmark` `ToolbarItem` and confirm on exit if timers are running. |
| 2 | S2 | Finishing does nothing but dismiss. It does not mark the meal cooked, offer to deduct ingredients from the pantry, ask for a rating, or celebrate. | `:136-137` | "Finish" -> completion sheet: "Mark as cooked", "Update your pantry" (list with quantities to subtract), and a stamped confirmation using the existing `LarderMotion.stamped` animation plus `.sensoryFeedback(.success)`. |
| 3 | S2 | No local notification when a timer ends while the app is backgrounded or locked (no `UNUserNotificationCenter` anywhere). "Timers flash and vibrate" is a promise the app cannot keep outside the foreground. | `grep UNUserNotification` returns nothing | Schedule a `UNNotificationRequest` per running timer; use Live Activity/Timer in a later release; haptic via `.sensoryFeedback(.warning)`. |
| 4 | S3 | Timers are manual; step text is plain; quantities inside the step text are not highlighted. | `TimerControl.swift`; `StepPage` | Detect times in steps and show a tappable "Start 10 min timer" chip; bold quantities. |
| 5 | S3 | Page style `TabView` plus Back/Next buttons duplicates gestures without a visible page indicator (`indexDisplayMode: .never`). | `:101` | Keep swipe, add the progress capsule. |

### 2.8 Grocery (shots: `grocery-light`, `grocery-dark`)

| # | Sev | Issue | Evidence | Fix |
|---|---|---|---|---|
| 1 | S1 | Empty state is a left-aligned line drawing (the same shelf-and-jar used for 3 different screens) at the top of an otherwise empty screen. Text: "Nothing to buy / Plan a week or add items by hand." with no button. | `grocery-light.png`; `GroceryView.swift:25-30` | Centre vertically; icon `cart`; actions "Plan a week" (switch tab) and focus the add field. |
| 2 | S1 | Hand-written items can't be deleted or edited (no swipe, no context menu); only checking then "Clear basket". Quantity is unsupported in the UI (`addManual(name:quantity:)` is never passed one). | `GroceryView.swift:19, 55-60`; `GroceryModel.removeManual` unused by view | Convert to a `List` with `.swipeActions` (Delete, Edit), allow "2 tins milk" parsing into a quantity. |
| 3 | S2 | Side effects are invisible: ticking a planned item silently puts it on the Pantry; unticking removes it (`GroceryModel.toggle`). The header never says so. "In the basket" and "Clear basket" are unexplained (a basket here means "bought"). | `GroceryModel.swift:196-226`; `GroceryCopy.swift` | Footer "Ticked items are added to your pantry" plus a toast with Undo; rename "In the basket" to "Bought" and "Clear basket" to "Remove bought items". |
| 4 | S2 | Planned items don't say which recipe/day needs them; no per-aisle count; no store-order controls; ShareLink is a bare icon in a glass circle with the label hidden; `ShareLink(item: model.shareText())` is disabled when nothing to buy. | `GroceryView.swift:42-47` | Subtitle "For Tuesday's dal"; header shows "12 items, 3 bought"; share as a text list and also Reminders export. |
| 5 | S3 | Add field placeholder is very faint on the sunken fill; "Add" button is an outlined 8 pt rectangle next to a text field, the only such pattern in the app. | `grocery-light.png`; `AddItemField.swift:15-31` | Use a native `.searchable`-style bottom text field or a keyboard toolbar; filled `Add` only when text exists. |
| 6 | S3 | No Settings gear on this tab (and on Recipes). | `RootView.swift:92-97` | Settings is an app-level entry; place it in one consistent place (profile button top-trailing on every tab root, or in a "You" tab). |

### 2.9 Settings / Account (code only; **not screenshotted**)

| # | Sev | Issue | Evidence | Fix |
|---|---|---|---|---|
| 1 | S2 | A custom `ScrollView` of `PaperCard`s in place of an `insetGrouped` `List`/`Form`: loses native row heights, section headers, chevron navigation, search-in-settings muscle memory. One screen holds profile, five constraint axes, Plus, data and about. | `SettingsView.swift:21-39, 250-277` | Rebuild as `Form`/`List(.insetGrouped)` with sections and navigation pushes: Profile, Food rules (Allergies, Diets, Faith, Dislikes), Assistant and privacy, Subscription, Data, About. |
| 2 | S2 | Entry point is an "Account" gear that opens "Settings"; there is no account. | `Copy.Tab.account`; `RootView.swift:136-138` | Label "Settings" with the gear, or a person icon labelled "Profile". |
| 3 | S2 | "Simpler layout" toggle is stored but unused; it and "Show numbers", "Allow AI help" (60-word hint) and "Timers" are in one "Profile" card with 5 other controls. | `SettingsView.swift:112-131`; grep shows no reader | Implement it (e.g., hide secondary stamps, single-column, larger rows) or remove it. |
| 4 | S2 | Plus status is a mono stamp "FREE" and a quiet link "See Larder Plus"; no benefit list, no indication of how many free weeks remain. | `SettingsView.swift:183-196` | A row with a leading gradient-free badge, "Larder Plus", subtitle "1 free week left", trailing chevron to the paywall. |
| 5 | S2 | "Delete all data" sits next to "Export everything" as the same outlined-button weight; a confirmation dialog exists (good). No link to Terms or Privacy in Settings (only in the paywall). | `SettingsView.swift:204-213, 60-71` | Destructive action as a red-text row at the bottom of its own "Danger zone" group; add Terms, Privacy, Support, Rate and "What's new". |
| 6 | S3 | Constraint removal uses a quiet "Remove" button per row plus a dialog; the safety copy is good. Add uses a `Menu` labelled "Add" that lists 21 items in one flat menu. | `SettingsView.swift:141-181` | Use a searchable multi-select sheet per axis. |

### 2.10 Paywall (code only; **not screenshotted**)

| # | Sev | Issue | Evidence | Fix |
|---|---|---|---|---|
| 1 | S2 | Native `SubscriptionStoreView` (good) with a custom header: 22 pt heading, a paragraph, then a `PaperCard` listing six full sentences. The bottom inset adds "Not now", "Restore purchases", the renewal sentence and two links, which stacks about 220 pt of chrome over the products on small phones. | `PaywallView.swift:43-65, 106-157` | Use `SubscriptionStoreView` marketing content with icon-led one-line benefits, a hero, and `.subscriptionStorePolicyDestination` for terms/privacy; keep "Not now" as an `xmark` in the corner (still equal weight in copy). |
| 2 | S2 | Legal URLs are placeholders (`larder.app/terms`, `larder.app/privacy`) and are labelled as such in a code comment. | `PaywallView.swift:6-10` | Must be real before submission. |
| 3 | S3 | Features are paragraphs, e.g. "Household profiles give each person their own swaps on one shared plate." | `AccountCopy.swift:76-81` | Six 6-8 word bullets with SF Symbols. |
| 4 | S3 | When prices fail to load the fallback shows `displayName` plus price as full-width primary buttons, one per product (same weight for monthly and annual). | `:77-93` | Highlight annual as "Best value" and show per-month price. |

### 2.11 Widget and Shortcuts (code)

The Today widget (`TodayWidget.swift`) is clean and consistent. "Nothing planned / Open Larder for three ideas." is a good fallback. Missing: tap target `widgetURL` deep link into Tonight, and a medium layout that shows three ideas (`TodayWidgetView` renders one layout for small and medium). App Intents exist (`WhatsForDinnerIntent`, `OpenTonightIntent`) with local strings that STATUS item 6 already flags.

---

## 3. Cross-cutting design-system findings (component by component)

### 3.1 Buttons: `Sources/LarderDesign/Components/LarderButtonStyle.swift`
- Three weights: filled 8 pt rectangle, outlined 8 pt rectangle, text. 8 pt rectangles are neither the iOS 26 capsule (`.glassProminent`, `.borderedProminent` with `.capsule`) nor the old rounded rect (10-14 pt). In the screenshots they sit next to capsule FABs and glass circles, so the app shows **four button shapes** (rectangle, capsule, circle glass, text).
- Primary press feedback is a 8% black overlay and opacity; no haptic. The app has exactly one `sensoryFeedback` call (`CookingModeView.swift:45`).
- The quiet button is verdigris text with no affordance; at rest it reads as a label ("See recipe" in `tonight-light.png`).
- **Fix.** Use native styles as the base: `.borderedProminent` + `.buttonBorderShape(.capsule)` + `.tint(brand)` for primary, `.bordered` for secondary, `.plain/.borderless` for quiet, `.glass` / `.glassProminent` on iOS 26 for floating controls. Keep Larder tokens through `tint` and `foregroundStyle`. Add `.sensoryFeedback(.impact(weight: .light), trigger:)` on primary taps and `.success` on saves.

### 3.2 Floating action: `FloatingAction.swift`
- An opaque brand capsule placed with `safeAreaInset(edge: .bottom)`. It stacks with the system tab bar, overlays content on every tab (`shelves-light.png`, `recipes-light.png`), and is aligned differently per tab (`ShelvesView.swift:134-147`, `RecipesView.swift:33-41`, `LedgerView.swift:60-67`).
- UI test code has to special-case it as an occluder (`LarderUITests.swift:175-177`), a sign it is fighting the system.
- **Fix.** Remove. Primary add actions move to the toolbar (`+`, `.primaryAction`) and empty states. If a persistent action is needed use iOS 26 `.tabViewBottomAccessory` (for the "On for tonight" mini-player: Start cooking) rather than an FAB.

### 3.3 Cards and rows: `PaperCard.swift`, `LedgerRow.swift`, `JarLabel.swift`, `TapeLabel.swift`
- `PaperCard` is hairline top/bottom plus a 12 pt clip; its contrast against `canvas` is below what most cards need (`#FFFDF7` on `#F5F1E6`); on dark it is `#20241E` on `#161915`. Cards inside lists (Shelves "Eat first") put rows inside a card, which then duplicate the same item below.
- `JarLabel` wraps content width, producing the ragged rectangles in `ledger-planned-light.png`. `TapeLabel` rotates -1 degree, which looks like a layout bug at a glance and defeats VoiceOver/UI-test frame checks.
- **Fix.** Replace with a single `ListRow` component (leading media, title, subtitle, accessory) and use `List(.insetGrouped)` where possible. Keep the paper identity through colour and type, not through bespoke containers. Remove the rotation.

### 3.4 Stamps: `Stamp.swift`, `FreshnessStamp.swift`, `LarderFont.mono`
- One component carries time, quantity, step progress, status, date, servings and "Today". Uppercase tracked mono at caption size (about 12 pt) in a box hurts scan-ability and Dynamic Type; five different meanings share one shape so nothing is more important than anything else (see `shelves-light.png`: two boxes on every row).
- `FreshnessStamp` carries icon + word + date at 13 pt and a filled mustard/paprika pill for urgency; good colour-independence but visually the loudest element on screen for a normal item.
- **Fix.** Reserve boxed stamps for one place (the Eat-first urgency badge). Use plain `Label("35 min", systemImage: "clock")` for metadata and a secondary `Text` for quantity. Keep mono only for timers and numerals.

### 3.5 Typography: `LarderFont.swift`
- Fraunces only exists in three static instances (`Fraunces144pt-SoftMedium`, `-SoftBold`, `72pt-SoftSemiBold`); `display(.title2)` and everything else falls to SemiBold 22 (`LarderFont.swift:56-62`). Large titles on Tonight/Ledger use Fraunces while Shelves/Recipes/Grocery use the system SF bold navigation title, and section headings inside the same screens use Fraunces again (`shelves-light.png`). Three display voices in one app.
- Body is `.system(style)`, which is right. Hierarchy within a screen is mostly 17 pt regular vs 17 pt semibold; there is no 15-pt secondary line or 13-pt caption rhythm, so rows look flat.
- **Fix.** Decide one rule: Fraunces for large titles **and** section headers only, applied via a single `ViewModifier`, with `.navigationTitle` plus `.toolbarTitleDisplayMode(.large)` and `UINavigationBarAppearance` custom large-title font, so Tonight/Ledger/Shelves/Recipes/Grocery are identical. Use `title3`/`headline` for row titles, `subheadline` for secondary lines, `footnote` for captions.

### 3.6 Colour: `Tokens/LarderColor.swift`, `Colors.xcassets`
- The tokens are well-built (light/dark/increased-contrast, WCAG-tested). The weakness is application: background is cream everywhere, white-ish cards barely differ, and the only saturated colour is a brick-red paprika that is used for primary buttons, today's label, tab selection and the pick outline; there is no true accent hierarchy (verdigris is both link colour and chip-selected colour). Mustard (`accent.spot`) as a background fill for leftovers and freshness appears loud next to everything else.
- The app does not set an `AccentColor` asset; `.tint(LarderColor.accent.brand)` is applied only at the root (`LarderTheme.swift:10`), so system controls inside sheets (e.g., `Form` toggles, date pickers, `PasteButton`) fall back inconsistently.
- Dark mode works (see `*-dark.png`) and keeps contrast; the only issue is tab-bar ghosting.
- **Fix.** Add the `AccentColor` asset; set `.tint` on every presented sheet root; map selected state to one colour (brand), links to ink-underline or brand, success/ready to verdigris; use mustard only for "use soon".

### 3.7 Empty states: `EmptyShelf.swift`
- A 160 pt line drawing of a shelf and a jar, left-aligned, with `SectionHeading`, body and an optional filled button. The same drawing appears for "No plan", "Nothing to buy", "No recipes", "Nothing on the shelves". It is not recognisable as anything, and left-aligned in a mostly empty screen leaves 60% of the viewport blank (`ledger-light.png`, `grocery-light.png`).
- `ContentUnavailableView` is used in exactly one place (`StartupFailureView`).
- **Fix.** Use `ContentUnavailableView` with context-specific SF Symbols (`calendar.badge.plus`, `cart`, `refrigerator`, `book`), centred, with the primary action inside. If the shelf illustration stays, make it the Pantry empty state only.

### 3.8 Navigation, toolbars and sheets
- Tonight and Ledger hide their nav title and use content titles (`TonightView.swift:26-29`, `LedgerView.swift:112-115`); the others use `.navigationTitle`. Toolbar actions are inconsistent (see 2.1 #4, 2.8 #6).
- Sheets: Settings, Recipe detail and the Meal sheet are presented as sheets from the root (`RootView.swift:105-127`) with a `Button(role: .close)`; the recipe sheet hosts a `NavigationStack` but not a drag indicator or detents. Recipe detail from the Recipes tab is a push (`navigationDestination`), from Tonight/Ledger a sheet; two presentations of one screen.
- Search: `.searchable` only on Recipes. Shelves, Grocery and Ledger have none.
- **Fix.** One recipe-detail presentation (push within each tab's stack, or one shared full sheet). Set `presentationDetents` and `presentationDragIndicator(.visible)` on every sheet. Add `.searchable` on Pantry and Shopping.

### 3.9 Feedback, haptics, animation
- One haptic in the whole app. No haptic on: add, tick a grocery item, mark cooked, swap, plan generated, pick, delete, undo.
- `LarderMotion.stamped` ("the one bounce") is defined but the grep shows no call site for a save stamp; `Copy.Voice.planSaved` ("Stamped. The week is yours.") is used only as a VoiceOver announcement (`LedgerView.swift:78-81`), never shown.
- Loading states are spinners (`ProgressView`) with no skeletons; "Planning the week" is a spinner plus a line in the list header.
- **Fix.** Add `.sensoryFeedback` on grocery tick (`.selection`), add-to-pantry (`.success`), delete (`.warning`), plan generated (`.success`), and show the "Stamped" toast visibly. Use skeleton placeholders for lists and the planning step ("Choosing recipes... Checking your allergies... Writing your list").

### 3.10 Error states
- Four different presentations of errors: alert on root (`RootView.swift:128-134`), inline `LedgerNotice` (info icon, never red, `LedgerNotice.swift`), inline `ErrorBanner` (red triangle, `ErrorBanner.swift`), and raw coloured `Label`s (Recipes, Settings, Paywall, Import). Tone and colour logic differ (the ledger "never shows failure", Shelves shows danger red).
- **Fix.** One `InlineBanner` component (icon, title, message, optional action) with status tones, and one `ToastView` for transient confirmations with Undo; keep alerts only for blocking problems.

### 3.11 Copy catalogue: `Copy.swift`, `*Copy.swift`, `Localizable.xcstrings`
- Tone is consistent and pleasant, but metaphor-heavy: "Ledger", "Shelves", "Eat first", "Let it go", "Eat it", "Stamped. The week is yours.", "shelf balance", "Light / Comfortable / Heavy". Instructions and outcomes are mostly missing: no screen has a one-line subtitle explaining its job except Tonight ("Three ideas from what you have.").
- Several strings contradict the UI: "Pull down to try again" (`RecipesCopy.loadFailed`) and "Pull to try again later" (`GroceryCopy.loadFailed`) when Grocery has no `refreshable`; "Turn it on in Account" (`ShelvesCopy.consentRequired`) but the screen is "Settings".
- Not all feature strings are in the catalogue yet: `RootView.swift` notices and `StartupFailureView` use `String(localized:)` without the shared bundle (STATUS item 6).
- **Fix.** Add a first-visit explainer line to each tab root; replace jargon with task words (section 5 P0-4); audit every instruction string against actual affordances.

### 3.12 Accessibility
Strong: roles/labels, rotors, AX-size layout switches (`AdaptiveStack`), 44 pt targets, Reduce Motion handling, per-screen audits. Gaps found:
- Audit suppressions hide real problems (`LarderUITests.swift:140-160`): the FAB and tab bar occluding content is "skipped", but it is also a visible defect for sighted users.
- 12 pt uppercase mono stamps at AX sizes wrap and break boxes; text-only status via stamps is fine but crowded.
- `TapeLabel` rotation and a mono date header ("SAT, 17 OCT") are read as letter-by-letter by some voices; the visible text is a different string from what the day header announces (`LedgerRow.swift:35-36` combines).
- Not run: VoiceOver/Voice Control manual passes (STATUS item 10).

### 3.13 What is missing from the system entirely
Photo/thumbnail component; skeleton/loading component; toast/snackbar; segmented control; native `List` row style; badge; avatar; first-use tips (TipKit); success/celebration pattern; Glass usage beyond the system tab bar (`grep glassEffect` returns nothing). The Liquid Glass claim in the blueprint is satisfied only by the system tab bar and toolbar buttons.

---

## 4. Gaps beyond the owner's three complaints

1. **Safety**: Skip wipes allergen answers (2.2 #2). Allergen list collapsed to 4 of 15 by default (2.2 #4). The allergen verdict on recipe detail shows nothing for a pass, then the same "Check the label on every product" sentence for every recipe (`RecipeDetailView.swift:217-221`), which trains users to ignore it.
2. **Core loop is open at both ends**: cooking does not update the pantry (2.7 #2, `markCooked`), ticking groceries does (invisibly) (2.8 #3). Users will not trust a pantry that drifts.
3. **Missing basic features** versus category leaders: favourites/collections, ratings, notes, recipe photos, scale/unit conversion toggle, meal-type slots beyond dinner, copy/share a recipe, share a plan, multi-list grocery, aisle reordering, barcode scan UI (engine exists), receipt scan UI, widget deep links, Reminders export, notifications (timer, expiring food, "plan your week" Sunday nudge), iPad layout, Mac/Watch (v2).
4. **Settings dead or misleading**: "Simpler layout" no-op; "Timers flash and vibrate" can't work in background; HealthKit strings with no HealthKit code; camera string with no camera UI.
5. **Paywall timing**: the free week is spent on the first "Plan my week" tap, then the paywall appears on the next (`LedgerModel.generate`, `paywallRequested`). Users never see what Plus does before choosing; Settings shows "FREE" with no counter.
6. **Assistant surfaces are invisible or conditional**: "Why this week?" and quick-add parsing silently route on-device -> proxy -> deterministic; the user never sees which. Offline copy ("Your plan is saved here and will sync later", `Copy.Voice.offline`) promises sync that the blueprint defers.
7. **Date display**: no year anywhere; "13 AUG" next to a 17 Oct "today" (`shelves-light.png`) reads as expired though it is a future date.
8. **Testing blind spots**: UI tests never open onboarding screenshots, paywall, settings content, recipe detail, cooking mode, quick add, import, meal sheet, error states or empty states; `testScreenshots` only saves the five tab roots and the planned ledger (`LarderUITests.swift:96-113`). The audits' skip-rules suppress issues exactly where the FAB and tab bar overlap content.
9. **Brand assets**: no app icon, no launch screen, no marketing illustration set (research 02 specified 40-60 ingredient illustrations; none exist), no photography policy implemented.
10. **Performance/perceived speed**: every tab loads in `.task` with spinners; Recipes shows a spinner titled "Loading recipes" before the list appears, so the FAB and first rows pop in.
11. **iPad/landscape**: declared supported but untested and unspecified; portrait-only on iPhone is fine but `TARGETED_DEVICE_FAMILY` should match what is designed.
12. **Localisation**: UK spellings in strings (Coeliac, Fibre, Sulphites, "Stovetop") alongside US words ("Grocery", "Cookbook"); the app does not choose a locale strategy (`en-GB` vs `en-US`).

---

## 5. Prioritised redesign recommendations

Effort: S < 1 day, M 1-3 days, L 3-8 days (for one SwiftUI engineer).

### P0: fix before anyone else sees the app

| ID | Change | Files | Effort |
|---|---|---|---|
| P0-1 | **Real first-run.** New `IntroView` (3 pages in a `TabView(.page)`: promise, how it works, "Safe for your table"), full-bleed canvas, wordmark, one capsule "Get started". Then a 2-question setup (allergies/diets; household size) with all other questions deferred. Add "Finish setting up" card on Tonight that surfaces goal, cook time, equipment, birth year, conditions, accessibility. Remove the AI toggle and disclaimer from step 1; ask AI consent at first use. | `Sources/FeatureAccount/Onboarding/OnboardingFlow.swift`, `OnboardingModel.swift` (reduce `Step`), `AccountCopy.swift`; new `IntroView.swift` | L |
| P0-2 | **Never discard answers on Skip**; replace per-step Skip with one "Not now" that leaves selections intact; add a UI test that selecting an allergen and tapping the secondary action keeps it. | `OnboardingModel.swift:118-126, 210-239`, `OnboardingFlow.swift:208-228`, `LarderUITests.swift` | S |
| P0-3 | **First-run path to value**: after setup, offer "Start with a sample pantry" (preload 8 staples with dates, clearly removable) or "Show me recipes"; Tonight empty-state button opens the Add sheet directly; rename Parse; add Scan barcode/receipt buttons (wrap `DataScannerViewController`, wire `BarcodeReader` and `ReceiptToPantry`). | `ShelvesView.swift`, `QuickAddSheet.swift`, `RootView.swift:73-75`, `TonightView.swift:47-51`, `Sources/LarderOnDeviceAI/*`; new `ScannerView.swift` | L |
| P0-4 | **Rename and explain.** Tabs: Tonight, Plan, Pantry, Recipes, Shopping; icons `sun.horizon`, `calendar`, `refrigerator`, `book`, `cart`. Actions: "Cook this" -> "Make tonight's dinner" then "Start cooking"; "Add to Ledger" -> "Add to plan"; "Parse" -> "Add"; "Eat it/Let it go" -> "Used up/Throw away"; "Pick for me" -> "Surprise me" (reshuffle) or remove; "Replan" -> "Replan week". Add a one-line purpose subtitle under every large title. Keep "Eat first" as "Use soon". | `Copy.swift`, `LedgerCopy.swift`, `ShelvesCopy.swift`, `RecipesCopy.swift`, `GroceryCopy.swift`, `RootView.swift:71-97`, `LarderUITests.swift` (`Tab` raw values, button labels) | M |
| P0-5 | **Fix "Cook this" / "Add to plan" semantics**: Tonight card primary button = "Start cooking" once added; day picker for "Add to plan"; toast with Undo; no tab jumping. | `TonightView.swift:97-144`, `TonightModel.swift:83-97`, `RecipeDetailView.swift:131-149`, `RootView.swift:154-165`, `AppDependencies.swift:276-287` | M |
| P0-6 | **Remove dead ends**: item edit sheet on Shelves; swipe delete + edit + quantity on Grocery; "Paste recipe text" path in Import; show real units on shelves (stop displaying grams for eggs). | `ShelfRow.swift`, `ShelvesView.swift`, `GroceryView.swift`, `GroceryRowView.swift`, `ImportSheet.swift`, `ImportModel.swift`, `ShelvesCopy.swift:51`, `PantryItem.swift` | L |
| P0-7 | **App icon + launch**: `Assets.xcassets` with Icon Composer icon and `AccentColor`; launch screen colour + wordmark. | `App/Larder/Resources`, `project.yml` | S |
| P0-8 | **Replace the FAB** with toolbar `+` actions (Pantry, Recipes), and put "Plan my week" inside the Plan empty state and in the toolbar when a plan exists. Apply `scrollEdgeEffectStyle(.soft)`. | `FloatingAction.swift` (delete), `ShelvesView.swift:28, 134-147`, `RecipesView.swift:33-41`, `LedgerView.swift:60-67`, `LarderUITests.swift:175-177` | M |

### P1: make it feel like a top iOS app

| ID | Change | Files | Effort |
|---|---|---|---|
| P1-1 | **Photos**: `Recipe.imageURL`, JSON-LD `image` parsing, Nuke-backed `RecipeThumbnail`, hero in detail, tonight cards and plan rows; tinted placeholder for seed recipes; store imported photos locally. Row = thumbnail + title + "Have 6 of 8". | `Recipe.swift`, `JSONLDRecipeParser.swift`, `RecipeRecord.swift`/migration, new `Sources/LarderDesign/Components/RecipeThumbnail.swift`, `RecipeRow.swift`, `TonightView.swift`, `LedgerView.swift` | L |
| P1-2 | **One list row and native lists**: new `LarderRow` (media, title, subtitle, accessory) and move Shelves, Plan, Grocery, Settings to `List` with real `Section` headers; delete `JarLabel`, `TapeLabel` rotation; keep `Stamp` only for urgency. | `LedgerRow.swift`, `JarLabel.swift`, `TapeLabel.swift`, `Stamp.swift`, `ShelfRow.swift`, `GroceryRowView.swift`, `SettingsView.swift` | L |
| P1-3 | **One title system**: `.navigationTitle` + large display font through `UINavigationBarAppearance` or a `.larderTitle()` modifier on all five tabs; same toolbar (settings/profile button top-trailing) on every tab root. | `TonightView.swift`, `LedgerView.swift`, `RootView.swift`, `LarderTheme.swift` | M |
| P1-4 | **Button and chip shapes**: base on native `.borderedProminent`/`.bordered` with capsule shape and Larder tint; chips as capsules with 36 pt visual height; use `.glass` for floating chrome only. | `LarderButtonStyle.swift`, `FilterChips.swift:51-61` | M |
| P1-5 | **Recipe detail and cooking mode**: sticky bottom bar (Start cooking, menu), ingredient have/missing, add missing to Shopping, checkable ingredients, favourite; cooking progress capsule, ingredients sheet, finish sheet with "Mark cooked" + pantry deduction, local notification for timers. | `RecipeDetailView.swift`, `CookingModeView.swift`, `CookingSession.swift`, `TimerModel.swift`, `LedgerModel.markCooked` (`:331`), `PantryRepository.consume` | L |
| P1-6 | **Filters and library**: filter sheet with grouped sections, quick chips, sort menu, favourites segment, bottom/minimised search. | `RecipesView.swift`, `FilterChips.swift`, `RecipesModel.swift`, `RecipeFilters.swift` | M |
| P1-7 | **Settings rebuild** as grouped `List` with navigation pushes; remove or implement "Simpler layout"; real Terms/Privacy URLs; "Plus" row with free-week counter. | `SettingsView.swift`, `SettingsModel.swift`, `PaywallView.swift:6-10` | M |
| P1-8 | **Feedback**: haptics map (grocery tick, add, delete, plan done, undo), visible "Stamped" toast on plan saved (use `LarderMotion.stamped`), one `InlineBanner` + one `Toast` replacing `LedgerNotice`, `ErrorBanner` and ad-hoc `Label`s; skeletons for lists; TipKit tips for swipe actions. | `LedgerNotice.swift`, `ErrorBanner.swift`, `UndoBar.swift`, new `Toast.swift`, `LarderMotion.swift` | M |
| P1-9 | **Empty states**: `ContentUnavailableView` per context with centred layout and in-state actions; use shelf illustration only for Pantry. | `EmptyShelf.swift`, `TonightView.swift`, `LedgerView.swift`, `GroceryView.swift`, `RecipesView.swift` | S |
| P1-10 | **Grocery clarity**: "For Tuesday's dal" subtitles, "Added to pantry" toast with Undo, "Bought" section naming, share + Reminders export. | `GroceryView.swift`, `GroceryModel.swift:196-226`, `GroceryCopy.swift` | M |

### P2: polish and growth

| ID | Change | Effort |
|---|---|---|
| P2-1 | Widget deep link (`widgetURL` -> Tonight), medium widget with three ideas, `tabViewBottomAccessory` mini-player for "tonight: Start cooking". | M |
| P2-2 | Plan view: week strip header, drag to reorder days, per-day add (breakfast/lunch/snack), legend and relocation of the balance card to the top as a collapsible summary. | L |
| P2-3 | iPad: `.tabViewStyle(.sidebarAdaptable)` with split detail, or drop iPad from `TARGETED_DEVICE_FAMILY`. | M |
| P2-4 | Notifications: timers, "use soon" nudge (max one a day), Sunday plan reminder; Reminders export for Shopping. | M |
| P2-5 | Illustration set (research 02 specified 40-60 ingredient drawings): ship 12 for onboarding and empty states first. | L |
| P2-6 | Add UI tests and screenshots for: intro, each onboarding step, quick add, import, recipe detail, cooking mode, meal sheet, settings, paywall, empty states (light/dark/AX3), and remove audit skip-rules once the FAB is gone. | M |
| P2-7 | Locale decision (en-US vs en-GB) and a copy pass; localise `RootView` and App Intents strings. | S |
| P2-8 | HealthKit nutrition write after "Mark cooked", or remove the usage strings until built. | M |

### Suggested order of work
1. P0-2, P0-7 (safety and brand, one day).
2. P0-4, P0-5 (copy and semantics, low risk).
3. P0-1, P0-3, P0-6, P0-8 (first-run, dead ends, FAB).
4. P1-3, P1-4, P1-2, P1-9 (visual consistency pass).
5. P1-1, P1-5, P1-6 (recipes and cooking parity).
6. P1-7, P1-8, P1-10, then P2.

### Design direction in one paragraph
Keep the identity (cream paper, paprika, verdigris, Fraunces for headings, tight hairlines) but express it through **native structures**: large titles, inset-grouped lists, capsule buttons, sheets with detents, toolbar actions, real photos and thumbnails, and iOS 26 glass only on floating chrome. Reserve the stamp motif for two places where it adds meaning (use-soon badges and the "Stamped" save moment). Every screen gets a one-line purpose, one primary action in a predictable place, and an empty state that does the job of the screen.
