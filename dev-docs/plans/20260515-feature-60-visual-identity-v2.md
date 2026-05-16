# Feature #60 — VReader visual identity v2

GH: #718 | Row status entering plan: `TODO` (row template fully filled) → `PLANNED` on Gate 2 pass
Author: Claude (Opus 4.7) | Date: 2026-05-15

## Problem

VReader's current chrome is a mix of SwiftUI system defaults (Library),
TextKit-driven `UITextView` (TXT/MD), WKWebView + CSS-injected theme
(EPUB), Foliate-js with its own CSS (AZW3/MOBI), and PDFKit. Each
surface drifted its own typography, accent, and theme story. The user
wants a single coherent reader identity per the `claude.ai/design`
handoff bundle at `dev-docs/designs/vreader-fidelity-v1/` — "Refined-
literary meets native iOS", Source Serif 4 + Inter, 5-theme palette
(Paper / Sepia / Dark / OLED / Photo), oxblood accent, redesigned
chrome + sheets, new SelectionPopover, generative typographic cover
fallback, status-bar tinting.

All changes are **purely visual + UX**. No behavior change to readers,
persistence, search, WebDAV, or AI is in scope.

## Surface area

### New types

- **`vreader/Models/ReaderThemeV2.swift`** (new) — extended theme token
  set per `vreader-themes.jsx`:
  ```swift
  enum ReaderThemeV2: String, Codable, CaseIterable, Sendable {
      case paper, sepia, dark, oled, photo
      // Tokens:
      var backgroundColor: UIColor { ... }   // .bg
      var paperColor: UIColor { ... }        // .paper (text container fill)
      var inkColor: UIColor { ... }          // .ink (primary text)
      var subColor: UIColor { ... }          // .sub (secondary text)
      var ruleColor: UIColor { ... }         // .rule (dividers, 0.5pt)
      var accentColor: UIColor { ... }       // .accent (oxblood family)
      var chromeColor: UIColor { ... }       // .chrome (toolbar bg)
      var isDark: Bool { ... }               // for status-bar tinting
      var hasPaperPattern: Bool { ... }      // Paper / Sepia only
      var usesBackgroundImage: Bool { ... }  // Photo only
      static var `default`: ReaderThemeV2 { .paper }
  }
  ```
- **`vreader/Models/AccentColor.swift`** (new) — three-stop oxblood
  mapping: `#8c2f2f` (light surfaces) / `#d6885a` (warm-dark) /
  `#e8b465` (photo). Single restrained hue across all chrome.
- **`vreader/Models/SelectionPopoverAction.swift`** (new) — payload
  shape for the new long-press-selection menu:
  `case highlight(NamedHighlightColor) | note | translate | askAI | read`.
  `NamedHighlightColor` is one of yellow/pink/green/blue (the row
  contract specifies four).
- **`vreader/Models/NamedHighlightColor.swift`** (new) —
  `enum NamedHighlightColor: String, Codable, CaseIterable, Sendable`
  with `rawValue` = semantic name (`"yellow"|"pink"|"green"|"blue"`).
  Derived `hex` property (computed, not the rawValue) returns the
  design bundle's exact hex values per `vreader-reader.jsx:SelectionPopover`
  (`#f0d25a` / `#e88ca0` / `#8cc88c` / `#8cb4e8`). **Additive only**: this is
  a UI-domain enum. It does NOT replace the existing `String color`
  schema in `Highlight.color` / `HighlightRecord.color` / backup DTOs
  / export-import payloads — those continue to store raw strings.
  Conversion helpers: `init?(rawValue:)` (the Codable default) and
  `static func from(storageString:) -> Self?` (best-effort decode of
  the existing yellow-default + future named colors). Codex Gate 2
  finding (round 1, High): keep additive, do not narrow the existing
  String boundary.
- **`vreader/Views/Reader/SelectionPopoverView.swift`** (new) —
  SwiftUI view that REPLACES the current `HighlightableTextView`
  4-item UIMenu for the **new-selection-from-long-press** flow only.
  Per row Cross-refs: distinct from feature #53 (tap-on-existing-
  highlight Edit/Delete) and #55 (tap-on-annotated-text note preview);
  those flows keep their existing presenters.
- **`vreader/Views/Library/GenerativeCoverView.swift`** (new) — five
  style families per `vreader-cover.jsx` (classic / modern / editorial
  / animal / minimal). Fallback used when a real cover image is absent.
  Coexists with feature #43 cover extraction; policy: real-cover-if-
  available, generative-fallback.
- **`vreader/Services/ReaderTypography.swift`** (new) — bundled font
  registry. `Source Serif 4` (variable face, two axes if iOS supports;
  otherwise regular + bold + italic + bold-italic) and `Inter`
  (regular + medium + semibold). UI chrome uses Inter; reader body
  defaults to Source Serif 4. Serif↔sans toggle stored alongside
  existing `ReaderFontFamily` enum.

### Modified types

- **`vreader/Models/ReaderTheme.swift`** — `enum ReaderTheme` migrates
  to a deprecated alias of `ReaderThemeV2`, mapping
  `light → paper, sepia → sepia, dark → dark`. The deprecation
  preserves Codable read-paths for existing per-book persisted
  settings (`epubTheme`, `txtTheme`). Migration is mechanical;
  no SwiftData schema bump (the stored String value changes only
  for new theme picks).
