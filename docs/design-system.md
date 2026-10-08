# Design system

How PDF Algo Pro looks, moves and reads: the principles, tokens, components and accessibility rules
that every screen follows, and how they are implemented and governed in code. The design system is
native Apple first. It uses Apple's system colours, type, materials and components, and applies the
Algorythmos brand only as an accent. Anything a feature needs that is not here is proposed as a change
to this document and to the `DesignSystem` package in the same pull request.

Owner: Design · Reviewed: each milestone, and whenever a token or component changes

## Summary

| Area | Decision |
|---|---|
| Foundation | Apple's [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) (HIG) first; system components before custom ones ([ADR-0022](adr/0022-apple-first-capability-baseline.md)) |
| Materials | Liquid Glass only in the control layer (toolbars, page indicator, tab and sidebar chrome); standard materials in the content layer |
| Colour | Semantic tokens mapped to system colours; the product's red as the app accent and brand cyan as the intelligence marker, each with light, dark and Increase Contrast variants |
| Type | SF Pro through system text styles, full Dynamic Type up to AX5; no bundled fonts |
| Spacing | 8-point grid with 4-point half-steps, named tokens |
| Motion | One `Motion` helper that honours Reduce Motion; one `Haptics` helper over system feedback |
| Accessibility | WCAG 2.2 AA contrast in every appearance, VoiceOver rotors for headings and pages, 44-point targets, Voice Control names, full keyboard |
| Source of truth | `tokens.json` in the repository generates the `DesignSystem` package; parity and contrast tests fail CI on drift |

## Principles

1. **Native, by the HIG.** Standard SwiftUI components and behaviours first. A custom component
   exists only when no system component does the job, and it must behave like one (focus, Dynamic
   Type, VoiceOver, keyboard, Reduce Motion). This is how the product meets the Apple-first mandate
   in [founder principles](founder-principles.md) (principle 2).
2. **Content first.** The document is the interface. Chrome recedes while reading; controls float
   above the page and can be hidden and reliably restored, as the HIG recommends for distraction-free
   views ([Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)).
