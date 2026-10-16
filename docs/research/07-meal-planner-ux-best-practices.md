# Larder research 07: meal-planner / recipe / pantry / grocery UX best practices (iOS 26)

Researched 2026-10-17 to inform a redesign of Larder (SwiftUI, iOS 26+; shelves, week plan, "Tonight", recipes with cooking mode and import, grocery list, account/onboarding/paywall/settings; deterministic planner plus optional AI assistant; calories off by default; allergen safety).

## Evidence notes (read first)

- Apple guidance was read from the primary text: the HIG pages (fetched as the JSON behind developer.apple.com/design/human-interface-guidelines/<page>) and a summary of WWDC25 sessions 356 and 323. Tags: **[HIG]** = Apple HIG text; **[WWDC25]** = Apple session; **[NN/g]** = Nielsen Norman Group.
- **[Teardown]** = ScreensDesign video-chapter/caption pages. These are derived from screen recordings, so chapter counts may not equal screen counts and nothing was hands-on tested.
- **[Review]** = trade/blog reviews (MacStories etc.). **[Vendor]** = competitor blogs and aggregators (Plan to Eat, unstar, justuseapp, RapidDevelopers): useful as signal, biased as evidence. **[Stat-2nd]** = figures relayed by a secondary site, not read in the original report.
- **[Inference]** = my conclusion from the above, or standard iOS practice I did not find a primary page for (for example swipe-action placement, 8pt grid, `isIdleTimerDisabled`). Treat these as defaults to verify, not citations.
- Not reachable: Mobbin (no teardown surfaced), Reddit, Baymard (nothing meal-specific found), Apple's TipKit and Liquid Glass design pages beyond the HIG JSON. No App Store review text could be read directly for Mealime/Paprika/Mela/Pestle; complaint evidence comes from roundups and aggregators.
- Mealime: Larder research 01 records that Mealime announces closure on 2026-10-21 (and Plan to Eat's blog repeats it); my own search did not surface independent confirmation. Its teardown below describes a flow that will disappear within days. Still useful as the category's best-loved "took the decision away" pattern.

---

## 1. First-run experience

### What Apple says [HIG: Onboarding, Launching, Privacy, Managing accounts, Ratings and reviews]

- Ideally people understand the app by using it; if onboarding is necessary make it "fast, fun, and optional". It happens after launch, never as part of it.
- Teach through interactivity; prefer context-specific tips to a single flow; keep it brief so people do not have to memorise anything.
- Any separate tutorial should be skippable, never re-shown after being skipped, and findable later (help/settings).
- Postpone nonessential setup; provide defaults so most people can start immediately.
- Permissions: ask when the feature is first used. Exception: if the app cannot function without it, explain the benefit in onboarding. A custom pre-alert screen is allowed when it adds real context.
- Do not ask for a rating or a purchase during onboarding; wait until people are engaged. Rating prompts only after a significant completed task, at least a week or two apart, via the system prompt.
- Sign-in: "Delay sign-in for as long as possible." Ask for an account only if core functionality needs it; explain benefits in the sign-in view; offer Sign in with Apple or passkeys; account deletion must be possible in-app.
- Launch screen: plain, resembles the first screen, never a splash or branding moment.
- NN/g tutorial study (70 participants, 4 iOS apps, swipe-through tutorials): task success 91% (read) vs 94% (skipped); no speed difference; readers rated tasks harder (4.92 vs 5.49 on a 7-pt ease scale). "Think twice about creating a tutorial for simple applications." [NN/g]

### What the category does

| App | First-run shape | Notes |
|---|---|---|
| Mealime [Teardown] | 12 chapters: welcome, feature carousel, diet, allergies, dislikes, serving size, reminder time, system notification prompt, account creation, animated tutorial, Pro paywall (chapter 11), build plan | Preference questions are the value; paywall comes late, after invested effort. Notification prompt sits before account creation and is unexplained in-flow. |
| Eat This Much [Teardown] | ~14 chapters: sign-up (email/Google/Apple), units, height/weight/age/sex/body fat, goal and rate, activity level, diet, allergies, calorie/macro review, paywall (yearly preselected, 14-day trial, free vs premium table), post-purchase settings, plan generation | Heaviest flow in the set; value (a plan) arrives only after the paywall. Heavy multi-step tooltip tours (Next/Previous/Skip) on every main screen afterwards. Selection uses large single-choice cards; advanced macro options hidden behind "Customize". |
| Mise [Teardown] | 23 to 27 steps incl. diet, budget, equipment picker; computes "estimated yearly savings"; ingredient animation while plan generates; hard paywall straight after, 3-day trial | Author's note: notification permission requested just before paywall with a "we'll remind you before the trial ends" promise; also says a cold launch-time prompt feels abrupt and suggests asking when the grocery list is introduced. |
| Crouton [Teardown] | Icon + "Get Started", then straight to an empty library with search, illustration and an add button. Add menu: manual, from website, QR. | Value-first, no quiz. Heavily "Unlock Pro" gated afterwards; two models (Plus one-time, Discover annual). |
| Plan to Eat [Vendor] | 14-day trial, no card required at sign-up | Reviewer said tutorials were weak but the tour helped a first-time overwhelmed user. |
| Paprika / Mela / Pestle [Review] | No quiz; import-first (browser, share extension, camera scan). | Users are the data source; the empty library is the onboarding. |
| Ollie [Vendor/App Store] | AI plan around schedules/preferences; photo of fridge/pantry; 7-day trial; 4.8 from ~938 ratings | Onboarding flow itself not documented in anything I could read. |
| Apple Reminders groceries [Apple support] | No onboarding: a list type with auto-categorised sections | The benchmark for "no setup". |

Conversion numbers (all **[Stat-2nd]**, via Airbridge/RocketShip/SaaStr summaries of RevenueCat and Adapty): hard paywalls convert about 10.7% vs freemium 2.1% but survivorship-biased and higher refund rates; paywalls after a measurable value moment show about 65% trial-start vs 31% for immediate hard walls; about half of paid conversions happen on day 0. Directionally: value before paywall; not a licence for a hard wall. Larder's blueprint already rejects a hard paywall; keep that.

### Do / Avoid

- Do get to a useful Tonight screen within one minute of first launch, using seed recipes, with zero account and zero payment. The first screen after onboarding should already answer "what's for dinner?".
- Do cap the intro at one welcome screen plus at most three questions: who you cook for (household size), what to avoid (allergens/diet), and optionally "how much time on weeknights". Everything else (equipment, budget, calories, units, dislikes, schedules) is deferred to Settings or asked contextually.
- Do ask the allergen/avoid question early because it is safety-relevant, but make Skip explicit and say what skipping means ("Recipes won't be filtered until you tell us"). Never default "no allergens" silently; show "not set" in the UI.
- Do show a progress indicator on the question flow (a thin bar or "2 of 3") and a Back button on every step; Skip on every optional step.
- Do use large single-choice cards or chips with multi-select, 44pt+, one decision per screen, instead of long forms [Teardown: Eat This Much, Mealime].
- Do put the notification primer where the benefit is obvious: after the first plan exists ("Remind me at 5pm to look at Tonight") or when the first timer starts in cooking mode, not at launch. Show your own pre-alert only with a real "why" and a clear "Not now" [HIG: Privacy].
- Do request camera access on first tap of "Scan" / "Import from photo", photo library on first photo pick, Reminders/Calendar only if you add export.
- Do delay sign-in until something needs it (sync, household sharing, AI assistant). Explain the benefit in that moment [HIG: Managing accounts].
- Do present the paywall at a value moment (second use of "Plan my week", opening Household profiles), with the free tier visible, price and renewal date in plain text, and a Restore/Close control always present [Inference + Stat-2nd].
- Do rate-prompt only after a completed cook or a generated-and-used grocery list [HIG: Ratings].
- Avoid body-metric questions (weight, body fat, sex) in the default path: it is Eat This Much's 17-step pattern, conflicts with "calories off by default", and is a known risk for disordered-eating sensitivity (see research 01).
- Avoid a swipe-through feature carousel; NN/g found tutorials do not improve success and make apps feel harder. Replace it with an interactive first run (for example "Tap a dinner to see why it was suggested").
- Avoid post-onboarding tooltip tours with Next/Previous/Skip on every tab (Eat This Much) [Teardown].
- Avoid splash animations and legal copy in the flow; the App Store shows agreements [HIG: Onboarding].

---

## 2. Navigation and information architecture

### Rules [HIG: Tab bars, Toolbars, Searching; WWDC25]

- A tab bar is for navigation, not actions; keep it visible; use the fewest tabs that cover the hierarchy; avoid the More tab (iPhone shows 5 before overflow); never disable or hide a tab, and if a section is empty explain why.
- Tab labels: "single words whenever possible"; prefer filled SF Symbols.
- iOS 26: tab bar floats on glass; can minimise on scroll (`tabBarMinimizeBehavior`); optional bottom accessory (`tabViewBottomAccessory`); a dedicated search tab (`Tab(role: .search)`) at the trailing end. Avoid screen-specific actions in the tab bar. [HIG, WWDC25]
- Search: if important, give it a primary position; one clearly identified place to find anything; show the current scope; provide suggestions/recents; let people clear history. [HIG: Searching]
- Toolbar titles: concise, under about 15 characters; don't title with the app name; use a large title on iOS to orient. [HIG: Toolbars]
- NN/g: very few icons are universal (home, magnifier, print); heart and star are misread; keep visible text labels with icons. [NN/g: icon usability]

### What the category does

- Crouton: bottom tabs include Meal Plan, Discover, Settings plus the recipe home with search, folder grid and tags; meal planner is a vertical list of daily cards where a menu adds recipe, note, random recipe or section. [Teardown] A MacStories reviewer values it as "a dedicated tab that lists current and upcoming days", simple. [Review]
- Mela: calendar entries live in the system Calendar; grocery list lives in Reminders; layout adapts per device (single column iPhone, two/three panes iPad). [Review, mela.recipes]
- Paprika: daily, weekly or monthly calendar; reusable multi-day menus. [App Store listing, via search]
- Samsung Food: moved the meal-plan calendar to a list view with a one-tap toggle back (v2.18.0 changelog). Tablet layouts criticised as just a phone tab bar. [APKMirror, SamMobile]
- RecipeSage docs: phone calendar collapses to month grid with dots, tap day for list below; list view groups by date from today and folds past days. [Vendor docs]
- Plan to Eat's claim that Mealime has "no true calendar view" and that its shopping list resets when the plan changes is competitor marketing. [Vendor]

### Week-planner layout options

| Layout | Strength | Risk | Verdict for Larder |
|---|---|---|---|
| Vertical list of days, starting today, past days folded | Matches how people use it (what's next), scales to Dynamic Type, accessible, works with swipe/menus | Harder to see a week at a glance | Default |
| Horizontal day strip (Mon to Sun chips) as a navigator above a list | Fast jump, shows which days are empty/planned | Drag between days is awkward (NotePlan users report broken drag in horizontal week); breaks at large type | Use as a header/scroll anchor, not the primary surface |
| Month/calendar grid | Long-range, copying a week | Dense; poor at AX sizes | Optional later; not v1 |
| Drag-and-drop between days | Natural on iPad | A heuristic evaluation found drag/scroll conflicts on phones | Always provide "Move to..." in a context menu and swipe action |

### Do / Avoid

- Do use at most 5 plain tabs. Recommended: **Tonight**, **Week**, **Recipes**, **Pantry**, **Groceries**. Put Account/Settings behind a profile button in the Tonight toolbar (not a tab), as it is infrequent and not part of the cooking loop.
- Do reconsider internal brand nouns as tab labels. "Ledger" and "Shelves" are metaphor words; NN/g and HIG both favour single plain words, and research 01 says Mealime users valued "took the decision away", not metaphor. Suggested compromise: plain tab labels (Week, Pantry) and brand words inside the screen (large title "This week", subtitle or section "On the shelves", the stamped-label visual). **Decision for the owner**: this overrides the current naming.
- Do make Tonight the landing tab and answer one question: what are we eating, is anything missing, how long will it take. One primary button ("Cook this" or "Start cooking"), one secondary ("Swap").
- Do put search where Apple does: either `Tab(role: .search)` as the trailing tab (global recipe+pantry search) or `searchable` in Recipes. Show scope ("Search recipes").
- Do give each tab an explanatory empty state rather than hiding it [HIG: Tab bars].
- Do keep the main action discoverable: one "+" in the top-trailing toolbar of Week/Recipes/Pantry/Groceries opening a short menu (Crouton's add menu: manually, from website, scan) and one glass-prominent button for the screen's primary verb.
- Do consider `tabBarMinimizeBehavior(.onScrollDown)` for long lists (Recipes, Groceries) and a bottom accessory for an active cooking session or running timer ("Pasta, 6:12 left, Step 3 of 7"), which makes the in-progress cook re-enterable from any tab. [Inference built on WWDC25 API]
- Avoid a hamburger/"More" for core features, a Settings tab, or an action button in the tab bar.
- Avoid icon-only toolbar buttons for non-standard actions; use SF Symbols with tooltips/labels where meaning is unclear (see section 7).
- Avoid forcing drag-and-drop as the only way to reschedule.

---

## 3. Component craft (iOS 26)

### Liquid Glass ground rules [HIG: Materials; WWDC25 356/323]

- Liquid Glass is the functional layer (tab bars, toolbars, sheets, controls) above content. "Don't use Liquid Glass in the content layer." Use sparingly on custom controls; group nearby glass in `GlassEffectContainer`; do not stack glass on glass.
- Regular variant for anything with text; clear only over rich media with dimming (35% for bright media).
- Remove custom backgrounds on bars and sheets (`presentationBackground`, `toolbarBackground`) so the system material and scroll-edge effect work. Use one scroll edge effect per view; soft by default on iOS.
- Concentricity: nested radius = parent radius minus padding; capsule on iPhone for buttons; use `.containerConcentric`.
- Tint only to convey meaning (the primary action), not decoration; toolbar icons render monochrome.
- Larder fit: its visual system (paper, hairlines, no shadows) is a content-layer style; keep it there and let chrome stay system glass. Larder's radii (8/12/24/pill) nest cleanly: a 12pt card inside a 24pt sheet with 12pt padding is concentric. [Inference]

### Components

**Recipe cards and rows**
- A grid of cards works when images dominate; lists are better for text-heavy scanning [HIG: Lists and tables].
- ScreensDesign guidance: show title, image, time, meal type, diet, source, saved state; "Avoid putting the full recipe on the card." [Teardown article]
- Photo-forward grids are the norm in Crouton/Pestle [Teardown]; Mela leans on typography [Review: "wonderful typography", "carefully laid out text"].
- Larder has no stock photos by design. Do: a typographic card (Fraunces title, time, a food-group colour band or the shelf-label stamp, allergen status chip). Offer the user's own photo when imported (schema.org image) and fall back to the typographic card when absent; never a grey placeholder box. Avoid: a blank image slot, or a stock photo or emoji filler.
- Row anatomy: title, one line of meta (time, servings), trailing status (allergen stamp, "have 7/9"). Use `ViewThatFits` so rows reflow at large type instead of truncating.

**Chips, filters, segmented controls, pickers**
- Segmented controls: closely related views of the same thing, at most about 5 segments on iPhone, noun labels, don't mix icon and text. [HIG: Segmented controls] Use for List/Calendar toggles or Ingredients/Steps, not for navigation between sections.
- Filters: a horizontal chip row for 3 to 6 frequent filters (Quick, Vegetarian, Uses pantry) and a "Filters" sheet for the rest. Show the active-filter count. Allergen exclusions are a persistent setting, shown as a labelled strip ("Avoiding: peanuts, sesame"), not a chip that can be toggled away casually. [Inference]
- Prefer pickers/menus over free text where possible [HIG: Entering data].

**Search** - see section 2. Support dictation and recents; index recipes in Spotlight [HIG: Searching].

**Sheets and detents** [HIG: Sheets; WWDC25]
- Use for focused tasks (add item, swap meal, filters, timer). One sheet at a time. Medium detent for progressive disclosure; compose-style tasks go full height; include a grabber on resizable sheets; support swipe-down dismiss and confirm with an action sheet if there are unsaved changes.
- Cancel on the leading edge, Done/Confirm on the trailing; never all three of Cancel, Done, Back. Partial sheets are inset glass on iOS 26 and turn opaque at full height; don't override the background.
- Use `matchedTransitionSource` + zoom navigation transition to morph a sheet from the toolbar button.
- Avoid sheets for deep or multi-step flows (use a pushed screen or full-screen cover; import review is the borderline case).

**Toolbars and buttons**
- Group by function and frequency (`ToolbarSpacer`); don't group symbols with text buttons; keep Done separate and tinted; move secondary actions into a More menu. [WWDC25, HIG]
- Floating button vs toolbar button: Apple's own pattern in iOS 26 Mail/Notes is a toolbar item (top-trailing or in the bottom bar), with a single prominent glass button for the main commit action. A custom floating "+" over scrolling content is a content-layer glass control, which the HIG discourages unless it is one of the most important functional elements. Recommendation: toolbar "+" everywhere; at most one `.glassProminent` bottom button per screen for the primary verb (Start cooking, Add all to list) with an `.safeAreaInset` so it never covers rows. [Inference]
- Button labels are verbs ("Add to list", "Start cooking") [Inference, consistent with HIG alerts wording]. Use `.buttonBorderShape(.capsule)` on iPhone.

**Swipe actions and context menus**
- Context menu: few items, most relevant first, destructive last and red, same icons as the system, support it consistently across the app, and mirror every item elsewhere in the main UI because menus are hidden. [HIG: Context menus]
- Swipe actions are not in the HIG pages I fetched. Convention [Inference]: trailing = destructive/remove (full-swipe delete only if undoable), leading = positive/fast (Check off, Mark cooked). Always duplicate in a context menu and expose as VoiceOver custom actions.

**Haptics and motion** [HIG: Playing haptics, Motion]
- Use system haptics consistently, only to reinforce a cause and effect, never overuse; make them optional; short transient haptics.
- Larder candidates: light impact on check-off, success on "Planned" / plan generated, warning on allergen conflict, notification-style at timer end. SwiftUI `.sensoryFeedback` covers these. Skip haptics for scrolling, tab changes, or every tap.
- Motion: purposeful, brief, cancellable; avoid animating frequent interactions; supplement with non-motion cues; honour Reduce Motion (Larder tokens: 120/220/360 ms, one bouncy "stamp").

**Typography, spacing, SF Symbols**
- Use text styles with Dynamic Type; avoid ultralight/thin/light weights; keep hierarchy through weight and size and preserve it when text grows; at larger sizes prioritise the important content rather than scaling everything [HIG: Typography].
- Spacing: HIG accessibility advice is about 12pt padding around bezeled controls and about 24pt around unbezeled ones; 44pt minimum targets. The "8pt grid" is a convention rather than an HIG rule [Inference]; use 4/8/12/16/24 steps with `@ScaledMetric`.
- SF Symbols: prefer filled in tab bars; monochrome in toolbars; same weight as adjacent text; semantic symbol per concept used consistently (one symbol for "pantry", one for "grocery"); custom ingredient glyphs are fine in content but not as the only label.

### Do / Avoid summary
- Do let system components render the chrome; do style content, not bars.
- Avoid custom nav bar backgrounds, a hand-drawn bottom bar, glass cards in lists, tinted toolbar icons for decoration, or glass over glass.

---

## 4. Pantry and grocery UX

### Evidence
- Apple Reminders groceries: auto-categorised sections, renameable and reorderable categories, empty ones hideable. [Apple support, via search]
- Banana: type "2 avocados, whole-grain pasta, milk" and it splits and groups by category. TickIt: sorts into supermarket-style categories. [App Store listings]
- Paprika: merges duplicate ingredients, groups by aisle with custom reorderable aisles, multiple lists; pantry tracks quantity, purchase date and expiry and moves items between pantry and grocery list. [App Store listing]
- Mela and Pestle: send ingredients to Reminders with items pre-selected so you uncheck what you already have; Mela puts quantities in the Notes field. Crouton: "Add to Groceries" modal with per-ingredient checks and a count on the confirm button; banner confirms additions; empty state with basket icon; custom numeric keypad for quantities. [Review, Teardown]
- Complaints: Mealime list resets when the plan changes and consolidation can feel useless (Vendor); Ollie: old meals linger until deleted, quantities in cups/oz not item counts, checked-off items reappear when a meal is added, shared lists need a manual refresh (Review via search); Mob: duplicate "mint" and "fresh mint" (Review aggregator); Paprika: web import drops ingredients (Vendor).
- ScreensDesign guidance: let users review quantities before handing off to groceries, mark pantry items, avoid duplicates across recipes, and treat the list as a reversible projection that does not overwrite checked or manually edited items. [Teardown article]
- Pantry apps (small apps via search): green/amber/red expiry with counts per state, user-adjustable "expiring soon" window, group by fridge/freezer/pantry, barcode/receipt/camera because manual entry is the adoption barrier. [Vendor/App Store]
- HIG: don't ask for what can be inferred; offer choices instead of typing; support paste/drag; validate as the user types. [HIG: Entering data]

### Do / Avoid
- Do give one fast-add field at the top of Pantry and Groceries that accepts natural language ("2 onions, 500g rice, milk") and shows the parsed rows for a one-tap confirm or edit. Parse deterministically first (quantity, unit, name); use the model only as optional enhancement. Never block saving on a parse failure; keep the raw text.
- Do suggest from existing names as you type (autocomplete from pantry, recipes, and past lists) and snap to canonical ingredient names so "mint" and "fresh mint" merge, with a visible "merged 2 items" detail.
- Do group the grocery list by aisle with sensible default aisle order, user-reorderable, empty aisles hidden, "Other" last. Make an aisle header show count.
- Do pre-select recipe ingredients, subtract what the pantry already holds ("Have 200g of 500g; adding 300g"), show the count on the confirm button ("Add 7 items"), and confirm with an inline banner with Undo, not an alert.
- Do keep checked items in place for a moment, then move to a collapsed "In the basket (6)" section; one tap to uncheck; light haptic on check. Never reset checked or manually edited items when the plan changes; mark them "from plan" vs "added by you" so regeneration only touches plan-derived rows.
- Do offer "Done shopping" which proposes moving the basket to Pantry with quantities and best-by suggestions, and is undoable. This matches the blueprint's "checked items land on the shelves".
- Do show expiry with icon + word + date ("Use soon · Thu"), never colour alone; sort "Eat first" to the top; let the user set the window; default dates from category with "estimated" labelled.
- Do show quantities in the units a shopper buys (2 onions, 1 bag rice), converting from recipe units where possible (the Ollie complaint).
- Do support Share sheet / Reminders export for lists others use, and live shared lists only if sync is reliable (Ollie and Crouton shared-list complaints).
- Avoid separate "add" screens with many fields as the default path; avoid auto-adding without a review step; avoid silent merges that change quantities; avoid a list that resets.
- Avoid claiming a pantry quantity is current when it is an estimate; label as estimated (consistent with research 01's "stale snapshot" point about scans).

---

## 5. Cooking mode

### Evidence
- Mela: full-screen focus mode, larger font, dims every step except the current, tap ingredients to check off, switch between several recipes while cooking a menu, timers from Cook Mode. [mela.recipes, MacStories]
- Pestle: very large green "Start Cooking" button "easy to hit even if your iPhone... is sitting on a kitchen counter an arm's length away"; ingredients and times highlighted in an accent colour that works in light and dark; tap an ingredient to see its quantity, tap a time to start a timer; hands-free voice "Next"/"Previous" with customisable phrases; timers in the toolbar; iPad shows ingredients left, steps right in large text. [MacStories]
- Crouton (2024 Apple Design Award, Interaction): swipe or tap arrows through steps; hands-free wink gesture on TrueDepth devices (limited by camera angle); iPad two-column; collapsible ingredient checklist at the bottom of step view; floating timer card with quick-add minutes; multiple timers from tapping times in steps. [Review, Teardown, crouton.app]
- Paprika: keeps the screen on, cross off ingredients, highlights current step, auto-detects times in directions and starts a timer on tap. [App Store listing]
- Vendor guidance (low weight): one step per screen, large type, step counter and progress, previous/next, quantities near the instruction, labelled timers, persistent state, nothing that needs scrolling mid-cook, no ads between steps, no account wall. [Vendor]

### Do / Avoid
- Do give a single "Start cooking" entry (large, prominent) on every recipe and on Tonight; resume an in-progress cook from a bottom accessory.
- Do show one step at a time in large text that scales with Dynamic Type including AX sizes (reflow with `ViewThatFits`, not capped, per Larder's accessibility audit rule), with "Step 3 of 8" and a progress bar. Let the step itself scroll if it overflows, but keep Next/Back fixed at the bottom within thumb reach.
- Do inline the amounts used in this step ("2 tbsp oil") so the user need not return to the ingredient list; keep a collapsible ingredient checklist (check-off persisted) reachable in one tap. [Mela, Crouton, Pestle]
- Do detect durations in step text and render them as tappable timer chips ("10 min"); name each timer after its step; allow several; show them in a persistent strip and in the bottom accessory. Run timers via local notifications (and a Live Activity/Dynamic Island if added) so they fire while backgrounded or locked [Inference: standard iOS APIs]; sound plus haptic at the end; VoiceOver announcement.
- Do keep the screen awake only while cooking mode is visible (`UIApplication.isIdleTimerDisabled` or the SwiftUI equivalent), restore it on exit/background, and tell the user once ("Screen stays on while you cook") with a setting. Mind battery. [Inference]
- Do offer optional voice control (Pestle) as a button-activated toggle; don't assume it works in a noisy kitchen; never make it the only control. Voice Control and big swipe targets also serve accessibility.
- Do dim non-current steps (Mela) or collapse them, and highlight only what is actionable (ingredient amounts, times) with an accent plus underline/weight, not colour alone.
- Do show an allergen line at the top of cooking mode if the recipe was flagged ("Contains: sesame (you avoid this)") so a swap is made before cooking, not mid-cook.
- Do keep state if the user leaves; reopening resumes at the same step and timer states.
- Avoid ads, upsells, or rating prompts mid-cook; avoid tiny ingredient text; avoid requiring scrolling to find "Next"; avoid pop-ups that cover the step; avoid sound-only cues.

---

## 6. Empty states, loading, errors, destructive actions, undo

### Rules
- **Empty states** [NN/g]: (1) communicate system status, never show "No records" while still loading; (2) provide learning cues (in-context "pull revelations" beat long onboarding); (3) provide a direct path to the key task (a button, not just a description), plus a demo/sample option for complex apps. [HIG: Tab bars] adds: if a section is empty, explain why.
- **Loading** [HIG: Loading, Progress indicators]: show something as soon as possible; placeholders replaced by content; let people do other things while loading; use determinate indicators when duration is known.
- **Alerts** [HIG: Alerts, Action sheets]: use sparingly; not for information alone; avoid alerts for common undoable actions even if destructive; titles say what happened, never "Error"; button titles are verbs; destructive style only where the user did not deliberately choose it; avoid "OK" except for informational. Use an action sheet (SwiftUI `confirmationDialog`) for choices about an intentional action, destructive choice at top, Cancel at bottom, at most about 3 choices plus Cancel.
- **Undo** [HIG: Undo and redo]: help people predict the result, show the result (restore scroll/highlight), allow multiple undos, don't redefine shake/3-finger gestures. Inline undo toasts are the mobile convention for list edits [Inference].
- **Errors**: reviewers cite a crash when swapping a meal by category (Eat Together) and plans that delete themselves (Mob) [Review aggregator]; the lesson is that data loss on a planner is trust-ending.

### Larder states and what to show

| State | Treatment |
|---|---|
| First launch Tonight | Seeded suggestions, not blank; if the pantry is empty, "Tonight" still shows quick pantry-light dinners and a link "Add what you have" |
| Empty Week | "Nothing planned yet." Buttons: "Plan tonight" and "Plan my week" (Plus, free trial week), "Add a recipe". Offer "Copy last week" when history exists |
| Empty Pantry | One sentence of purpose, add field focused, "Scan a barcode" and "Add from last grocery trip" |
| Empty Groceries | Basket glyph, "Your list builds itself from the plan" with button "Go to Week" (Crouton uses a basket empty state with banner confirmation) |
| Empty search | Echo the query, suggest widening filters, offer "Import a recipe" |
| Loading recipes/import | Skeleton rows; parsed-import progress "Reading ingredients...", then a review screen showing what was and wasn't parsed so nothing is dropped silently (Paprika import complaint) |
| AI unavailable/offline | Deterministic planner keeps working; the assistant surface says "Assistant is offline. Plans still work." Never block Tonight on a network call |
| Failed import | Say which part failed ("Couldn't find ingredients on this page"), offer paste text / photo scan |

### Do / Avoid
- Do use SwiftUI `ContentUnavailableView` (or equivalent) with a title, one sentence and one button [Inference: standard API].
- Do delete without confirmation when it is undoable (single recipe, grocery row, a planned meal) and show "Removed. Undo" for about 5 seconds; keep a "Recently deleted" for recipes. Confirm with an action sheet only for irreversible bulk actions (clear all groceries, delete account, reset pantry), name the object and count ("Delete 12 items?"), destructive button first.
- Do give account deletion in-app and say when it completes [HIG: Managing accounts]; offer full export first (blueprint: JSON export; Yummly's shutdown with no bulk export is the cautionary case [Vendor/trade press]).
- Do write errors with what happened + what to do. Avoid "Something went wrong", "Error", raw codes.
- Avoid a launch-time alert [HIG: Alerts]; avoid spinners with no content; avoid blank screens during sync.

---

## 7. Clarity of function: discoverability, tips, labels, jargon

### Rules
- **Tips** [HIG: Offering help; TipKit docs]: tips are short transient views for new or less-obvious features; popover when you want to preserve flow, inline when you want surrounding content visible; one to two sentences; direct action language; feature should need no more than about three actions; define rules so only eligible people see them; cap frequency (HIG suggests e.g. once every 24 hours); include the feature's symbol (filled); a button may deep-link to a setting. TipKit's own page: use sparingly, don't show every launch, **don't use tips to guide people through your app** or to advertise.
- **Contextual over upfront** [HIG: Onboarding; NN/g tutorials and empty-states].
- **Labelled icons** [NN/g]: icon meaning is ambiguous; keep visible text labels; a clock icon was never clicked in a study; heart/star are ambiguous.
- **Terminology** [HIG: Offering help]: be consistent and platform-appropriate; describe the specific task, not how standard controls work.

### Candidate Larder tips (each should fire once, after a trigger, by rule)
1. Swipe a planned meal to Swap or Skip (after 3 planned meals).
2. Long-press a grocery item to move it to Pantry (after first shopping trip).
3. Tap a time in a step to start a timer (first cooking session).
4. "Eat first" shelf: items due within 3 days appear here (after first item with a date).
5. Share a recipe link into Larder (after 2 manual imports).

### Do / Avoid
- Do replace tooltips tours with at most a handful of TipKit tips keyed to events; set a global frequency of about one tip per day.
- Do give every non-obvious icon a text label or a `Label` in menus; use `accessibilityLabel` and `help`/tooltips for iPad pointer.
- Do put a "Help & tips" entry in Settings that lists tips again (HIG: findable tutorial) and a replay of the first-run explainer.
- Do speak plainly: "Best by" not "expiry date metadata"; "Use soon" not "FIFO"; "Ingredients to buy" not "delta list"; "Why this?" for recommendation reasons. Name AI features by what they do ("Plan my week"), not by technology; mark the AI-assisted parts with a small "Suggested" label and always give the reason. [Inference, consistent with blueprint voice]
- Avoid custom iconography as a sole label for core actions, jargon words as navigation labels (see tab labels in section 2), and promotional tips.

---

## 8. Accessibility and Dynamic Type

(Cross-reference research 03 for the v1 acceptance checklist; this section covers what is specific to meal-planner UX.)

### Rules [HIG: Accessibility, Typography, Layout]
- Support text enlargement of at least 200%; use system text styles; prefer regular and heavier weights; prioritise important content when text grows rather than scaling everything.
- Contrast: meet WCAG/APCA minimums; check light and dark; honour Increase Contrast and Reduce Transparency (Liquid Glass changes under these settings).
- Do not convey status by colour alone (allergen, expiry, done).
- About 12pt padding around bezeled controls and 24pt around unbezeled; 44pt hit targets; give spacing the same weight as size.
- Be cautious with fast motion; honour Reduce Motion with fades and tighter springs; consider Assistive Access.
- Describe interface and content for VoiceOver; the grabber on sheets works with VoiceOver for detent changes.

### Where meal apps fail
- Reviewers complain of tiny text on phones with no zoom, and no landscape on tablets (Review aggregator). Competitors' recipe rows truncate at large sizes [Inference].
- Cooking mode is used at arm's length, in bright light, with wet hands, i.e. an "accessibility situation" for everybody.

### Do / Avoid
- Do reflow rows with `ViewThatFits` or `Layout` at accessibility sizes (stack image/stamp above text); do not cap Dynamic Type or suppress with `minimumScaleFactor` as a fix (Larder's own audit rule: a capped text size is flagged; skips only for geometry-based false positives).
- Do keep content from sliding under glass: add `safeAreaInset` bars and `scrollContentBackground`/scroll-edge behaviour tested at AX5 (Larder memory: "content under glass" is an audit flag).
- Do give each day cell a full VoiceOver label ("Tuesday 20 October, dinner: Lentil soup, 35 minutes, contains no avoided allergens"); announce timer completion; provide custom actions mirroring swipes; Voice Control names matching visible labels.
- Do show allergen results as text + icon + position ("Contains sesame" with a shield or warning glyph), never colour alone, and "Not checked" as a distinct state (blueprint rule: unknown is never shown as safe).
- Do offer tap alternatives for drag/reorder (Move up/Move to...). Do test with Reduce Transparency and Increase Contrast.
- Avoid text on photo without a scrim; avoid fixed-height rows; avoid timers that only vibrate or only play sound.

---

## 9. What users hate and love in meal-planner apps

### Complaints (frequency by theme; all from reviews roundups/aggregators, flagged as weaker evidence)

1. **Paywall and trial deception**: "free" listings that give nothing free (vegan planner reviewer; Mealime free tier "kind of pointless"), trials converting without reminder (Yummly), annual renewals that happened silently and cancellation buried (Mealime), renewals at a higher price than the trial implied (NYT Cooking), features moved behind Premium (Allrecipes serving sizes). Users ask for a one-time purchase. [Vendor/Review: unstar, Trustpilot/aggregators]
2. **Repetition**: same meals every week (Mealime), recommendations stale after 2 to 3 months (Yummly), Mob and others. [Vendor]
3. **Grocery list failures**: duplicates, missing quantities, resets on plan change, checked items reappearing, quantity units unsuited to shopping, no live sharing. [Review aggregator, Vendor]
4. **Data loss and sync**: plans deleting themselves (Mob), lost recipes after device change (Paprika), save/sync failures (NYT), Yummly's shutdown with no bulk export. [Review aggregator, Vendor]
5. **Import errors**: dropped ingredients or times, clippers failing on some sites. [Vendor]
6. **Allergen and diet failures**: peanut recipes shown with allergen filter (Yummly); users want tagging and substitutions; "most recipes require an ingredient I can't eat". [Vendor/Review aggregator]
7. **Ads and interruptions**: full-screen video ads mid-cook (Allrecipes). [Vendor]
8. **Setup burden**: usability study found the family organiser requiring lots of user input scored lowest; participants weighed time saved against effort (JMIR Mhealth 2021, Mauch et al.; I could read only the abstract) [peer-reviewed, partial].
9. **Accessibility**: text too small/no zoom, no landscape on tablets. [Review aggregator]
10. **Crashes in flows**: category swap crashes (Eat Together). [Review aggregator]
11. **Per-platform repurchase** and dated UI (Paprika). [Vendor]

### What top apps do that users praise
- Ollie (4.8 from ~938 ratings): removes the nightly "what's for dinner" stress; plans adapt to tastes/dietary needs; auto grocery list; flexibility to shift meals; improves over time. [App Store, sample of 4 reviews, Vendor]
- Plan to Eat (4.8 from ~6,100 ratings): drag recipes onto a calendar, list builds automatically, extra staples, reorder categories, per-store lists; 14-day trial without card. [App Store listing]
- Mealime (before closure): "took the decision away"; aisle-sorted grocery list; touch-free cooking mode; low Pro price. [research 01, Vendor]
- Mela and Crouton: restraint, typography, per-device layout, import (Paprika importer, share sheet, camera), focus-mode cooking, grocery via Reminders, one-time prices. Mela was a 2025 Apple Design Award finalist (Interaction, Delight and Fun); Crouton won Interaction in 2024. [Apple newsroom, Review]
- Pestle: hands-free voice, accent colour on measurements, tap-to-timer, ingredients detected. [MacStories]
- Paprika: no ads, one-time price, strong import (complaints noted above). [Vendor]

### Do / Avoid
- Do be explicit about the free tier on the App Store page and in-app; send a renewal reminder before trial end; show price + date; offer cancel link (Settings > Subscription) [Inference].
- Do vary suggestions: track recently cooked/skipped; surface "last made" and a rotation setting; explain why each suggestion appears.
- Do treat grocery list state as user-owned; only regenerate plan-derived rows.
- Do ship data export and import-from-competitors (research 01 recommendation, reinforced by Mealime/Yummly closures).
- Avoid ads, trial dark patterns, plan auto-deletion, silent import drops, and any allergen claim stronger than the data supports ("No avoided allergens detected" with source/limits, not "Safe").

---

## Where this report agrees or conflicts with current Larder decisions

- Agrees: no hard paywall; allergen safety free forever; calories off; no streaks; export; cooking mode with timers and keep-awake; natural-language quick add; aisle-sorted grocery list; checked items land on shelves; one generated week to try Plus.
- Suggest revisiting: brand-noun tab labels (Ledger, Shelves) vs plain single words; custom visual styling of chrome (HIG and WWDC25 ask to remove custom bar/sheet backgrounds, keep the paper/ink identity in content); typographic recipe cards to replace photos.
- Open question I could not resolve from sources: swipe-action conventions and whether a floating "+" button is acceptable under iOS 26. Both are shown as [Inference]; verify against Apple apps (Reminders, Notes, Mail) on a device.

---

## Top 25 actionable recommendations for Larder

- [ ] 1. First run: one welcome screen plus at most three optional questions (household, allergens/diet, weeknight time) with Back and Skip, then land on a populated Tonight within about a minute; no account, no paywall.
- [ ] 2. Ask the allergen question early but skippable; if skipped, show "Allergens not set" in the UI and never imply safety; make it editable from the first screen.
- [ ] 3. Drop body-metric, calorie and weight questions from the default path; if offered later, they live in Settings behind an explicit opt-in.
- [ ] 4. Replace any swipe-through feature carousel with an interactive first run and 3 to 5 TipKit tips triggered by events (rate-limited to about one per day).
- [ ] 5. Prime notifications after the first plan exists or when the first timer starts, with your own one-line reason and a "Not now"; request camera/photos on first use.
- [ ] 6. Delay sign-in until sync, sharing or the assistant needs it; support Sign in with Apple/passkey; ship in-app account deletion and full JSON export.
- [ ] 7. Paywall at a value moment (second "Plan my week", household profiles), free tier visible, price/renewal in plain text, Close and Restore always present; send a pre-renewal reminder; no rating prompt on first launch.
- [ ] 8. Tabs: Tonight, Week, Recipes, Pantry, Groceries (5 max, single plain words, filled symbols, never disabled); Account and Settings behind a profile button, not a tab. Decide whether brand nouns ("Shelves", "Ledger") stay as screen titles only.
- [ ] 9. Tonight is the home screen: one answer, one primary button (Start cooking), one Swap; show why it was suggested and what's missing.
- [ ] 10. Week = vertical list of days from today with past days folded; optional day-strip header for jumping; a "Move to..." menu and swipe action in addition to any drag.
- [ ] 11. Search: use `Tab(role: .search)` or `searchable` in Recipes with visible scope, recents/suggestions, and Spotlight indexing.
- [ ] 12. Let system chrome be glass: remove custom bar, toolbar and sheet backgrounds, one scroll-edge style per view, `GlassEffectContainer` for any custom glass, no glass inside content; keep paper/ink styling in the content layer.
- [ ] 13. Toolbar "+" (opening a short add menu) for add actions, grouped with `ToolbarSpacer`; at most one `.glassProminent` bottom button per screen for the primary verb, inset so it never covers rows; no action buttons in the tab bar.
- [ ] 14. Sheets: medium+large detents with grabber, Cancel leading and Done trailing, one sheet at a time, swipe-dismiss with an action-sheet confirm when there are unsaved edits.
- [ ] 15. Typographic recipe cards (no stock photos): title, time, food-group band, allergen/have-it status; show the user's own imported photo when available; rows reflow with `ViewThatFits` at AX sizes with no capped text.
- [ ] 16. Quick add: natural-language field on Pantry and Groceries; deterministic parse first, show parsed rows for one-tap confirm, autocomplete to canonical names so duplicates ("mint"/"fresh mint") merge and say so.
- [ ] 17. Grocery list: aisle groups (user-reorderable, empty hidden), pre-selected recipe ingredients minus pantry stock, "Add 7 items" confirm with undo banner, checked items move to a collapsed "In the basket", and plan changes never reset checked or user-added rows.
- [ ] 18. Pantry expiry: "Use soon" with icon + word + date, window user-adjustable, "Eat first" on top, group by storage location, estimated dates labelled as estimated; "Done shopping" proposes moving the basket to the shelves, undoable.
- [ ] 19. Cooking mode: one step per screen in large Dynamic Type text, "Step n of N" with progress, inline amounts, collapsible persisted ingredient checklist, dimmed non-current steps, fixed Next/Back in thumb reach.
- [ ] 20. Cooking timers: auto-detect durations into tappable chips, multiple named timers, run via local notifications (consider a Live Activity), end with sound + haptic + VoiceOver announcement; screen stays awake only while cooking, restored on exit; bottom accessory to resume an active cook.
- [ ] 21. Empty states for every tab and for search/import: status-true message, one sentence, one primary button (and sample data where useful); skeletons for loading; import review screen that shows what was and wasn't parsed.
- [ ] 22. Destructive actions: undoable ones (remove a meal, grocery row, recipe) happen instantly with a 5-second "Undo" toast and "Recently deleted"; confirmationDialog only for irreversible/bulk actions, with named object and count, destructive option first.
- [ ] 23. Errors and offline: plain "what happened + what to do" copy; the deterministic planner and Tonight never depend on the network; the AI assistant degrades to a clear "offline" state; never auto-delete or silently drop user data.
- [ ] 24. Haptics and motion: a small consistent set (light on check-off, success on plan saved, warning on allergen conflict, notification at timer end), optional in Settings, honour Reduce Motion; no haptic/animation on routine navigation.
- [ ] 25. Accessibility gates for every screen: AX5 without truncation, status never by colour alone ("Not checked" is distinct from safe), VoiceOver labels that read day/meal/allergen status, tap alternatives to every swipe/drag, 44pt targets with 12 to 24pt spacing, Increase Contrast and Reduce Transparency tested over glass.

---

## Sources

Apple (primary)
- Onboarding: https://developer.apple.com/design/human-interface-guidelines/onboarding
- Launching: https://developer.apple.com/design/human-interface-guidelines/launching
- Tab bars: https://developer.apple.com/design/human-interface-guidelines/tab-bars
- Toolbars: https://developer.apple.com/design/human-interface-guidelines/toolbars
- Sheets: https://developer.apple.com/design/human-interface-guidelines/sheets
- Materials (Liquid Glass): https://developer.apple.com/design/human-interface-guidelines/materials
- Searching: https://developer.apple.com/design/human-interface-guidelines/searching
- Lists and tables: https://developer.apple.com/design/human-interface-guidelines/lists-and-tables
- Segmented controls: https://developer.apple.com/design/human-interface-guidelines/segmented-controls
- Context menus: https://developer.apple.com/design/human-interface-guidelines/context-menus
- Alerts: https://developer.apple.com/design/human-interface-guidelines/alerts
- Action sheets: https://developer.apple.com/design/human-interface-guidelines/action-sheets
- Loading: https://developer.apple.com/design/human-interface-guidelines/loading
- Undo and redo: https://developer.apple.com/design/human-interface-guidelines/undo-and-redo
- Entering data: https://developer.apple.com/design/human-interface-guidelines/entering-data
- Offering help (tips): https://developer.apple.com/design/human-interface-guidelines/offering-help
- Managing accounts: https://developer.apple.com/design/human-interface-guidelines/managing-accounts
- Privacy (requesting permission): https://developer.apple.com/design/human-interface-guidelines/privacy
- Ratings and reviews: https://developer.apple.com/design/human-interface-guidelines/ratings-and-reviews
- Playing haptics: https://developer.apple.com/design/human-interface-guidelines/playing-haptics
- Motion: https://developer.apple.com/design/human-interface-guidelines/motion
- Accessibility: https://developer.apple.com/design/human-interface-guidelines/accessibility
- Typography: https://developer.apple.com/design/human-interface-guidelines/typography
- TipKit: https://developer.apple.com/documentation/tipkit
- WWDC25 "Get to know the new design system" (356): https://developer.apple.com/videos/play/wwdc2025/356/
- WWDC25 "Build a SwiftUI app with the new design" (323): https://developer.apple.com/videos/play/wwdc2025/323/
- Reminders grocery categories: https://support.apple.com/guide/reminders/remnbb50db03/mac
- 2025 Apple Design Awards (Mela finalist): https://www.apple.com/newsroom/2025/06/apple-unveils-winners-and-finalists-of-the-2025-apple-design-awards/
- 2024 Apple Design Awards (Crouton, Interaction): https://www.apple.com/in/newsroom/2024/06/apple-announces-winners-of-the-2024-apple-design-awards/

Nielsen Norman Group
- Designing empty states in complex applications: https://www.nngroup.com/articles/empty-state-interface-design/
- Mobile app tutorials study: https://www.nngroup.com/articles/mobile-tutorials/
- Icon usability: https://www.nngroup.com/articles/icon-usability/

App teardowns and reviews
- ScreensDesign, Mealime: https://screensdesign.com/apps/mealime-meal-plans-recipes/
- ScreensDesign, Eat This Much: https://screensdesign.com/apps/eat-this-much-meal-planner/
- ScreensDesign, Mise: https://screensdesign.com/showcase/mise-meal-planner
- ScreensDesign, Crouton: https://screensdesign.com/apps/crouton-recipe-manager/
- ScreensDesign, recipe app design examples: https://screensdesign.com/articles/recipe-app-design-examples/
- MacStories, Pestle 1.2: https://www.macstories.net/reviews/pestle-1-2-the-macstories-review/
- MacStories, Mela: https://www.macstories.net/reviews/mela-an-elegant-and-innovative-recipe-and-cooking-app-for-iphone-ipad-and-mac/
- MacStories, Crouton: https://www.macstories.net/reviews/crouton-review-an-elegant-modern-recipe-manager-and-cooking-aid/
- Mela: https://mela.recipes
- Crouton: https://crouton.app
- Paprika 3 (App Store): https://apps.apple.com/ng/app/id1303222868
- Ollie (App Store): https://apps.apple.com/us/app/ollie-ai-family-meal-planner/id6480014476
- Samsung Food changelog: https://APKMirror.com/apk/samsung-food/whisk-recipes-meal-planner/
- Samsung Food tablet redesign: https://www.sammobile.com/?p=16627727
- RecipeSage meal plans docs: https://docs.recipesage.com/docs/tutorials/meal-plans/usage/
- NotePlan horizontal week feedback (indirect): https://feedback.noteplan.co/board/p/horizontal-week-view

Complaints, pricing and market (vendor or aggregator; weaker evidence)
- unstar, recipe apps ranked: https://unstar.app/blog/allrecipes-yummly-nyt-cooking-paprika-mealime-recipe-apps-ranked-2026
- Plan to Eat on Mealime (competitor): https://www.plantoeat.com/?p=3689
- Plan to Eat on Eat This Much: https://www.plantoeat.com/blog/2023/10/eat-this-much-app-review-pros-and-cons/
- Plan to Eat on Yummly closing: https://www.plantoeat.com/blog/2024/12/yummly-is-closing-discover-the-best-meal-planning-alternative
- Mob reviews aggregator: https://grand-screen.com/apps/mob-delicious-meal-planning/reviews/
- Eat Together reviews: https://justuseapp.com/en/app/1627955204/eat-together-meal-planner/reviews
- Mealime reviews aggregator: https://justuseapp.com/en/app/1079999103/mealime-meal-plans-recipes/reviews
- Airbridge on hard vs soft paywalls: https://www.airbridge.io/blog/hard-vs-soft-paywalls
- RocketShip HQ (Adapty benchmarks): https://www.rocketshiphq.com/?p=6000
- SaaStr on RevenueCat report: https://www.saastr.com/the-top-10-learnings-from-revenuecats-state-of-subscription-apps/
- JMIR Mhealth 2021, family meal apps user testing (abstract only): https://pmc.ncbi.nlm.nih.gov/articles/PMC8140382/
- EveryBite allergen filtering guidance (vendor): https://docs.everybite.com/tutorials/allergen-filtering
- Banana shopping list (App Store): https://apps.apple.com/us/app/id6460372700
- Pantry/expiry app examples: https://apps.apple.com/app/id894059283
- Internal cross-references: docs/research/01-users-market-ux.md, 02-visual-identity.md, 03-accessibility.md, docs/BLUEPRINT.md