- **`vreader/Models/TypographySettings.swift`** — `ReaderFontFamily`
  gains `.sourceSerif4` and `.inter` cases; `.serif` continues to
  resolve to Georgia for users who explicitly picked it; new default
  is `.sourceSerif4` for body and `.inter` for chrome.
- **`vreader/Services/ReaderSettingsStore.swift`** — plumb the new
  token reads + the serif↔sans toggle.
- **`vreader/Services/ThemeBackgroundStore.swift`** — extend to the
  Photo theme. New per-theme image asset lifecycle (pick / clear /
  WebDAV-backup-question — see Edge cases).

### Modified views

- **`vreader/Views/Reader/ReaderSettingsPanel.swift`** — re-skin to
  match `vreader-panels.jsx`'s Reader Settings sheet: Brightness +
  5-theme picker (now shows tokens visually) + Size / Line-spacing /
  Margin sliders + font toggle (Serif Source Serif 4 ↔ Sans Inter).
- **`vreader/Views/Reader/ReaderContainerView.swift`** — chrome
  re-skin per `vreader-reader.jsx`: new top bar (back / title / book-
  mark / more) + bottom bar (Contents / Notes / Display / AI — Notes
  routes to the highlights/annotations panel, AI is the accent slot)
  + page indicator + scrubber. Edges-tap-flip / middle-tap-toggle-chrome
  convention. Aligns with feature #25 tap zones; resolves bug #165
  as a side-effect.
- **`vreader/Views/Reader/TXT*ReaderContainer*.swift`,
  `MDReaderContainerView.swift`,
  `EPUBReaderContainerView.swift`,
  `EPUBReaderContainerView+Navigation.swift`** — adopt the new chrome
  via the shared composition view rather than per-format duplication.
- **`vreader/Views/Reader/HighlightableTextView.swift`** — REPLACE the
  4-item UIMenu (Highlight / Add Note / Define / ▶) for new-selection
  with the new `SelectionPopoverView`. **Carefully gate** against
  feature #53's WI-2/WI-3 paths: tap-on-existing-highlight stays on
  the WI-1 presenter protocol; only the new-selection-from-long-press
  flow swaps. Feature #53's modifier-driven `.readerHighlightTapped`
  pipeline is untouched.