3. **Liquid Glass for controls, never for content.** Liquid Glass "forms a distinct functional layer
   for controls and navigation elements"; the HIG says not to use it in the content layer and to use
   it sparingly on custom controls ([Materials](https://developer.apple.com/design/human-interface-guidelines/materials)).
   System toolbars, sidebars and sheets get it automatically. Our only custom glass surfaces are the
   floating page indicator and the reader's floating tool strip. AI answer cards, library cards and
   the paywall sit in the content layer and use standard materials or grouped backgrounds.
4. **SF Symbols for every icon.** Symbols scale with Dynamic Type and adapt to appearance and
   accessibility settings when drawn with system colours
   ([SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)). A custom
   symbol is drawn as an SF Symbols template only when no system symbol fits (for example a
   redaction mark), and it ships with all weights.
5. **Brand as an accent, with a few signature moments.** Red marks what is interactive and cyan
   marks what the intelligence layer produced. Everything else is system colour: screens are white
   or the system's grouped grey in light and the system's dark backgrounds in dark, never a red
   surface or a red navigation bar ([PAP-047](decision-register.md)). The brand is also
   shown, on purpose and in few places (PAP-040): Home carries the app mark, a soft wash of the brand
   tint behind its header (`BrandGlow`) and, in its footer, the company mark with "Built by
   Algorythmos"; Settings and About carry the app mark and the company mark. Screens where people
   work on a document (the reader, the assistant, the scanner) carry none of these, and there
   what is selected or being edited is `color.selection`, the system's blue: on a document, red is
   an annotation colour and the colour of Delete.
6. **Honest interface.** Generated text is always labelled and never styled as document text; the
   tier that answered is always visible; paywalls close in one action from the moment they appear.
   These follow founder principles
   4, 5 and 10.
7. **Accessible by default.** Accessibility is a requirement of every component, tested in CI, not
   a pass at the end ([testing strategy](testing-strategy.md)).

**Why this matters for switching, paying and staying.** A native, calm, accessible interface is
part of the product's case against cross-platform competitors ([competitive moat](competitive-moat.md)):
people switch for a better everyday experience, pay when intelligence is trustworthy (citations,
visible tiers), and stay when nothing gets in the way of their documents. Restraint with new
materials is deliberate: recent public App Store reviews of one Apple-only competitor include
requests to turn off its iOS 27 Liquid Glass redesign (small, negative-skewed sample;
[PDF Expert customer reviews feed](https://itunes.apple.com/us/rss/customerreviews/page=1/id=743974925/sortBy=mostRecent/json)).

## Colour

### Semantic tokens

Screens never use raw colour values. They use semantic tokens, and most tokens resolve to Apple's
dynamic system colours, which already carry light, dark and Increase Contrast variants
([Color](https://developer.apple.com/design/human-interface-guidelines/color)). The HIG asks apps not
to redefine the meaning of dynamic system colours, so each token keeps the system colour's purpose.

| Token | Resolves to | Use |
|---|---|---|
| `color.background.primary` | `systemBackground` | Screen background |
| `color.background.secondary` | `secondarySystemBackground` | Grouped content inside a screen |
| `color.background.grouped` | `systemGroupedBackground` | Settings and form backgrounds |
| `color.background.groupedElevated` | `secondarySystemGroupedBackground` | Rows and cards on grouped backgrounds |
| `color.label.primary` | `label` | Primary text |
| `color.label.secondary` | `#5E5E66` light, `#A1A1A8` dark (`#45454C` / `#C4C4CC` with Increase Contrast), not `secondaryLabel`, which is 3.3:1 on grouped backgrounds; at least 4.5:1 on every system background | Supporting text, including empty states (`EmptyState`, not `ContentUnavailableView`) |
| `color.label.tertiary` | `tertiaryLabel` | Disabled text and placeholders only |
| `color.separator` | `separator` | Dividers |
| `color.fill.primary` / `.secondary` / `.tertiary` | `systemFill` family | Control fills |
| `color.status.success` | `systemGreen` | Success, always with a symbol |
| `color.status.warning` | `systemOrange` | Warnings, always with a symbol |
| `color.status.error` | `systemRed` | Errors and destructive actions, always with a symbol |
| `color.link` | `link` | Inline links in help text |
| `color.selection` | `systemBlue` | What is selected or being edited on a document: the outline of a selected annotation, the outlines of editable text, the editing field's rule and caret, the current and the selected pages in Pages |
| `color.brand.tint` | Brand red (below) | App accent colour: interactive text, selected state, borderless buttons |
| `color.brand.fill` / `color.brand.onFill` | Brand red fill and its label colour | Prominent buttons |
| `color.intelligence.tint` | Brand cyan (below) | Markers for AI-generated content: tier badge, citation chips |
| `color.intelligence.fill` / `color.intelligence.onFill` | Cyan fill and its label colour | Selected citation chip |
| `color.page.background` | The PDF's own rendering | Never tinted; pages render as authored |

Rule: the brand red always means "you can act on this"; cyan always means "the intelligence layer
produced this". The HIG warns against using one colour to mean different things
([Color](https://developer.apple.com/design/human-interface-guidelines/color)).

**Red and destructive actions.** The brand red and the red of destructive actions are almost the
same colour (`#C41230` and `color.system.destructiveText` `#C2181F` are 1.01:1 against each other),
so colour cannot tell them apart and nothing relies on it to. A destructive action always has the
system's destructive role, a symbol or a verb that names the loss ("Delete"), and a confirmation
when it cannot be undone. A filled red button is never a destructive action, and a bar that holds
a destructive action keeps its other labels plain (the reader's selection bar sets its tint to the
label colour).

### Brand and accent tokens

The red is the product's own ([PAP-047](decision-register.md)); it replaced the organisation's
violet on 2026-10-07. The cyan and the company mark still come from the company website's design
tokens (organisation brand standard). The cyan's Increase Contrast variants are **proposed here**;
the brand source does not define them (see open questions).

| Token | Light | Dark | Light, Increase Contrast | Dark, Increase Contrast |
|---|---|---|---|---|
| `color.brand.tint` | `#C41230` | `#FF6F7D` | `#881337` | `#FDA4AF` |
| `color.brand.strong` | `#A30F28` | `#FB4F64` | `#881337` | `#FDA4AF` |
| `color.brand.fill` | `#C41230` | `#FF6F7D` | `#881337` | `#FDA4AF` |
| `color.brand.onFill` | `#FFFFFF` | `#08080C` | `#FFFFFF` | `#000000` |
| `color.intelligence.tint` | `#0E7490` | `#22D3EE` | `#155E75` | `#67E8F9` |
| `color.intelligence.fill` | `#0E7490` | `#22D3EE` | `#155E75` | `#67E8F9` |
| `color.intelligence.onFill` | `#FFFFFF` | `#08080C` | `#FFFFFF` | `#000000` |
| Website background (reference only) | `#FAFAF9` | `#08080C` | — | — |
| Website text (reference only) | `#111218` | `#F4F4F7` | — | — |
| `color.logo.mark` (company mark, letterform) | `#3715E0` | same | same | same |
| `color.logo.dotStart` → `color.logo.dotEnd` (company mark, dot) | `#4A18E8` → `#8420F5` | same | same | same |
| `color.logo.tile` (the tile the company mark sits on) | `#FFFFFF` | same | same | same |

The website backgrounds and text colours are listed for reference and marketing surfaces (App Store
screenshots, the support site). Inside the app, backgrounds and text use the system tokens above.

The company mark's colours and outline are those of the logo the company publishes on its website
(`public/bimi/algorythmos.svg` in the website's public repository, read on 2026-10-06). They are
the same in every appearance, and `color.logo.*` is used by `CompanyMark` only. `opacity.brandGlow`
(0.1) is the most brand tint `BrandGlow` lays over a background: measured in the design-system
tests, primary and secondary text over it keep at least 4.5:1 in all four appearances.

### Measured contrast

Ratios below were calculated with the WCAG 2.2 relative-luminance formula
([WCAG 2.2, contrast minimum](https://www.w3.org/TR/WCAG22/#contrast-minimum)) and are recomputed by
the parity tests. Thresholds follow the HIG, which applies WCAG AA: 4.5:1 for text up to 17 points,
3:1 for text of 18 points or more and for bold text
([Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)), and
3:1 for user-interface components and meaningful graphics
([WCAG 2.2, non-text contrast](https://www.w3.org/TR/WCAG22/#non-text-contrast)).

`Assumption:` resolved sRGB values of the iOS dynamic backgrounds are `#FFFFFF` (systemBackground,
light), `#F2F2F7` (secondarySystemBackground, light), `#E5E5EA` (a common light fill), `#000000`
(systemBackground, dark), `#1C1C1E`, `#2C2C2E` and `#3A3A3C` (dark secondary, tertiary and elevated
surfaces). Apple does not publish these values in the HIG; the parity test resolves them on device
and recomputes every ratio, so a difference fails the build rather than going unnoticed.

**Website tokens on their own theme backgrounds (reference; the brand red is not a website colour)**

| Foreground | Background | Ratio | Body text (4.5:1) | Large text and UI (3:1) |
|---|---|---|---|---|
| Dark text `#F4F4F7` | `#08080C` | 18.21:1 | Pass | Pass |
| Dark accent `#22D3EE` | `#08080C` | 11.06:1 | Pass | Pass |
| Light text `#111218` | `#FAFAF9` | 17.90:1 | Pass | Pass |
| Light accent `#0E7490` | `#FAFAF9` | 5.13:1 | Pass | Pass |

**Brand tokens on iOS system backgrounds (how the app actually uses them)**

| Foreground | Background | Ratio | Body text | Large text and UI |
|---|---|---|---|---|
| Light brand `#C41230` | `#FFFFFF` | 6.04:1 | Pass | Pass |
| Light brand `#C41230` | `#F2F2F7` | 5.41:1 | Pass | Pass |
| Light brand `#C41230` | `#E5E5EA` | 4.81:1 | Pass | Pass |
| Light brand-strong `#A30F28` | `#FFFFFF` | 7.91:1 | Pass | Pass |
| Light brand-strong `#A30F28` | `#F2F2F7` | 7.08:1 | Pass | Pass |
| Light accent `#0E7490` | `#FFFFFF` | 5.36:1 | Pass | Pass |
| Light accent `#0E7490` | `#F2F2F7` | 4.80:1 | Pass | Pass |
| Light accent `#0E7490` | `#E5E5EA` | 4.27:1 | **Fail** | Pass |
| Dark brand `#FF6F7D` | `#000000` | 7.82:1 | Pass | Pass |
| Dark brand `#FF6F7D` | `#1C1C1E` | 6.34:1 | Pass | Pass |
| Dark brand `#FF6F7D` | `#2C2C2E` | 5.19:1 | Pass | Pass |
| Dark brand `#FF6F7D` | `#3A3A3C` | 4.23:1 | **Fail** | Pass |
| Dark brand-strong `#FB4F64` | `#000000` | 6.40:1 | Pass | Pass |
| Dark brand-strong `#FB4F64` | `#1C1C1E` | 5.19:1 | Pass | Pass |
| Dark brand-strong `#FB4F64` | `#2C2C2E` | 4.25:1 | **Fail** | Pass |
| Dark accent `#22D3EE` | `#000000` | 11.62:1 | Pass | Pass |
| Dark accent `#22D3EE` | `#1C1C1E` | 9.42:1 | Pass | Pass |
| Dark accent `#22D3EE` | `#2C2C2E` | 7.71:1 | Pass | Pass |

**Labels on filled controls**

| Label | Fill | Ratio | Body text | Large text and UI |
|---|---|---|---|---|
| `#FFFFFF` | Light brand `#C41230` | 6.04:1 | Pass | Pass |
| `#FFFFFF` | Light brand-strong `#A30F28` | 7.91:1 | Pass | Pass |
| `#FFFFFF` | Dark brand `#FF6F7D` | 2.68:1 | **Fail** | **Fail** |
| `#FFFFFF` | Dark brand-strong `#FB4F64` | 3.28:1 | **Fail** | Pass |
| `#08080C` | Dark brand `#FF6F7D` | 7.45:1 | Pass | Pass |
| `#FFFFFF` | Light accent `#0E7490` | 5.36:1 | Pass | Pass |
| `#FFFFFF` | Dark accent `#22D3EE` | 1.81:1 | **Fail** | **Fail** |
| `#08080C` | Dark accent `#22D3EE` | 11.06:1 | Pass | Pass |

**Increase Contrast variants (the cyan values are proposed)**

| Foreground | Background | Ratio |
|---|---|---|
| `#881337` | `#FFFFFF` / `#F2F2F7` / `#E5E5EA` | 9.57:1 / 8.57:1 / 7.62:1 |
| `#FDA4AF` | `#000000` / `#1C1C1E` / `#2C2C2E` | 11.11:1 / 9.00:1 / 7.37:1 |
| `#155E75` | `#FFFFFF` / `#F2F2F7` | 7.27:1 / 6.51:1 |
| `#67E8F9` | `#000000` / `#1C1C1E` | 14.49:1 / 11.74:1 |
| `#FFFFFF` on `#881337`; `#000000` on `#FDA4AF` | — | 9.57:1; 11.11:1 |

**Tokens used in the wrong appearance, and the logo**

| Foreground | Background | Ratio | Result |
|---|---|---|---|
| Light brand `#C41230` | Dark `#08080C` | 3.31:1 | **Fail** |
| Dark brand `#FF6F7D` | Light `#FAFAF9` | 2.57:1 | **Fail** |
| Dark accent `#22D3EE` | Light `#FAFAF9` | 1.73:1 | **Fail** |
| Logo `#6D00FF` | `#FAFAF9` / `#08080C` / `#000000` | 6.50:1 / 2.95:1 / 3.09:1 | Below 3:1 on `#08080C` |
| Logo `#7658E7` | `#FAFAF9` / `#08080C` / `#000000` | 4.65:1 / 4.11:1 / 4.32:1 | Above 3:1 |

### Colour rules from the measurements

1. **The brand red passes AA for body text on every primary, secondary and grouped system
   background, in all four appearances** (lowest: light on `#E5E5EA`, 4.81:1). The design-system
   tests resolve the system backgrounds on the device and check it.
2. **Dark brand-strong `#FB4F64` is not a body-text colour in the app.** It fails on the dark
   tertiary surface (4.25:1). It is limited to large text (18 points or more, or bold), symbols
   and focus rings; body text uses `color.brand.tint`.
3. **Dark prominent buttons use a dark label.** White on `#FF6F7D` is 2.68:1 and white on
   `#FB4F64` is 3.28:1. `color.brand.onFill` is `#08080C` in dark (7.45:1). The same applies to the
   cyan fill (white on `#22D3EE` is 1.81:1). `PrimaryButton` sets the label colour explicitly; the
   default white label of a tinted system button is never relied on in dark.
4. **No brand text on the darkest elevated fills.** Dark brand `#FF6F7D` on `#3A3A3C` is 4.23:1 and
   light accent `#0E7490` on `#E5E5EA` is 4.27:1. Tinted text sits on primary, secondary or grouped
   backgrounds only; on fills, use `color.label.primary` with a tinted symbol.
5. **Tokens always resolve per appearance.** Used in the wrong appearance, the brand colours fail
   (1.73:1 to 3.31:1). Tokens are dynamic colours with all four variants, generated from
   `design/tokens.json`; the app's accent colour in the asset catalog is written by the same
   generator, whose check fails when the two differ. A single hex value in feature code is blocked
   by the `invariants` gate.
6. **Liquid Glass changes contrast.** Tinted glass takes colour from content behind it
   ([Color, Liquid Glass color](https://developer.apple.com/design/human-interface-guidelines/color)).
   The two custom glass controls are snapshot-tested over light pages, dark pages and photographs;
   where a label falls below 4.5:1, the control switches to an opaque style.
7. **The logo is decoration, not text, and always sits on its light tile.** WCAG exempts logotypes
   from the text-contrast rule, but the mark's violet falls below 3:1 on dark backgrounds. So
   `CompanyMark` draws it on `color.logo.tile` in every appearance (PAP-040): `color.logo.mark` on
   the tile is a declared contrast pair of at least 4.5:1 in `tokens.json`, checked in CI.
8. **Colour is never the only signal.** Status, selection, annotation colour and OCR confidence
   always carry a shape, symbol or text, as the HIG requires
   ([Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)).

### Annotation colours

Highlight, pen and shape colours are the user's content, not brand. The palette is six named colours
(yellow, green, blue, pink, orange, purple) plus a custom colour. Each has a spoken name for VoiceOver
and Voice Control ("Yellow highlight"). Highlights are drawn as translucent overlays so the text
underneath keeps its contrast; the parity test checks black text under each highlight at its
default opacity stays at 4.5:1 or more on a white page. `Assumption:` six colours are enough for
common review workflows; validated in usability sessions ([customer research](customer-research.md)).

### Decision: brand as accent over system colours

**Rationale.** The HIG recommends system colours because they adapt automatically to appearance and
Increase Contrast, and suggests a brand colour as the app accent in apps with mostly monochromatic
content ([Color](https://developer.apple.com/design/human-interface-guidelines/color)). PDFs are
colourful content, so the chrome stays neutral and the accent does the brand work.
**Trade-offs.** Less brand presence than a fully branded theme; two extra colour families
(red and cyan) to keep meaningful. **Alternatives considered.** A fully branded dark theme like
the website (fights document colours, loses system adaptivity, more contrast risk). System blue with
no brand (loses identity). Solid red navigation bars on every screen, as other apps in the category
have (a pattern from other platforms that fights Liquid Glass and puts red chrome over documents).
**Risks.** The brand red is the colour of destructive actions; mitigated by the rule above and by
keeping red off working screens. A red app in a category of red apps is less distinct than the
violet was; the icon's sparkle and the cyan marker carry the difference. **Future scalability impact.** The same tokens carry to
iPad, Mac and visionOS; Mac honours the user's own accent colour when it is not "multicolour"
([Color](https://developer.apple.com/design/human-interface-guidelines/color)), which the Mac adapter
allows. **Pillars served.** PIL-7 Native Apple Experience.

## App icon

Version 3: the artwork of version 2 (approved by the owner on 2026-10-01) on a red field, decided
on 2026-10-07 ([PAP-047](decision-register.md)). `scripts/design/make_app_icon.swift` draws it from
`design/tokens.json` and writes both icon sets; never edit the PNGs by hand.

| Element | Default appearance | Dark | Tinted |
|---|---|---|---|
| Field | Diagonal gradient, top left to bottom right: `color.icon.gradientStart` `#FF5468`, `color.icon.gradientMid` `#E11D48` at 55%, `color.brand.tint` `#C41230` | Transparent (the system draws it) | Transparent |
| Page, 61% of the width, with a folded corner | White; fold `color.icon.fold` `#FECDD3` | The field gradient | White |
| "PDF" mark and the rule under it | `color.brand.tint` | Cut out of the page | Cut out of the page |
| Sparkle over the top-left corner of the page | `color.intelligence.tint` (dark value) with a white ring | The same, with a cut-out ring | Grey |
| Beta badge (Staging only) | `color.icon.stagingBadge` `#F59E0B` pill with a white "β" | The same | White pill, cut-out "β" |

- **Why a red field.** Observation (App Store search for "pdf editor", iPhone, 2026-10-01): every
  result above the fold used a red icon with a large page or a "PDF" mark. Version 2 ended its
  field in the brand violet to differ from them; with the brand now red, the field is red
  throughout, lighter at the top left and deepest at the bottom right. What is meant to set the
  icon apart now is the cyan sparkle with its white ring.
- **Assumption:** a red icon with the sparkle is recognised as a PDF app and is still told apart
  from the others. Validation plan: the alternate-icon test in the
  [App Store strategy](app-store-strategy.md) once the app is live.
- **The icon colours are for the icon only.** `color.icon.*` never appears in the interface as a
  colour; there, the brand red means "you can act on this" and cyan means the intelligence
  layer. The icon itself does appear, as an image: `AppMark` shows it on Home, in Settings and in
  About (PAP-040). The script writes that image (`AppMark.png` in the `DesignSystem` package) from
  the same artwork, and the `invariants` gate checks it is there.
- **The "PDF" mark is drawn as paths**, not set in a font, so the icon depends on no font licence.
- **Staging** (`AppIcon-Staging`) is the same artwork with the beta badge, selected by the Staging
  build configuration in `project.yml`.
- **Liquid Glass.** The script also writes an Icon Composer document for each set (`AppIcon.icon`,
  `AppIcon-Staging.icon`) with the page, the sparkle and the badge as separate glass layers over a
  red fill. The build uses the document, and iOS draws the dark, tinted and clear
  appearances from it. An Icon Composer fill takes two colours and runs top to bottom, so there the
  field goes from `color.icon.gradientStart` straight to `color.brand.tint` without the middle stop.
- `scripts/ci/invariants.py` checks that the default image of each set is an opaque 1024 × 1024 PNG
  and that each Icon Composer document has all its layer images.

## Typography

- **SF Pro through system text styles only.** Text styles give Dynamic Type and the accessibility
  sizes automatically ([Typography](https://developer.apple.com/design/human-interface-guidelines/typography)).
  No fonts are bundled in the app. Numerals in tables use monospaced digits (`.monospacedDigit()`).
- **Full Dynamic Type, including AX1–AX5.** At AX5, Body is 53 points and Large Title 60 points
  (HIG iOS type tables); every screen is designed and snapshot-tested at the default size (Large) and
  at AX5.
- **Custom dimensions scale too.** Icon sizes, thumbnail heights and spacing next to text use
  `@ScaledMetric`, so layout grows with text.
- **Bars do not grow without limit.** Toolbar and tab-bar items keep their size and offer the Large
  Content Viewer (`accessibilityShowsLargeContentViewer()`), as system bars do.
- **Text never truncates meaning.** Labels wrap; horizontal groups switch to vertical with
  `ViewThatFits` when they no longer fit.

| Text style | Size at Large (default) | Size at AX5 | Used for |
|---|---|---|---|
| Large Title | 34 pt | 60 pt | Library title |
| Title 1 / Title 2 / Title 3 | 28 / 22 / 20 pt | 58 / 56 / 55 pt | Introduction headlines, paywall header, section titles |
| Headline | 17 pt semibold | 53 pt | Card titles, list row titles |
| Body | 17 pt | 53 pt | AI answers, settings, dialogs |
| Callout | 16 pt | 51 pt | Intent picker descriptions |
| Subheadline | 15 pt | 49 pt | Metadata (page count, modified date) |
| Footnote | 13 pt | 44 pt | Disclosures ("Not legal advice"), subscription terms |
| Caption 1 / Caption 2 | 12 / 11 pt | 43 / 40 pt | Citation chips, badges |

Sizes from the HIG's iOS and iPadOS Dynamic Type tables
([Typography, specifications](https://developer.apple.com/design/human-interface-guidelines/typography)).
The HIG minimum text size on iOS is 11 points
([Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)).
Subscription terms and legal disclosures never go below Footnote.

The PDF page itself has fixed layout and does not follow Dynamic Type; readers enlarge it with zoom,
and VoiceOver reads its text layer (see the accessibility section below).

**Decision: no custom fonts.** **Rationale.** System fonts support Dynamic Type, Bold Text and
every script the product will localise into without extra work
([Typography](https://developer.apple.com/design/human-interface-guidelines/typography)).
**Trade-offs.** Less typographic brand distinction than the website. **Alternatives considered.** The
website's typeface in headings (licensing, Dynamic Type and localisation work for little user value).
**Risks.** A typed signature needs a script-style face: it uses a typeface already installed on the
system, never a bundled font (open question). **Future scalability impact.** Mac and visionOS use
their own system text styles with no code change. **Pillars served.** PIL-7.

## Spacing

An 8-point grid with 4-point half-steps. Tokens are named on a numeric scale where `100` is one grid
unit, so new steps can be added without renaming.

| Token | Points | Typical use |
|---|---|---|
| `space.0` | 0 | Flush elements |
| `space.050` | 4 | Icon-to-label gap, chip padding |
| `space.100` | 8 | Gap between related items |
| `space.150` | 12 | Padding around bezelled controls |
| `space.200` | 16 | Card inset, standard content margin on compact width |
| `space.300` | 24 | Section spacing; padding around controls without a bezel |
| `space.400` | 32 | Group spacing on regular width |
| `space.500` | 40 | Onboarding and paywall vertical rhythm |
| `space.600` | 48 | Large empty-state spacing |
| `space.800` | 64 | Hero spacing on regular width |

Semantic aliases keep intent readable: `space.inset.card` = `space.200`, `space.gap.inline` =
`space.100`, `space.stack.section` = `space.300`, `space.target.padding` = `space.150`. The 12- and
24-point values match the HIG's advice on padding around bezelled and unbezelled controls
([Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)).

Other size tokens: `size.target.minimum` = 44 × 44 points (the HIG default control size on iOS);
corner shapes use the system's concentric shapes (`ConcentricRectangle`) so custom cards nest
correctly inside system containers, rather than fixed radius tokens.

Rules: system components keep their own spacing; tokens apply to our layouts. Spacing next to text
uses `@ScaledMetric` so it grows with Dynamic Type. Values off the grid are rejected in review.

## Layout

- **Size classes and available space, never device type.** The HIG says to base layout on size
  classes, not device or orientation ([Layout](https://developer.apple.com/design/human-interface-guidelines/layout)).
  iOS 27 lets iPhone apps resize (for example in iPhone Mirroring and on iPad), so an iPhone layout
  must work at any width ([What's new in SwiftUI, WWDC26](https://developer.apple.com/videos/play/wwdc2026/269/)).
- **Split-view shell.** `NavigationSplitView` collapses to a stack in compact width and expands to
  two or three columns in regular width ([ADR-0004](adr/0004-navigation-and-multi-window.md)).
- **Readable width.** Long text (AI answers, help, settings footers) is limited to the readable
  content width that UIKit computes from the current text size (`readableContentGuide`), exposed as a
  `readableWidth()` modifier. PDF pages are never constrained.
- **Safe areas.** Content scrolls under Liquid Glass bars with the system scroll-edge effect; nothing
  interactive sits in unsafe areas.
- **Right-to-left ready.** Leading and trailing, never left and right; directional symbols mirror.
  English and French ship first, but layouts are tested with right-to-left pseudo-language.
- **Localisation headroom.** Layouts are tested with French and with double-length
  pseudo-localisation. `Assumption:` French strings run about 20–30% longer than English;
  pseudo-localisation covers the worst case.

| Screen | Compact width | Regular width |
|---|---|---|
| Library | Opens on Home, the first level of the stack: the app mark, quick actions, recent documents, then the sections with their counts. A section's list is one step in; search in its toolbar | Sidebar (sections with counts, tags) + grid or list. The Home extras are not shown: beside the documents it stays a sidebar |
| Reader | Page fills the screen; thumbnail strip on demand at the bottom | Thumbnail rail in a leading column; inspector for annotations and AI answers in a trailing column |
| Assistant (AI) | Sheet with detents over the page | Trailing inspector next to the page, so citations and page stay visible together |
| Onboarding, paywall | Single column, scrolls | Centred single column at readable width |

## Components

Every component lives in the `DesignSystem` package, has previews for light, dark, Increase
Contrast, Large and AX5, and has snapshot and accessibility tests before it is marked stable.

### Buttons

| Component | Built on | Rules |
|---|---|---|
| `PrimaryButton` | In bars, the design system's own capsule (`PrimaryBarButtonStyle`): the system's `.glassProminent` chooses its label colour itself and in dark mode that colour fails colour rule 3. `.borderedProminent` in content | One per screen. `color.brand.fill` with `color.brand.onFill` label. Label is a verb plus object ("Scan document"); in a bar, where width is scarce and the object is the document on screen, the verb alone ("Edit") |
| `SecondaryButton` | `.glass` in bars; `.bordered` in content | Alternatives to the primary action |
| `TertiaryButton` | Borderless, `color.brand.tint` | Low-emphasis actions, "Not now" |
| `DestructiveButton` | `role: .destructive` | System red; confirmation for anything not undoable |
| `IconButton` | SF Symbol, borderless | 44 × 44 point hit area; accessibility label and Voice Control input labels always set |

| `QuickAction` | A tile: an SF Symbol over a short title, on a card, or on `color.brand.fill` when filled | Home's few starting actions. At most one filled tile on a screen, and it counts as that screen's `PrimaryButton`. At accessibility text sizes the symbol moves beside the title and the tiles stack |

The HIG applies the accent colour to the background of prominent buttons and warns against colouring
many controls ([Color, Liquid Glass color](https://developer.apple.com/design/human-interface-guidelines/color)).
Equal-weight buttons are used where the choice must not be steered: consent screens and the
telemetry prompt present "Share" and "Not now" with the same style.

### Cards

Cards group related content in the content layer: document cards in the library grid, AI answer
cards, onboarding intent options. They use `color.background.groupedElevated` or a standard material,
`space.inset.card` padding and concentric corners. A card is a single accessibility element with a
combined label unless it contains more than one action, in which case each action is reachable and
also offered as a custom accessibility action.

### Brand marks and tiles

| Component | What it is | Rules |
|---|---|---|
| `AppMark` | The app icon as an image, with the icon's corner shape | Home's header, Settings and About only. Decoration beside the app's name, so hidden from VoiceOver. Grows with the text size, to one and a half times its size |
| `CompanyMark` | The Algorythmos mark, drawn as a vector shape, on `color.logo.tile` | Home's footer and About only, beside "Built by Algorythmos". Never without its tile, never recoloured, never mirrored in right-to-left layouts. VoiceOver reads "Algorythmos" |
| `BrandGlow` | A wash of `color.brand.tint`, strongest at the top (`opacity.brandGlow`) and gone at its lower edge | Behind Home's header only, in compact width. Removed by Reduce Transparency and by Increase Contrast. Never behind a document |
| `TileLabel` | An `IconTile` before a row's title | The label of a Settings row: a toggle, a picker, a link to another screen. Not for plain text buttons such as "Report a problem" |
| `IconTile` | An SF Symbol on a small filled tile, as the system's Settings rows show theirs | List rows that lead somewhere. `brand` for things to open or change, `intelligence` for what the intelligence layer does, `quiet` for things set aside (Recently deleted). The fills and their symbol colours are the declared contrast pairs. Decoration beside the row's title |

### Lists

Home on iPhone is the one grouped screen that is not a `List`: it is a scroll view of cards drawn
like a grouped list's sections (PAP-040). In the sidebar-style list the accessibility audit reported
small text and the rows' counts as not scaling or as clipped, on text that used standard styles; as
cards, every part lays itself out at once when the text size changes, and the audit passes at the
default size and at AX3. In a wide window the same sections are a `.sidebar` list.

Settings groups its rows under at most one heading per subject: privacy and security are one section
(the statement, Spotlight, App Lock and the privacy report), and About is one row that opens the
app's mark and version, its public pages, sharing and the company mark.

System `List` styles only: `.insetGrouped` for settings, `.sidebar` for the library sidebar, plain
for search results. Swipe actions (for example Delete, Favourite) always have an equivalent in the
context menu and as accessibility custom actions, because the HIG asks for alternatives to gestures
([Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)).

### Toolbars and ornaments

- System toolbars with items grouped by purpose (leading: navigation and document menu; trailing:
  primary actions), using `ToolbarSpacer` to separate groups. Liquid Glass comes from the system.
- Toolbar labels stay monochrome over PDF content, as the HIG advises for colourful content
  ([Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)); only the
  selected annotation tool shows the brand tint, together with a selected shape.
- **One exception: the reader's primary action.** The reader's bar holds exactly one filled
  button, Edit, built as `PrimaryButton` for bars. An icon among icons was missed by people who
  were not looking for it (owner's device test, 2026-10-06, PAP-037). Every other item in that bar
  stays a monochrome symbol, and no second filled button is added to it.
- **Tips** (TipKit) are for a screen's primary action only, and one-time: a tip stops for good
  when the action is used, when it is closed, or after three showings. A tip is never shown for a
  feature that is hidden or locked, never where the action would answer with a refusal, and never
  over a sheet or an alert. It is drawn in the screen's layout, not presented over it.
- Items that do not fit move to the system overflow menu on iPad and Mac; we never build our own.
- Window titles are the document name, never the app name (same source).
- **Ornaments** are a visionOS component: controls that float beside a window
  ([Ornaments](https://developer.apple.com/design/human-interface-guidelines/ornaments)). They are
  not used in V1. The reader's tool strip is designed as a self-contained view so a future native
  visionOS target can present it as an ornament without redesign ([platform strategy](platform-strategy.md)).

### PDF controls

These are the product's most-used custom components. Each wraps the PDF engine's view through the
`PDFEngine` adapter ([ADR-0007](adr/0007-pdf-sdk-boundary-and-vendor-selection.md)) and adds our
accessibility layer where the vendor's is weak.

#### Thumbnail rail

- Leading column in regular width; a horizontal strip at the bottom in compact width, shown on demand.
- The current page has an outline and a page number label, never colour alone. VoiceOver label:
  "Page 12 of 240, current page".
- In Organise mode, thumbnails reorder by drag (`Transferable`), and each offers custom actions:
  Move up, Move down, Rotate, Delete, Extract.
- Thumbnails come from the engine's cache and must meet the thumbnail budget in
  [performance budgets](performance-budgets.md).

#### Page indicator

- A small Liquid Glass capsule floating over the page ("12 / 240"). It hides while reading and
  returns on tap or scroll stop; with VoiceOver running it stays visible and focusable.
- Tapping it opens Go to Page (number field plus outline). Uses monospaced digits so it does not
  jitter while scrolling.

#### Zoom

- Pinch and double-tap follow the engine's native behaviour. A zoom menu in the toolbar offers Fit
  Width, Fit Page and Actual Size; keyboard ⌘+, ⌘− and ⌘0.
- `accessibilityZoomAction` supports assistive zoom gestures; the zoom level is announced after a
  change. `Assumption:` a 25%–800% range; confirmed against the chosen SDK's limits.

#### Annotation palette

- Tools: Highlight, Underline, Strike-through, Pen, Text, Shape, Note, Eraser. On iPad, Apple Pencil
  uses the PencilKit tool picker ([PencilKit](https://developer.apple.com/documentation/pencilkit)).
- The selected tool shows a filled symbol, a tinted background and a text label; the selected
  colour shows a check mark.
- Every tool has a spoken name and a keyboard shortcut on iPad and Mac.

#### Colour picker

- The six named annotation colours as swatches, plus the system `ColorPicker` for custom colours and
  a recent-colours row.
- Swatches announce their names; the selected swatch has a check mark, so the picker works for
  people who cannot distinguish the colours ("Differentiate Without Color Alone").

#### Signature pad

- A full-width canvas with a baseline and a "Sign above the line" hint, Clear and Done buttons, and
  landscape support on iPhone. PencilKit on iPad; finger drawing on iPhone.
- Alternatives for people who cannot draw: type a name (rendered in an installed system script
  face) or import an image of a signature.
- Saved signatures are sensitive data: stored on device with complete data protection, never synced
  unless the user turns it on, and never sent to any AI tier ([data classification](data-classification.md),
  [privacy architecture](privacy-architecture.md)).

#### Scanner capture UI

- Capture uses the system document camera (`VNDocumentCameraViewController`) unchanged, so edge
  detection, guidance and its accessibility come from the system ([ADR-0008](adr/0008-ocr-and-scanning.md)).
- Our review screen follows: a page grid with reorder, retake, crop and filter (colour, greyscale,
  black and white), a document-name field and a "Make text searchable" switch, on by default.
- Recognition progress uses the system continued-processing progress UI when the app leaves the
  foreground ([iOS architecture review](ios-architecture-review.md)).

#### OCR confidence overlay

- An optional "Review recognised text" mode draws recognised text regions over the scanned page.
- Words below the confidence threshold get a dashed underline and a warning symbol, not only a
  colour. `Assumption:` threshold 0.5 on Vision's recognised-text confidence
  ([RecognizedText confidence](https://developer.apple.com/documentation/vision/recognizedtext/confidence));
  tuned with the OCR accuracy suite ([testing strategy](testing-strategy.md)).
- VoiceOver reads each flagged word as "Low confidence: invoice" and offers Correct and Accept
  actions. Corrections update the invisible text layer and the search index.

### AI answer cards with page citations

AI answers are the product's differentiator, so their design carries the trust rules in
[AI governance](ai-governance.md).

- **Structure:** a header with the question; a tier badge (cyan symbol plus text: "On device",
  "Private Cloud Compute" or "Claude by Anthropic"); the answer in Body text at readable width;
  citation chips ("p. 12") after the sentences they support; actions (Copy, Share, Save as note,
  Report a problem).
- **Citations are required.** Tapping a chip opens the page with the supporting passage
  highlighted. An answer the model cannot support shows "Not found in this document" rather than an
  uncited answer. The evaluation target for correct citations is in [success metrics](success-metrics.md).
- **Labelled as generated.** A footnote reads "Generated from this document. Check important details
  against the pages cited." Generated text is never styled like, or inserted into, the PDF without
  an explicit user action.
- **Uncertainty is visible.** When the model reports low confidence, a warning line says so.
- **Analyse Contract** shows a persistent disclosure at the top of every result: "Explains the
  document. Not legal advice." It is never dismissible and is translated with legal review
  ([non-goals](non-goals.md)).
- **Streaming:** text streams in without a typing animation; with Reduce Motion it appears in
  paragraph steps. VoiceOver announces once, when the answer is complete, and focus moves to the
  answer's first line.
- **Content layer:** the card uses a standard material, not Liquid Glass.

### First-run introduction

Three pages on first launch, one benefit each, telling one story: make a PDF, work on it, get more
from it ([PAP-045](decision-register.md), [PAP-052](decision-register.md),
[PAP-060](decision-register.md)).

| Page | Headline | Where on-device intelligence is unavailable |
|---|---|---|
| 1 | Scan anything to PDF | Same |
| 2 | Edit, sign and organise | Same |
| 3 | Ask your documents | Do more with every file (merge, make smaller, find) |

- Each page is a phone drawn in SwiftUI (`DeviceMockup`) showing the app's own screen for that
  capability over a synthetic document, with its lower edge fading into the page; then a Large
  Title headline of at most two lines, one sentence in Body, and one `PrimaryButton` ("Continue")
  in the bottom bar, in the same place on every page. Nothing in the picture is a screenshot, and
  it carries no words, so it needs no translation. A soft pool of the page's colour sits behind
  the phone, and three tiles float beside it with the page's tools or results. At accessibility
  text sizes the picture goes.
- **Skip** is in the toolbar on every page. A swipe turns the page forwards and back; "Continue"
  does the same for everyone, so no page needs a gesture, and only "Continue" on the last page
  ends the introduction. The page indicator is never the only sign of progress.
- Which third page shows is decided before it is on screen; it never changes while shown.
- Pages name only what the installed build does (FR-ONB-007), and no permission is asked here.
- Motion goes through `Motion`: a new page enters from the side the person is moving towards, the
  tiles arrive one after another, the scan line sweeps and the signature draws itself once. With
  Reduce Motion, and in UI tests, the pictures are still and pages change at once.
- After the last page, or Skip, first run is marked complete, then the subscription offer may show
  once (see Paywall); closing it leads to Home. While the App Store has not yet said whether the
  plans can be shown, the page waits up to three seconds with a spinner in place of "Continue".

### Home's first-use hint

Where the app this plan was modelled on blurs the screen and points a bubble at its add button,
Home already says how to begin (PAP-040): while the library is empty, a line under the starting
actions reads "Import a PDF from Files, scan a paper document, or try a sample", with the sample
one tap away, and it goes once a document exists (FR-ONB-008). It is part of the layout, covers
nothing and needs no dismissing, so no tip card is added on top of it.

### Intent picker (Settings)

The question "What do you do with PDFs most often?" is no longer asked on first launch; it is
Settings › Home screen › What you do most. The choice personalises the
home screen and the order of tools; it never gates anything.

| Group | Options (in this order) |
|---|---|
| Ask and understand (first) | Chat with PDF · Summarise Document · Extract Data with AI · Analyse Contract ("Explains contracts. Not legal advice.") |
| Work with PDFs | Edit PDF text · Annotate / Highlight · Sign · Convert PDF → Word/Excel/PPT · Merge / Organise pages · Read or view · Scan to PDF · All tools |

- Options are cards with an SF Symbol, a title and a one-line Callout description. `Assumption:`
  more than one option can be selected, and the first selected leads the home screen; confirmed in
  usability sessions.
- The question is optional, as the HIG recommends for onboarding
  ([Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)); with
  nothing chosen, Home shows its default actions.
- **No account or permission request appears during first run.** Permissions are requested when
  the feature needs them (the camera on first scan, notifications on the purchase confirmation).
- On devices that do not support Apple Intelligence, or where it is turned off, the AI options stay
  visible with a note that they run through an optional cloud service; the consent screen appears
  only when the user first uses one ([ADR-0009](adr/0009-tiered-ai-and-consent.md)). The app checks
  the model's availability through the framework, never a device list, and interface copy never
  implies on-device AI works on every device.

### Paywall

- The app's own screen over StoreKit 2 ([ADR-0027](adr/0027-own-paywall-over-storekit-2.md),
  [PAP-056](decision-register.md)). It answers three questions in order: what do I get, why is it
  worth it, what am I paying.
- **Layout.** Scrolling: the headline in the brand tint, one line under it, the scanning picture
  (`DeviceMockup`, gone at accessibility text sizes), what Pro adds, and the promise that documents
  never need Pro. Fixed at the foot of the screen: two plan cards side by side, the terms for the
  selected plan, one `PrimaryButton`, and four quiet links (Restore purchases, Redeem a code,
  Terms, Privacy). At accessibility text sizes the cards stack and everything scrolls together.
- **Plan card.** The plan's name, its price with its period, and one line under it: the free trial
  this account can have, or on the annual plan its saving. The annual plan carries a "Best Value"
  badge and is selected when the offer opens. Selection shows as a check mark and a brand border,
  never by colour alone.
- **Terms under the cards.** With a trial: its length, what is due today, and the price and period
  that follow, in one line. Without: the price and period. Then: it renews until cancelled, and
  how to cancel. A trial is shown only when StoreKit says the account is eligible; its length is
  StoreKit's.
- **Button.** "Start free trial" or "Subscribe", by the selected plan; a spinner while the App
  Store's sheet is on its way. For someone who has Pro: a note that says so, "Continue", and
  "Manage subscription"; nothing is sold.
- **States.** Loading: a spinner where the cards will be. Plans not loaded: a short message, "Try
  again" and Close. Cancelled: nothing changes. Pending or failed: an alert that says nothing was
  charged.
- **When it appears.** Once at the end of the first-run introduction ([PAP-042](decision-register.md)),
  and only if the products have loaded and the person does not have Pro; with no connection, first
  run ends on Home. After that: when the user taps a Pro feature (marked with a "Pro" badge), when
  the day's free allowance is used, and from Settings. Never at a later launch.
- **Close.** A Close button is in the toolbar from the first frame and closes in one action;
  swiping the sheet down does the same.
- **Every number is StoreKit's.** Names, prices, periods and the trial's length are formatted from
  StoreKit's values for the storefront. The one figure the app works out is the annual plan's
  saving against paying weekly for a year, from StoreKit's two prices, the percentage rounded down
  and left out when either plan does not load ([PAP-049](decision-register.md)).
- **When the store cannot be reached** after the person asked for the paywall, it shows a short
  message and Close, never an empty store.
- **Honest by construction.** Outcome-first header ("Unlimited answers with page citations"), the
  full renewal price as the most prominent price, trial length and the price after the trial, a
  plain statement that the plan renews until cancelled, and how to cancel. No countdown timers, no
  delayed Close button, no struck-through price, no urgency, and both plans always visible. The full
  disclosure checklist is in [App Store strategy](app-store-strategy.md).
- The Manage Subscription row in Settings opens the system sheet (`manageSubscriptionsSheet`).
  Settings has a subscription section straight after the AI switch, which stays first so that it is
  on the first screen at every text size: the plan (Free, Trial until a date, Pro, or a payment
  problem), See plans, Manage Subscription, Restore Purchases and Redeem Code.

### Purchase confirmation

Shown in the same presentation as the paywall when the entitlement changes to one that grants Pro
(FR-STORE-007): a check mark on a brand-filled circle with the `motion.emphasis` symbol effect and
the success haptic, "Welcome to Pro" in the brand tint, what is now available side by side (a list
at accessibility text sizes), and one `PrimaryButton` ("Start").
During a trial it also shows the date the trial ends and a "Remind me before the trial ends"
switch, which is the only place the app asks for notification permission; without permission the
reminder is an in-app notice. A pending or cancelled purchase shows nothing here, and closing this
screen never leads to a rating request.

### Empty, error and loading states

| State | Pattern | Example |
|---|---|---|
| Empty | `ContentUnavailableView` with a symbol, one sentence and at most two actions | Library: "No documents yet" with Scan and Import, plus "Try a sample". Home offers the same three when the library is empty |
| No search results | `ContentUnavailableView.search` with the query | "No results for 'lease'" |
| Offline | Inline banner, not a blocking alert | "You're offline. Answers on this device still work; cloud answers resume when you're back online." |
| Error | Plain language: what happened, what is safe, what to do next | "Couldn't save the signature. Your document hasn't changed. Try again." |
| Loading, short | Placeholder layout (`redacted(reason: .placeholder)`) | Library grid while the index opens |
| Loading, long | Determinate progress with a cancel button | OCR of a 200-page scan |

Errors never blame the user, never show raw error codes as the main text (codes appear in the
diagnostics summary; see [operations](operations.md)), and never lose work. The HIG asks apps to show
something as soon as possible and to show determinate progress when the duration is known
([Loading](https://developer.apple.com/design/human-interface-guidelines/loading)).

## Motion and haptics

**One `Motion` helper.** All custom animation goes through `Motion`, which reads
`accessibilityReduceMotion` and returns the reduced version automatically. Feature code does not call
`withAnimation` with its own curves; the `invariants` gate flags custom animation outside the
`DesignSystem` package.

| Motion token | Standard | With Reduce Motion |
|---|---|---|
| `motion.quick` | `.snappy`, `Assumption:` 0.2 s | Instant or opacity fade |
| `motion.standard` | `.smooth`, `Assumption:` 0.35 s | Opacity cross-fade |
| `motion.pageTransition` | Engine's native page animation | Cross-fade; no sliding or zooming |
| `motion.emphasis` | Symbol effect on success (for example a check mark) | Static symbol |

Rules follow the HIG: motion is purposeful, short and cancellable, never the only way to convey
information, and frequent interactions get little or no custom motion
([Motion](https://developer.apple.com/design/human-interface-guidelines/motion)). With Reduce Motion
on, sliding and zooming transitions become fades, as the HIG's accessibility guidance lists
([Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)).

**One `Haptics` helper** maps product events to system feedback through `sensoryFeedback`:

| Event | Feedback |
|---|---|
| Document saved after an edit; scan finished; signature placed | `.success` |
| An operation failed | `.error` |
| Unsaved-changes prompt | `.warning` |
| Tool, colour or page selection changed | `.selection` |
| Page picked up or dropped while reordering | `.impact(weight: .light)` |

Haptics always accompany a visual change, keep one meaning per pattern and are never used for
decoration, as the HIG asks ([Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)).
The system's own haptics setting is respected automatically.

## Accessibility

Targets and methods, per the HIG's [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
guidance and the architecture review's accessibility section ([iOS architecture review](ios-architecture-review.md)):

| Area | Requirement | How it is verified |
|---|---|---|
| Contrast | 4.5:1 for text up to 17 points; 3:1 for 18 points or more, bold text, UI components and meaningful graphics; in light, dark and Increase Contrast | Contrast tests over `tokens.json` pairs; snapshot review |
| Dynamic Type | Every screen usable at AX5; no truncated meaning | Snapshots at Large and AX5; UI tests at AX5 |
| VoiceOver | Every control labelled with its purpose; values and traits set; logical order; grouped cards | `performAccessibilityAudit()` in UI tests; scripted manual pass each release |
| VoiceOver rotors | Custom rotors for **Headings** (from the PDF outline or tags, or from OCR document structure for scans), **Pages**, **Annotations** and, in AI answers, **Citations** (`accessibilityRotor`) | UI tests enumerate rotor entries on corpus documents |
| PDF text | Read from the text layer, and from OCR for scanned files, so untagged PDFs are still readable | Golden corpus tests |
| Targets | 44 × 44 points by default, never below the HIG minimum of 28 × 28 | Accessibility audit; design review |
| Voice Control | Visible label equals the spoken name; short `accessibilityInputLabels` for icon buttons ("Highlight", "Sign", "Scan") | Manual Voice Control pass each release |
| Keyboard | Full Keyboard Access; shortcuts for common actions (⌘F find, ⌘+/⌘−/⌘0 zoom, arrow keys for pages); visible focus; no system shortcuts overridden | Keyboard-only pass on iPad each release |
| Motion | Reduce Motion honoured through `Motion` | Snapshot with Reduce Motion on |
| Transparency | Reduce Transparency and Increase Contrast change Liquid Glass automatically; custom glass controls fall back to opaque | Snapshot with both settings on |
| Colour | Never the only signal | Design review checklist; "Differentiate Without Color" snapshot |
| Listening | "Listen to this PDF" with `AVSpeechSynthesizer` | Manual |

These results also feed the Accessibility Nutrition Labels declared on the App Store, which may only
claim a feature if people can complete all common tasks with it
([Overview of Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels);
see [App Store strategy](app-store-strategy.md)).

## Implementation

### tokens.json

- One file, `design/tokens.json`, is the source of truth for colour, spacing, size and motion
  tokens. It follows the Design Tokens Community Group format, which reached its first stable version
  (2025.10) in October 2025 ([Design Tokens Format Module](https://www.designtokens.org/tr/drafts/format/)).
- Colour tokens that map to system colours record the system name; brand tokens record four values
  (light, dark, and each with Increase Contrast) under an `$extensions` key.
- Contrast pairs are declared in the same file with a minimum ratio, for example
  `{ "foreground": "color.brand.tint", "background": "color.background.secondary", "minRatio": 4.5 }`.

### DesignSystem package

- A generator script (`scripts/design/generate_tokens.py`) writes a Swift file of typed tokens
  (`Color.ds.brandTint`, `Spacing.s200`) into the `DesignSystem` package. Brand colours resolve per
  appearance (light, dark, and each with Increase Contrast) through dynamic colour providers, and
  semantic tokens return the system colour named in `tokens.json`. The same script checks every
  declared contrast pair and the spacing grid, and CI reruns it with `--check` to catch drift.
  Generated files are never edited by hand.
- The package also holds the components above, `Motion`, `Haptics`, the `readableWidth()` modifier
  and preview fixtures. Features depend on `DesignSystem`; `DesignSystem` depends only on SwiftUI and
  `Core` ([ADR-0002](adr/0002-xcodegen-and-modular-spm.md)).

### Parity and contrast tests

| Test | What it checks |
|---|---|
| Token parity | Each colour set, resolved in each of the four appearances, equals `tokens.json` (within one 8-bit step) |
| System mapping | Each semantic token returns the system colour named in `tokens.json` |
| Contrast | Every declared pair meets its minimum ratio in every appearance, using system colours resolved on the test device |
| Spacing | Generated constants equal the tokens and are multiples of 4 |
| Drift | CI reruns the generator and fails if the output differs from the committed files |
| Components | Snapshot tests per component in light, dark, Increase Contrast, Large and AX5 ([ADR-0018](adr/0018-snapshot-testing-test-only-dependency.md)) |
| Screens | `performAccessibilityAudit()` in UI tests for every top-level screen ([ADR-0014](adr/0014-testing-strategy-and-coverage.md)) |

### Enforcement

The `invariants` gate ([quality gates](process/quality-gates.md)) rejects, outside `DesignSystem`:
colour literals (`Color(red:…)`, hex initialisers), fixed font sizes (`.font(.system(size:))`), and
custom animation curves. Exceptions need a comment naming this document's section and a reviewer's
approval.

**Decision: tokens in the repository, generated into Swift.** **Rationale.** One reviewed source,
with tests, prevents the design and the code from drifting apart. **Trade-offs.** A generator to
maintain; designers edit JSON or a Figma plug-in that exports it. **Alternatives considered.**
Hand-written Swift constants (drift, no contrast checks); Figma as the source of truth (the
repository could not be verified in CI). **Risks.** Generator bugs; mitigated by the parity tests
themselves. **Future scalability impact.** The same file can generate tokens for the support website
and for a future Mac or visionOS adapter. **Pillars served.** PIL-7.

## Component lifecycle and governance

| Stage | Meaning | Exit criteria |
|---|---|---|
| Proposed | An issue with the `design` label describing the need and why no system component fits | Design review accepts it |
| Experimental | Lives inside one feature package, not reused | Used successfully; accessibility checked |
| Stable | In `DesignSystem`, documented here, with previews, snapshots and accessibility tests | — |
| Deprecated | Marked `@available(*, deprecated, message:)` with the replacement named | All uses migrated |
| Removed | Deleted after one minor release in Deprecated | — |

- **Design review** uses a checklist: which system component was considered; the Apple-first baseline
  ([ADR-0022](adr/0022-apple-first-capability-baseline.md)); the founder principles touched; contrast,
  Dynamic Type, VoiceOver, Voice Control, keyboard and Reduce Motion; the localisation headroom.
- **Token changes** need passing contrast tests and a changelog entry
  ([changelog strategy](changelog-strategy.md)).
- **Ownership.** The Design hat owns this document and the `DesignSystem` package. While there is
  one maintainer, the same person wears the Design and Architecture hats; the checklist is how the
  review stays honest. As people join, `DesignSystem` gets its own code owner
  ([GitHub governance](github-governance.md)).
- A separate `pdf-algo-pro-design` repository is reserved and created only if a separation
  criterion is met ([ADR-0019](adr/0019-public-private-documentation-split.md)).

## Figma library (readiness action)

The Figma library is part of readiness blocker C5 (UX information architecture, key flows and the
Figma library) in the [readiness review](readiness-review.md). The action:

1. Start from Apple's current iOS and iPadOS design kit in
   [Apple Design Resources](https://developer.apple.com/design/resources/), so system components match
   Apple's own drawings.
2. Create Figma variables that mirror `tokens.json`, with light, dark and Increase Contrast modes.
3. Build the components in this document, with the same names and states as the Swift components.
4. Draw the key flows: onboarding intent picker, first document, reader with thumbnail rail,
   annotation, signing, scan and OCR review, AI answer with citations, consent, paywall, and the
   empty, error and loading states, at Large and AX5, in English and French.
5. Record the file's link and version in [working memory](working-memory.md). The repository's
   `tokens.json` stays the source of truth; drift between Figma and the tokens is checked by hand at
   each milestone until an export is automated.

## Open questions

- **Increase Contrast cyan values.** The proposed `#155E75` and `#67E8F9` pass
  AAA; the brand owner confirms them or supplies others.
- **Typed signature typeface.** Which installed system script face to use, and whether a typed
  signature meets users' expectations in Australia and France.
- **Multi-select in the intent picker**, and how the home screen orders tools for several choices.
- **Resolved system colour values.** The `Assumption:` values above are confirmed by the first run of
  the contrast test on device.
- **A reflowed reading view** for small screens (text layer reflow with Dynamic Type) as a future
  feature; not in V1 scope today.
