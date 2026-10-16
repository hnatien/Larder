# Larder research 02: visual identity and design system

Researched 2026-10-16. Most "AI slop" sources are opinion pieces. Contrast ratios are WCAG 2 calculations by the researcher. Liquid Glass guidance comes from secondary summaries plus WWDC25 session 323.

## 1. What "AI-generated lookalike" means, and the opposite moves

Catalogue of tells (https://prg.sh/ramblings/Why-Your-AI-Keeps-Building-the-Same-Purple-Gradient-Website, https://www.925studios.co/blog/ai-slop-design-tells, https://impeccable.style/slop, https://noqta.tn/en/blog/ai-design-slop-overused-ui-patterns-fix-2026):
- Purple/indigo (traced to Tailwind UI's `bg-indigo-500` default), gradient text, glow halos, frosted-glass cards everywhere.
- Inter everywhere; Geist, Space Grotesk and Instrument Serif are the newer reflexes.
- Hairline border plus wide soft shadow; cards nested in cards; one oversized radius on everything; thick coloured stripe on one card edge; icons in rounded-square tiles above headings; identical icon-heading-text grids; "huge number, tiny label" hero metric; pulsing status dots; bounce easing on routine dialogs; em-dash overuse.
- Warning: the escape routes are the next cliché: cream/beige "tasteful" palette, italic-serif display headlines, small eyebrow labels. Distinctiveness must come from a specific idea executed everywhere, not from swapping one default for another.

Opposite moves: one central metaphor (the pantry shelf and the handwritten label); spot colour instead of a 50-900 ramp; real constraints (one display face, one mono, one illustration technique); hairline rules and tight unequal radii instead of shadows; content-specific components (jar-label stamp, masking-tape leftover tag, "eat first" shelf row); hand-drawn illustration, never stock bowls; copy with a point of view.

Recommendation: adopt the "pantry ledger and label" metaphor as the single organising idea. Ban purple, gradients, glow, gradient text, emoji icons, nested cards, card-per-row lists and stock food photos. Do not use cream + italic serif + eyebrow label as the signature.

## 2. Reference identities

| Reference | What reads as human |
|---|---|
| Mela | Per-platform care, typography, distinct dark mode; 2025 ADA finalist (https://www.macstories.net/reviews/mela-an-elegant-and-innovative-recipe-and-cooking-app-for-iphone-ipad-and-mac/) |
| Crouton | 2024 ADA Interaction winner; one step at a time, tappable ingredients inside steps, timers detected from text (https://www.macstories.net/reviews/crouton-review-an-elegant-modern-recipe-manager-and-cooking-aid/) |
| Pestle | Green accent only on measurements and key controls; room to breathe |
| Oddbox 2026 | Orange instead of eco green, oversized cropped newspaper type, screen-print produce icons on kraft (https://www.transformmagazine.net/articles/2026/oddbox-undergoes-playful-quirky-brand-refresh/) |
| Cook's Illustrated | Fixed cover template where only the food and colour vary; hand-drawn produce by John Burgoyne for 20 years (https://bobulate.com/2008/01/examining-the-ordinary/) |
| Monocle | Plantin as single serif, monochrome plus one signal yellow, rigid grid |
| Muji (Kenya Hara) | "Emptiness": restraint that leaves room for the user |
| Seed packets | Flat lithographic inks with halftone, one idealised specimen, strong top and bottom type |

Shared lessons: a rigid frame with one expressive variable; one illustration technique; a signal colour that is not the category cliché; specificity about material (kraft, print, ledger).

Recommendation: the Cook's Illustrated model. Fixed frame, one hand-made illustration per ingredient, one weekly seasonal spot colour.

## 3. Typography

Pairing A (recommended): Fraunces display + SF Pro text + Commit Mono labels.
- Fraunces: OFL-1.1 (https://github.com/undercasetype/Fraunces); axes weight, opsz 9-144, SOFT, WONK. Use upright weights 500-700, SOFT 50-100, WONK off, at 22pt and above. Never italic or light (the Instrument Serif tell).
- SF Pro for UI and body: system optical sizes, Dynamic Type, Bold Text free. Not a tell on iOS.
- Commit Mono: OFL-1.1 (https://commitmono.com); date stamps, quantities, use-by labels, uppercase tags. Check tabular figures before relying on them for columns.

Pairing B: Newsreader + Hanken Grotesk (quiet editorial; closer to the beige-serif cliché). Pairing C: New York + SF Pro + SF Mono (zero bundle, least distinctive).

Implementation caveats: SwiftUI `Font.Weight` cannot select arbitrary variable-font weights; ship static instances by name (cut with fontTools instancer). Use `Font.custom(name, size:, relativeTo:)` so custom fonts scale with Dynamic Type; `@ScaledMetric` for spacing. Cap display styles at `.accessibility2`; let body scale fully. Test Bold Text and AX5.

## 4. Colour

Concept: a shelf of tinned and painted things: flour-paper, brine-black ink, paprika, verdigris, mustard, beet. Not wellness green, no purple. Brand (paprika, hue 39) and danger (beet, hue 10) are different hues; status always carries an icon and a word; brand colour never means status.

Light mode (contrast vs canvas / raised / sunken):

| Token | Hex | Notes |
|---|---|---|
| surface/canvas | #F5F1E6 | paper |
| surface/raised | #FFFDF7 | cards, sheets |
| surface/sunken | #EBE5D4 | wells, inputs |
| line/hairline | #D6CEB8 | decorative only (1.39:1) |
| line/strong | #8C8570 | 3.26:1 on canvas, input outlines |
| ink/primary | #1F2620 | 13.7 / 15.2 / 12.3 |
| ink/secondary | #4F5448 | 6.9 / 7.7 / 6.2 |
| ink/tertiary | #5F6256 | 5.5 / 6.1 / 5.0 |
| accent/brand (paprika) | #A83F18 | 5.5 / 6.1 / 4.9; white on it 6.2 |
| accent/second (verdigris) | #2C6B5B | 5.5 / 6.1 / 5.0 |
| accent/spot (mustard, fill only) | #E3A82B | ink on it 7.3; never text |
| status/success | #2F6B34 | 5.7 / 6.3 / 5.1 |
| status/warning | #8A5700 | 5.4 / 6.0 / 4.9 |
| status/danger (beet) | #9C1F43 | 6.9 / 7.7 / 6.2 |
| status/info | #2F5D7C | 6.3 / 6.9 / 5.6 |

Dark mode (cast-iron green-black, not pure black):

| Token | Hex | Contrast |
|---|---|---|
| surface/canvas | #161915 | |
| surface/raised | #20241E | |
| surface/sunken | #10120F | |
| line/hairline | #363B32 | decorative |
| line/strong | #7C7866 | 4.0 / 3.55 / 4.25 (revised from #6E6A5A, which gave 2.91 on raised) |
| ink/primary | #F0ECDD | 15.0 / 13.3 / 15.9 |
| ink/secondary | #BDBAA8 | 9.1 / 8.1 / 9.6 |
| ink/tertiary | #9A9885 | 6.1 / 5.4 / 6.5 |
| accent/brand | #F0875A | 7.0 / 6.2 / 7.5; canvas ink on it 7.0 |
| accent/second | #6FC0A8 | 8.3 / 7.3 / 8.8 |
| accent/spot | #E3A82B | fill only |
| status/success | #8FCB84 | 9.3 / 8.3 / 9.9 |
| status/warning | #E5B04A | 9.0 / 8.0 / 9.5 |
| status/danger | #EE8CA6 | 7.6 / 6.7 / 8.0 |
| status/info | #8DB9D8 | 8.5 / 7.6 / 9.0 |

Food-group hues (graphics, at least 3:1, always with a text label; grains is tightest at 3.15:1 so keep bars 6pt+):

| Group | Light | Dark |
|---|---|---|
| food/produce | #4A8A3C | #86C46F |
| food/grains | #B07F1E | #E0AE4A |
| food/protein | #3E6F8E | #78AECF |
| food/dairy | #B05A78 | #E48FAE |
| food/fats | #76772A | #B9BA52 |
| food/legumes | #8A5A3A | #C99572 |

Token naming: `group/role` (surface, ink, line, accent, status, food) plus `ink/on-accent`.

Liquid Glass: belongs on navigation and controls, not content (WWDC25 session 323, https://developer.apple.com/videos/play/wwdc2025/323/). Glass for tab bars, toolbars, sheets, floating buttons; no glass on glass; content surfaces stay opaque paper; only the primary floating action takes brand tint; no long text on glass. Infinum measured 1.5:1 contrast on some glass screens; Apple added a Tinted option in 26.1 (https://infinum.com/blog/apples-ios-26-liquid-glass-sleek-shiny-and-questionably-accessible/).

## 5. Shape, texture and motion

- Radius scale: 2 (tags/stamps), 8 (inputs/chips), 12 (cards), 24 (sheets), pill (glass controls only). Nest concentrically with the system.
- Hairline ledger rule plus a flat tint step; no shadows on content cards; never nest cards.
- No grain on the app background (the default "atmospheric noise" everyone will have). Ink texture only on illustrations.
- Illustration: single-ink produce in screen-print/risograph style, two spot colours (paprika, verdigris) plus mustard. 40-60 core ingredients plus empty states. No mascots, no blob masks.
- Icons: SF Symbols for chrome; custom SF Symbols for food groups; no emoji.
- Photography: only the user's own and imported-recipe photos; 4:5, 8pt corners, no overlays; treated as "plated evidence".
- Motion: 120ms state, 220ms navigation, 360ms sheet. `.snappy` for taps, `.smooth` for layout, one `.bouncy` for the "stamped" save. No pulsing, looping or parallax. Under Reduce Motion: crossfade or 100-150ms ease-out, no bounce; pair with haptics.

## 6. Information design

- No daily calorie total by default; calories behind an opt-in toggle. Show the week, not the day.
- "Week shelf" strip: stacked bands by food group with a dotted bracket for a comfortable range; never a target line, never red. Copy states a gap and offers a swap: "Light on greens this week. Two dinners could take a handful."
- Week plan as a ledger: one row per day, a jar-label tag per meal, hairline between days; today marked by a paprika tab on the left edge; leftovers visually linked to the cook that produced them.
- Freshness: stamped date plus a word plus tone. Fresh is plain ink, "soon" is mustard, "today" is paprika. An "Eat first" top shelf. Leftovers use a masking-tape label: "Tue's chilli, day 2 of 4." Swipe to mark eaten or let go. At most one daily expiry nudge.
- Recommendations read like a friend: one sentence of reason, one alternative, one-tap veto.
- Data-light precedents: Gentler Streak (compares only with your own history), Apple Vitals (typical range), Ate (photo-first, feelings not calories), ShelfLife's Eat First shelf, Crouton cooking mode.

## 7. Voice and microcopy

Dry and plain. No exclamation marks, no em dashes, no hype, no moralising about food. Contractions fine; never joke on errors, allergen warnings or paywall.

Seed strings:
1. Empty pantry: "Nothing on the shelves yet. Add what you have and we'll plan around it."
2. First plan: "Here's your week. Two nights use up the spinach."
3. Expiring: "Spinach is best by Thursday. Dinner tonight uses it."
4. Expired today: "The yoghurt is at its limit today. Eat it, or let it go."
5. Leftover tag: "Chilli, day 2 of 4."
6. Light on a group: "Light on greens this week. A handful in two dinners would do it."
7. Veto: "Fair. Here's another that uses the same ingredients."
8. Plan saved: "Stamped. The week is yours."
9. Paywall: "Planning one week is free. Larder Plus plans the month and watches your shelf." with "Not now" as an equal-weight button.
10. Offline: "Couldn't reach the server. Your plan is saved here and will sync later."

## Design brief (ready for the SwiftUI module)

Idea: a pantry ledger. Paper, ink, stamped labels, a shelf. Not a dashboard.

Typography: Fraunces static (upright, 500-700) for display `relativeTo .largeTitle/.title`, capped at `.accessibility2`; SF Pro for body and UI; Commit Mono Regular for stamps `relativeTo .caption`, uppercase, +0.04em tracking.

Spacing (4pt base): 2, 4, 8, 12, 16, 24, 32, 48, 64. Radius: 2 / 8 / 12 / 24 / pill.

Surfaces: opaque paper, hairline rules, flat tint steps, no shadows, no nested cards. Glass only on navigation and floating controls, brand tint on at most one control per screen.

Open items: commission the illustration set; test the Fraunces static-instance pipeline and Commit Mono tabular figures; verify `line/strong` dark on device; verify Liquid Glass API names against current docs.