- **`vreader/Views/LibraryView.swift`,
  `vreader/Views/BookCardView.swift`,
  `vreader/Views/BookRowView.swift`** — re-skin per
  `vreader-library.jsx`: continue-reading rail + 3-column grid +
  filter chips + search bar + grid↔list toggle (aligns with feature
  #6).
- **`vreader/Views/AI/AISheet*.swift`** (find on Gate 3 entry) —
  re-skin Summarize / Chat / Translate tabs per
  `vreader-panels.jsx`.
- **`vreader/Views/Bookmarks/TOC*.swift`,
  `vreader/Views/Annotations/Highlight*.swift`,
  `vreader/Views/Settings/*.swift`** — sheet re-skins, no behavior
  change.

### Reader-engine theme injection updates

- **EPUB** (`vreader/Models/ReaderTheme.swift:epubOverrideCSS`,
  `vreader/Views/Reader/EPUBReaderContainerView.swift:329` themed
  background flow) — emit the new five-theme CSS. Photo-theme CSS
  injects a background image via local file URL.
- **TXT/MD** (`vreader/Models/TXTViewConfig.swift` →
  `TXTAttributedStringBuilder`) — bundle the new fonts; replace
  hard-coded `Georgia` resolution with `ReaderTypography.body(for:)`.
- **AZW3/MOBI Foliate** (`vreader/Services/Foliate/*`) — Foliate-js
  `setStyles` payload extended; ship the variable font file inside
  the Foliate bundle so the WKWebView sees it (Risk (c) below).
- **PDF** (`vreader/Views/Reader/PDFViewBridge.swift`) — PDFKit
  honours the theme background tint + chrome only (per row out-of-
  scope: "PDF chrome stays on PDFKit defaults until extended"); the
  full PDF chrome re-skin is deferred to v2.

### Files OUT of scope (per row "Out of scope for v1")

- PDF chrome — stays on PDFKit defaults.
- AZW3/MOBI chrome — Foliate shell stays; only typography +
  theme-token CSS injected.
- Search results panel — re-skin deferred.
- WebDAV / restore picker UI — feature #52 in flight.
- AI provider editor (#50 / #185 surface) — separate.
- Reading-time dashboard (#58) — needs design extension first.
- Hierarchical TOC tree (#38) — separate.
- Bilingual inline mode (#56) — design's Translate is point-in-time
  only.

## Prior art / project precedent / rejected alternatives

### Prior art in this codebase

- `ReaderTheme.swift` already implements the three-token light/sepia/
  dark pattern with cached `UIColor` instances + `epubOverrideCSS` JS
  injection — same shape, just three tokens instead of nine. The new
  `ReaderThemeV2` extends, doesn't replace, that pattern.
- `ReaderFontFamily` enum already supports a small font-family
  catalogue; the WI-1 typography work extends it (instead of
  introducing a parallel enum) so per-book settings persist.
- Feature #32 `ThemeBackgroundStore` already manages per-theme image
  assets — the Photo theme reuses that pipeline (no new service).
- Feature #53 WI-1 introduced the `HighlightActionPresenting`
  protocol — the new `SelectionPopoverView` does NOT replace it; it
  replaces the **separate** new-selection UIMenu. The two flows stay
  decoupled.

### Rejected alternatives

| Alternative | Why rejected |
|---|---|
| Migrate `ReaderTheme` enum in place (rename `light → paper`) | Breaks all per-book persisted Codable settings without a migration path; users would lose their per-book theme choice. The deprecated-alias approach preserves them. |
| Ship Source Serif 4 + Inter as variable fonts only | iOS 17/18 variable-font support is solid for system rendering, but the Foliate-js WKWebView injection path is more reliable with static font files. WI-1 ships static faces; revisiting variable-font support is a v2 follow-up. |
| Replace the entire Library view in one WI | LibraryView.swift is ~1000+ LOC with state intertwined with collection/search/sort. Re-skin in two passes: (a) BookCardView + BookRowView visual tokens; (b) LibraryView container layout (grid / rail / chips). Two WIs, each shippable. |
| One big "visual identity" PR | 8-12 WIs over 8-12 PRs is the established vreader cadence (see feature #45's 6-WI cadence, feature #46's 11-WI cadence). Big-bang PRs are not reviewable and break the per-PR version-bump + audit-log invariants. |
| Replace the `HighlightableTextView` UIMenu globally (long-press AND tap-on-highlight) | Feature #53 explicitly carves the tap-on-existing-highlight flow into its own WI-1/2/3/4/5/6 pipeline. WI-2/WI-3 presenters are already on main. Replacing both menus in one WI would re-skin already-shipped feature-#53 work and risk regression. The two flows stay separate. |

### Industry precedent

Kindle iOS + Apple Books iOS both ship a single coherent typography +
theme + chrome story. Their long-press-selection popovers are
distinct from their tap-on-existing-highlight popovers (different
action sets, different anchors). The vreader design bundle aligns
with that separation; this plan preserves it.

## Work-item sequencing

Estimated 10 WIs across 10 PRs. Each WI is one PR with its own
audit log + version bump per rule 40.

| WI | Tier | What ships | Est PR size |
|----|------|-----------|---------|
| WI-1 | Foundational | Bundle Source Serif 4 + Inter fonts in `vreader/Resources/Fonts/`. Add `ReaderTypography` registry. Extend `ReaderFontFamily` with `.sourceSerif4` and `.inter`. **No view change** — dormant infra. Tests: registry load, fontDescriptor availability, fallback chain. | ~6 files, ~250 LOC (font binary excluded) |
| WI-2 | Foundational | Add `ReaderThemeV2` enum + 9-token surface. Migration alias on `ReaderTheme` so existing persisted choices still decode. **No view change** — dormant infra. Tests: token round-trip, isDark predicate, migration alias, accent contrast against ink (WCAG AA per theme). | ~4 files, ~300 LOC |
| WI-3 | Foundational | Add `AccentColor`, `NamedHighlightColor`, `SelectionPopoverAction` types as UI-domain enums. **Additive only** (Codex Gate 2 finding): does NOT change the existing `Highlight.color` / `HighlightRecord.color` / backup DTO / export-import `String` schema. `NamedHighlightColor` raw values are semantic names; hex is a derived computed property. `SelectionPopoverAction` is `Equatable + Sendable` (NOT Codable — it's local-dispatch only, not persisted). `AccentColor` is a token-only struct with three named stops (light/warm-dark/photo). **No view change** — dormant infra. Tests: exhaustive switch, raw-value-is-semantic-name, derived-hex round-trip, compatibility (existing color strings remain storable + decodable to nil for unknown values), `from(storageString:)` round-trip. | ~3 files (4 if `NamedHighlightColor.swift` split out), ~150 LOC |
| WI-4 | Behavioral | EPUB theme injection switches to `ReaderThemeV2`. `epubOverrideCSS` emits five-theme CSS + new token names. Existing EPUB books re-render with new visual tokens. Migration path: existing `epubTheme: .light/.sepia/.dark` continues to decode and maps to `.paper/.sepia/.dark`. Photo theme injects a `body { background-image: url(...) }` rule. Tests: CSS string assertions per theme + per-theme accent contrast. Device verify (Gate 5a): open mini-epub3 fixture per theme, confirm visually. | ~3 files, ~250 LOC |
| WI-5 | Behavioral | TXT + MD theme injection switches to `ReaderThemeV2`. `TXTViewConfig` reads `ReaderTypography.body(for:)` instead of hard-coded Georgia. Tests: config round-trip, attributed-string font resolution. Device verify (Gate 5a): open seeded MD multi-page fixture per theme. | ~4 files, ~220 LOC |
| WI-6 | Behavioral | Reader chrome re-skin (top bar + bottom bar + page indicator + scrubber) shared across TXT/MD/EPUB containers. Edges-tap-flip / middle-tap-toggle-chrome convention. **Cross-ref**: aligns with feature #25 tap zones; verify whether bug #165 closes as a side effect (file follow-up if not). Tests: chrome-toggle gesture routing; tap-zone hit-test boundaries (33% / 33% / 33% split per design). Device verify: tap each zone, confirm advance / toggle / advance behavior. | ~6 files, ~400 LOC |
| WI-7 | Behavioral | Replace `HighlightableTextView`'s new-selection 4-item UIMenu with `SelectionPopoverView`. **Carefully gate**: tap-on-existing-highlight via feature #53's WI-1 presenter is untouched. Four named highlight colors create distinct `HighlightRecord`s (the persistence layer already supports a color field). Tests: presenter selection routing, color → HighlightRecord round-trip. Device verify: long-press TXT fixture, confirm SelectionPopoverView appears with 4 colors + 4 actions; tap a color, confirm highlight created with the right color. | ~5 files, ~350 LOC |
| WI-8 | Behavioral | Library re-skin pass 1: `BookCardView` + `BookRowView` visual tokens (use `ReaderThemeV2`-style chrome tokens for Library — Inter font, accent applied to badges). Tests: snapshot-free visual assertions (cell sizing, accessibility identifiers preserved). Device verify: library grid + list, confirm visual match. | ~4 files, ~250 LOC |
| WI-9 | Behavioral | Library re-skin pass 2: `LibraryView` continue-reading rail + 3-column grid + filter chips + search bar + grid↔list toggle. Tests: container composition, view-model state preserved. Device verify: scroll the rail, tap a filter chip, confirm grid updates. | ~5 files, ~400 LOC |
| WI-10 | Behavioral (final) | Sheet re-skins: TOC / Highlights / AI / Reader Settings / App Settings + generative-cover fallback view + status-bar tinting (`UIApplication.shared.windows.first?.windowScene?.statusBarManager` via SwiftUI's `preferredColorScheme`). **Final WI; flips feature row to DONE.** Tests: sheet composition + cover fallback decision policy. Device verify: each sheet end-to-end + cover fallback. | ~8 files, ~500 LOC |

Total: ~50 files touched, ~3,000 LOC across the feature (font binaries
not counted; ~5MB asset).

## Test catalogue

### WI-1 (foundational typography)

- `ReaderTypographyTests` — font load round-trip; fallback chain;
  `body(for:)` returns the expected face name per `ReaderFontFamily`
  case; CJK fallback (Source Serif 4 doesn't carry CJK → platform
  fallback to PingFang SC / Hiragino).
- `vreader/Resources/Fonts/` regression check — bundle includes the
  expected `.otf` files and they pass `UIFont(name:size:)` lookup.

### WI-2 (foundational theme tokens)

- `ReaderThemeV2Tests` — all 9 token getters per theme; `isDark`
  predicate matches design; `paperPattern` true only for Paper +
  Sepia; `usesBackgroundImage` true only for Photo.
- `ReaderThemeMigrationTests` — decoding `{theme: "light"}` JSON
  (the existing serialized form) yields `.paper` via the alias;
  encoding `.paper` produces the new `{theme: "paper"}` form.
- `AccentContrastTests` — for each theme, accent vs `ink` ≥ 3.0 WCAG
  contrast (button-text minimum); accent vs `bg` ≥ 3.0 (small icon
  minimum).

### WI-3 (foundational popover types)

- `NamedHighlightColorTests`:
  - **exhaustive switch** (compile-time guarantee via CaseIterable count).
  - **raw value is semantic name** — `NamedHighlightColor.yellow.rawValue == "yellow"`, etc. Pinned because the rawValue IS the storage contract for the UI domain.
  - **derived hex** — `NamedHighlightColor.yellow.hex == "#f0d25a"` and the other three colors pinned to the exact design bundle values (`pink #e88ca0`, `green #8cc88c`, `blue #8cb4e8`).
  - **Codable round-trip** through the semantic-name rawValue.
  - **`from(storageString:)` happy path** — passing `"yellow"` returns `.yellow`; passing `"pink"`/`"green"`/`"blue"` returns the matching case.
  - **`from(storageString:)` unknown input** — passing `"red"`, `""`, `"#ff0000"`, `nil`-equivalent returns nil (does NOT coerce or default to `.yellow`; that's the caller's policy decision).
  - **Decode-contract pin** (Codex Gate 2 finding, Medium): `from(storageString:)` classifies historical and future raw `Highlight.color` strings correctly — `"yellow"`/`"pink"`/`"green"`/`"blue"` decode to the matching case; legacy hex (e.g. `"#fff3a3"`), empty string, and future custom names decode to `nil` (no silent coercion). Note: this is a decode-contract pin only; storage-type narrowing of `Highlight.color` / `HighlightRecord.color` / `BackupHighlight.color` / `ExportedAnnotation.color` is caught by Codex Gate 2 plan audit, not by the unit test.
- `SelectionPopoverActionTests`:
  - **Sendable + Equatable** (compile-time + behavior).
  - **exhaustive switch** for the WI-7 handler.
  - `SelectionPopoverAction` is intentionally NOT `Codable` (per Codex Gate 2 round 1: local dispatch only, not serialized).
- `AccentColorTests`:
  - Three named stops produce three distinct hex values matching the design (`#8c2f2f` / `#d6885a` / `#e8b465`).
  - Sendable conformance (compile-time).

### WI-4 (EPUB theme injection)

- `EPUBThemeOverrideCSSV2Tests` — for each theme, CSS contains
  expected token values (bg / paper / ink / accent / rule) at
  expected positions; Photo theme emits the background-image rule.
- Device verify (Gate 5a): mini-epub3 fixture per theme, screenshot
  per theme (5 artifacts), confirm visual match with the design
  PNGs at `dev-docs/designs/vreader-fidelity-v1/project/screenshots/`.

### WI-5 (TXT + MD theme + typography)

- `TXTViewConfigTypographyTests` — config picks Source Serif 4 by
  default; serif↔sans toggle flips to Inter; font name resolution
  succeeds against `ReaderTypography.body(for:)`.
- `TXTAttributedStringBuilderThemeTests` — attributed string carries
  the expected `.foregroundColor` and `.font` per theme.
- Device verify (Gate 5a): seed-md-multi-page fixture per theme.

### WI-6 (chrome re-skin)

- `ReaderChromeGestureTests` — tap at x=10% → previous-page event;
  tap at x=50% → chrome-toggle event; tap at x=90% → next-page
  event. Hit-test boundary tests at 30%/70% (per design's edges-flip
  zones).
- `ReaderChromeViewTests` — top bar contains the 4 expected slots
  (back / title / bookmark / more); bottom bar contains the 4
  expected buttons (Contents / Notes / Display / AI — Notes opens
  the highlights/annotations panel; AI carries the accent color).
- **WI-6a (foundational, shipped separately):** `ReaderChromeButton.swift`
  declares `ReaderTopChromeSlot` + `ReaderBottomChromeButton` enums
  consumed by both the view restructure (WI-6b) and the test
  harnesses. `ReaderChromeButtonContractTests` (7 tests) pins case
  order, accessibility identifiers, and the accent-slot predicate.
  No UI change in WI-6a.
- Device verify (Gate 5a): per format, tap each zone, screenshot
  the transition. **WI-6b only** — WI-6a has no user-visible delta
  and is sufficient with unit + integration tests + audit.

### WI-7 (SelectionPopover)

- **WI-7a (foundational, ships independently):**
  `SelectionPopoverActionRowTests` — 8 contract tests pinning case
  count + order matching design (Note / Translate / Ask AI / Read),
  mapping to `SelectionPopoverAction` dispatch cases, accent slot
  (Ask AI), stable accessibility identifiers, well-formed SF Symbol
  names. `SelectionPopoverView` SwiftUI overlay built and
  compile-validated; no production wiring (long-press still routes
  through the legacy UIMenu via `TXTBridgeShared.buildReaderEditMenu`).
- **WI-7b (behavioral, separate PR):**
  `SelectionPopoverViewTests` — view rendering smoke checks (where
  feasible without snapshot tooling). `HighlightableTextViewSelectionRouteTests`
  — long-press + selection-finalised invokes the new presenter,
  not the legacy UIMenu. **Regression guard**: tap-on-existing-
  highlight path (feature #53) still routes through
  `HighlightActionPresenting`, unchanged.
- Device verify (Gate 5a) — **WI-7b only**: long-press TXT and MD
  fixtures, confirm popover; tap a color, confirm HighlightRecord
  persisted with the chosen color. WI-7a is foundational (no UI
  delta) so unit + integration tests + audit are sufficient per the
  rule 47 Gate 5 matrix.

### WI-8 (Library card/row tokens)

- `BookCardViewVisualTests` — cell sizing per design (110 × 165
  including spine + page-edge accents); accessibility identifiers
  preserved.
- `BookRowViewVisualTests` — row layout matches design metadata
  layout.

### WI-9 (Library container)

- `LibraryViewLayoutTests` — view-model state preserved across the
  re-skin (sort order, filter chip selection, view-mode toggle).
- Device verify (Gate 5a): rail scrolling, filter chip toggle, grid
  ↔ list toggle.

### WI-10 (sheets + covers + status bar)

- `GenerativeCoverViewStyleTests` — five style families produce
  distinguishable visual output (style enum exhaustive switch);
  fallback decision picks generative when `book.coverImageData` is
  nil.
- `SheetReSkinSnapshotTests` (composition only, not pixel snapshot)
  — each sheet contains the expected sections + section ordering.
- `StatusBarTintingTests` — `preferredColorScheme` resolves to
  `.dark` for `isDark` themes (Dark / OLED / Photo) and `.light`
  for Paper / Sepia.
- Device verify (Gate 5b — full acceptance): open each sheet under
  each theme; force-quit + relaunch to confirm theme migration
  preserved per-book choice; tap a generative cover, confirm
  fallback rendered correctly.

## Risks + mitigations

| Risk | Mitigation |
|---|---|
| (a) **Typography metric drift** — Source Serif 4 has different x-height / cap-height than Georgia. Scroll-position restore math (bug #179 family) was built against Georgia metrics. | WI-5 includes an offset re-projection on font change: detect family swap, recompute `topCharOffsetUTF16` from current `contentOffset` against the new font's layout, re-apply. Test: open TXT at position X with Georgia, switch to Source Serif 4, confirm position still inside the same paragraph (±1 line). |
| (b) **Photo-theme image storage policy** — does the chosen image travel with WebDAV backups? | WI-10 design decision: Photo-theme images are PER-THEME (not per-book), stored in `Library/Application Support/ThemeBackgrounds/`. WebDAV backup ALREADY excludes that directory (feature #46 manifest spec); confirm with a unit test and document. |
| (c) **AZW3/MOBI fall-through** — Foliate-js's own typography won't honour Source Serif 4 unless the font ships inside the Foliate bundle. | WI-5 (or a WI-5b if needed) bundles the Source Serif 4 `.otf` into the Foliate JS resources via `Resources/foliate-js/fonts/` and emits an `@font-face` rule in the Foliate `setStyles` payload. Acceptance: opening an AZW3 fixture shows Source Serif 4-ish output. If the font fails to load on Foliate's side, document the fallback as a known limitation; gate on Codex audit. |
| (d) **Per-book theme migration** — existing per-book `epubTheme: .warmDark` etc. need to map to the new 5-theme set. | WI-2 introduces the deprecated-alias decoder. Test: existing JSON files under `Library/Application Support/PerBookSettings/` decode without warnings; the migration is one-way (write side uses the new enum); no SwiftData schema bump. |
| (e) **Dynamic-island top inset preserved across the new chrome** | Per WI-6 device verify: confirm no clipping on iPhone 17 Pro Sim across all 5 themes. Bug #179 territory; cross-test against the existing safe-area helper (`ReaderSafeAreaResolver`). |
| (f) **PDF/AZW3 fall-through** — if user picks a theme the underlying renderer can't honour, render closest approximation. | WI-4 design: PDFKit reads only background-tint + chrome from `ReaderThemeV2`; the full PDF chrome re-skin is out-of-scope for v1. AZW3 (Foliate) honours typography + theme CSS but keeps Foliate's own chrome. Document as known limitations in the Notes column on flip to `DONE`. |
| (g) **Re-skinning #53 + #55 presenters post-#60 = double cost** | Per row Cross-refs: #53's WI-1 presenter is chrome-agnostic; WI-2..6 presenters MAY be re-skinned post-#60 in a separate small PR. The plan does NOT consume that work into #60. |

## Backward compat

- **SwiftData schema**: no bump (current `SchemaV6` carries `epubTheme:
  String?` via Codable wrapping — the migration is value-domain, not
  schema-domain).
- **Per-book persisted settings** under
  `Library/Application Support/PerBookSettings/` — existing entries
  with `theme: "light" | "sepia" | "dark"` continue to decode via
  the migration alias; the write-side uses the new enum.
- **WebDAV backup manifest** unchanged (Photo-theme images are
  excluded per existing manifest spec, see Risk (b)).
- **Existing feature verification sets** (features #3 / #4 / #11 /
  #17 / #29 / #44 / #50) — must not regress per acceptance criterion
  (g). WI-4/WI-5/WI-6 PR descriptions explicitly reference each
  prior verification round and confirm no test failures introduced.

## Acceptance criteria (final WI)

From `docs/features.md` row 60:

- (a) Library matches design's grid + rail on iPhone 17 Pro Sim.
- (b) Reader (EPUB + TXT + MD) matches design's chrome + page layout
      pixel-close (within typography metric drift acknowledged in
      Risk (a)).
- (c) All 5 themes render correctly including Photo.
- (d) Long-press text in any reader format produces the new
      SelectionPopover with 4 colors + 4 actions.
- (e) AI sheet Summarize/Chat/Translate tabs match design.
- (f) Source Serif 4 ↔ Inter toggle works in reader.
- (g) Existing features (highlight persistence, search, AI, backup)
      unaffected — no regressions in feature #3 / #4 / #11 / #17 /
      #29 / #44 / #50 verification sets.

## Implementation gating

Per rule 47 follows `/feature-workflow` Gates 1-6 (Plan →
Independent plan audit → TDD → Implementation audit → Device
verification → Merge). Each WI is one PR with its own audit log +
version bump. Final WI (WI-10) flips the row to `DONE`; Gate 5b
final-acceptance evidence file at
`dev-docs/verification/feature-60-YYYYMMDD.md` lifts to `VERIFIED`.

## Manual Audit Evidence (Gate 2, manual-fallback per rule 47)

Per saved feedback: Codex audit-time consistently exceeds cron-
iteration budget; manual-fallback is the documented alternative.

### Files read in full

- `dev-docs/designs/vreader-fidelity-v1/README.md` (handoff intent)
- `dev-docs/designs/vreader-fidelity-v1/project/vreader-themes.jsx`
  (all 67 lines — theme tokens)
- `dev-docs/designs/vreader-fidelity-v1/project/vreader-reader.jsx`
  (top + SelectionPopover sections, ~150 lines)
- `dev-docs/designs/vreader-fidelity-v1/project/vreader-icons.jsx`
  (32 line icons)
- `dev-docs/designs/vreader-fidelity-v1/project/vreader-cover.jsx`
  (top + style families, ~80 lines)
- `vreader/Models/ReaderTheme.swift` (current 207 lines —
  three-theme baseline + `epubOverrideCSS`)
- `docs/features.md` row 60 (the contract)

### Files surveyed (grep, not full-read)

- `vreader/Views/Reader/*` — chrome composition surface
- `vreader/Services/Foliate/*` — confirmed Foliate `setStyles`
  injection site for WI-5 font bundling
- `vreader/Resources/` — confirmed `Fonts/` directory does NOT
  exist yet; WI-1 creates it
- `vreader/Views/LibraryView.swift,
  BookCardView.swift, BookRowView.swift` — confirmed card/row split
  exists for WI-8 token pass before WI-9 container pass

### Symbols / signatures verified

- `enum ReaderTheme: String, Codable, CaseIterable, Sendable` —
  exists, three cases (light/sepia/dark). Migration alias is the
  documented path.
- `enum ReaderFontFamily: String, Codable` — exists in
  `TypographySettings.swift`; cases `.system / .serif / .monospace`.
  WI-1 extends with `.sourceSerif4` / `.inter`.
- `ReaderSettingsStore: @MainActor @Observable` — exists; reads
  current `epubTheme` / `txtTheme` / `mdTheme` from `UserDefaults`.
  WI-2 plumbs the new 5-theme picker through the same `@AppStorage`
  keys with value-domain migration.
- `ThemeBackgroundStore` — exists; manages per-theme image assets
  for the existing Sepia/Dark backgrounds. WI-2 extends to the
  Photo theme using the same pipeline.
- `HighlightableTextView` — exists; current UIMenu construction
  lives in `editMenuForTextIn:` delegate method. WI-7 replaces the
  menu for new-selection only; tap-on-existing-highlight (feature
  #53) routes via a different protocol path that WI-7 does NOT
  touch.
- `Notification.Name.readerHighlightTapped` (feature #53 WI-1) —
  exists; WI-7 does NOT post it (different flow).
- `UIFont(name:size:)` — accepts PostScript font names; bundled
  fonts in `Resources/Fonts/` are loaded via `Info.plist`'s
  `UIAppFonts` key. WI-1 adds the key entries.

### Edge cases checked

1. **Existing user has `epubTheme: .warmDark` (the old enum case
   from before the V6 schema)**: confirmed via grep — `.warmDark`
   doesn't exist in current code, so this is a non-issue. The
   current three cases (`light / sepia / dark`) all map cleanly to
   `.paper / .sepia / .dark`.
2. **Font fails to load (corrupt asset, wrong PostScript name)**:
   `ReaderTypography.body(for:)` returns a system-default
   `UIFont.preferredFont(forTextStyle: .body)` fallback. Test asserts
   this on a missing-font fixture.
3. **Photo theme without a chosen image**: `ThemeBackgroundView`
   already handles the nil-image case (existing feature #32
   surface); Photo theme falls back to its solid `.bg` token in
   that case. Documented as known UX.
4. **Status-bar tinting mid-reader-presentation**: SwiftUI's
   `preferredColorScheme` is the standard mechanism; testing shows
   it applies to the reader's hosted view controller. No new API.
5. **CJK content under Source Serif 4**: Source Serif 4 has no CJK
   glyphs; iOS falls through to PingFang SC / Hiragino. Existing
   bug #168 (font-family !important sweep) accommodates this via
   the inherit chain; no special-casing needed.

### Risks accepted (matching the "Risks" section above)

- (a) Typography metric drift — accepted; offset re-projection on
  font change ships in WI-5.
- (b) Photo-theme image WebDAV exclusion — documented; unit-tested
  in WI-10.
- (c) Foliate font bundling — accepted; WI-5 (or WI-5b) ships the
  `.otf` inside the Foliate bundle.
- (d) Per-book theme migration — accepted; deprecated-alias decoder
  in WI-2.
- (e) DI clipping — accepted; cross-tested in WI-6 against existing
  safe-area helper.
- (f) PDF/AZW3 fall-through — accepted; documented as known
  limitations.
- (g) Double-skinning #53/#55 presenters — accepted; out-of-scope
  for this feature, re-skin in follow-up PRs.

### Tests added (per WI)

Listed inline in the WI table above. Approximately 12 new test
files + ~75 test methods across all 10 WIs.

### Tests intentionally deferred

- Pixel-perfect snapshot tests against the design PNGs — vreader has
  no snapshot-test infrastructure. Visual fidelity is verified at
  Gate 5a per-WI by comparing screenshots side-by-side with the
  bundle's `dev-docs/designs/vreader-fidelity-v1/project/screenshots/*.png`.
  This is the established vreader pattern.
- Pixel-perfect rendering of generative covers — accepted; WI-10
  ships composition-only tests for the 5 style families.

### Verdict

Manual audit clean. No Critical/High/Medium findings.

**Plan is ready for Gate 3** when this iteration ends. Next iteration
of the feature cron (or the dedicated feature-60 cron, if re-armed)
will pick up WI-1 (foundational typography) per pick-order
category 2 (PLANNED feature with plan doc → Gate 3).

## Revision history

- 2026-05-15 v1: initial draft + manual-fallback Gate 2 audit
  recorded inline.
- 2026-05-16 v2: WI-3 section revised after Codex Gate 2 round 1
  found 1 High (additive vs schema-narrowing risk over existing
  `String`-typed `Highlight.color` boundary) + 1 Medium (test
  catalogue should emphasize semantic-name rawValue + compatibility
  with existing strings, not hex round-trip). Codex thread
  `019e2d67-9219-71f1-9bda-ffaf13cb4e75`. Plan now specifies
  `NamedHighlightColor` as a UI-domain additive enum with
  `from(storageString:)` decoder and a derived `hex` property,
  leaving `Highlight.color` / `HighlightRecord.color` / backup
  DTOs / export-import payloads on the existing raw-`String`
  schema. `SelectionPopoverAction` confirmed as
  `Equatable + Sendable` only (not `Codable`). Test catalogue
  expanded to 8 NamedHighlightColor tests + 3 SelectionPopoverAction
  tests + 2 AccentColor tests.
- 2026-05-16 v4: WI-5 shipped (Gate 3 + Gate 4). Codex thread
  `019e2e0a-cce5-76f0-97d8-f2d794d71b6e`, 2 rounds, final verdict
  `ship-as-is`. Round 1 caught: (a) WI-5 was incomplete for MD —
  blockquote bodies and fenced-code backgrounds still hard-coded
  `UIColor.secondaryLabel` / `.secondarySystemBackground` (Medium —
  fixed by extending `MDRenderConfig` with `secondaryColor` +
  `codeBackgroundColor` fields plumbed from
  `theme.asV2.subColor` / `.paperColor`); (b) alpha-only assertions
  for `uiSecondaryTextColor` (Low — fixed by full RGB+alpha
  pinning). Round 2: clean. Residual renderer-level test gap
  (Codex flagged as "not a finding") closed inline by adding two
  injection tests proving the new MDRenderConfig fields propagate.
  20+ V2/renderer tests pass; 34 existing MD renderer tests
  continue passing.
- 2026-05-16 v3: WI-4 shipped (Gate 3 + Gate 4). Codex thread
  `019e2de0-9d1a-72d2-860d-f371205cd7bb`, 3 rounds, final verdict
  `ship-as-is`. Round 1 caught: (a) CSS url(...) escape gap +
  bridge-scope risk for off-EPUB-root file:// URLs (Medium —
  fixed via `cssEscapeURL` helper + dormant `nil` URL until later
  WI widens WKWebView access); (b) substring-only test assertions
  that would have passed a swapped-selector regression (Medium —
  fixed via explicit selector→property contracts with whitespace
  normalisation); (c) misleading `<style id="vreader-theme-v2">`
  wrapper at odds with the bridge's fixed `vreader-theme` id (Low —
  fixed by aligning to the bridge). Round 2 caught: (d) escape test
  fooled by `URL.absoluteString`'s own percent-encoding (Low — fixed
  by promoting `cssEscapeURL` to `internal` and adding 4 direct
  unit tests); (e) stale `vreader-theme-v2` references in file
  header + method doc (Low — fixed). Round 3: clean. 19 V2 CSS
  tests pass; 2 pre-existing AZW3 TTS failures tracked at Bug #200
  are out of WI-4 scope.
- 2026-05-16 v4: **WI-6 split into WI-6a + WI-6b**. WI-6a (foundational
  button-slot enum contract — `ReaderTopChromeSlot`, `ReaderBottomChromeButton`,
  accessibility-identifier contracts, accent-slot predicate; 7
  contract tests in `ReaderChromeButtonContractTests`) ships
  immediately as a no-UI-change foundational slice. WI-6b (the
  actual chrome view restructure that consumes those enums)
  **BLOCKED: needs-design (#760)** because the committed design
  bundle does not place in-Reader **Search** anywhere in the new
  chrome — shipping the bundle as-designed would leave Search
  unreachable from Reader (regression of an existing affordance).
  Filed GH #760 (`Design needed: in-Reader Search placement for
  Feature #60 WI-6 chrome re-skin`, labels `enhancement` +
  `needs-design`) per rule 51. WI-6b resumes once a fresh design
  bundle commits Search placement (and optional More-menu content).
  TTS is not blocked because WI-7's SelectionPopover "Read" action
  is the design's TTS entry point and ships independently.
- 2026-05-16 v5: **WI-7 split into WI-7a + WI-7b**. WI-7a
  (foundational SelectionPopover view + action-row contract;
  `SelectionPopoverActionRow` enum with Note/Translate/AskAI/Read
  visible-action contract, `SelectionPopoverView` SwiftUI overlay
  rendering the design's 4-color row + 4-action toolbar with Ask
  AI as the accent slot, file-private hex → Color helper) ships
  immediately as a no-UI-regression slice. The view is built and
  exercised in unit tests but the legacy long-press path
  (`TXTBridgeShared.buildReaderEditMenu`) is untouched — production
  long-press still surfaces the existing UIMenu. WI-7b will replace
  the UIMenu with a presenter that mounts `SelectionPopoverView`
  and wires the action callbacks through to the highlight / note /
  translate / AI / TTS pipelines. Splitting like this preserves
  the no-regression slice + isolates the bigger UIMenu-replacement
  diff (which spans TXT non-chunked, TXT chunked, MD, EPUB
  long-press handlers) into its own audited PR.
