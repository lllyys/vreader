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
| WI-1a | Foundational | `ReaderTypography` registry + extend `ReaderFontFamily` with `.sourceSerif4` / `.inter`. **No view change** — dormant infra. Tests: registry load, fontDescriptor availability, fallback chain. | ~6 files, ~250 LOC |
| WI-1b | Behavioral — **SHIPPED v3.24.5** | Bundle the actual Source Serif 4 + Inter `.otf` binaries into `vreader/Resources/Fonts/` + `UIAppFonts` registration. **Shipped 2026-05-16** (PR #778): 7 faces — SourceSerif4 Regular/It/Bold/BoldIt (Source Serif 4.005) + Inter Regular/Medium/SemiBold (Inter 4.1); both SIL OFL 1.1, license texts vendored, fonts bundled unmodified (satisfies Source Serif 4's Reserved Font Name 'Source'). `ReaderTypography.body(for: .sourceSerif4 / .inter)` now resolves the real faces instead of the Georgia/system fallback. Reclassified Foundational → **Behavioral**: WI-4/5/7 (already merged) consume the registry + `cssFontStack`, so bundling the binaries flips real rendering for users who select Source Serif 4 / Inter. Gate 4: Codex 019e2ed0 + 019e2ed5, 2 rounds, ship-as-is. The deferral (external font fetch + OFL verification) was discharged in an interactive session — the user directed the fetch from official GitHub releases. **Unblocks** WI-5's typography Gate-5a device-verify, the Foliate font-bundling slice, and the Gate 5b acceptance pass. GH #774 closed. | font binaries (~2.9 MB) + Info.plist |
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

- **WI-7a (foundational, shipped):**
  `SelectionPopoverActionRowTests` — 8 contract tests pinning case
  count + order matching design (Note / Translate / Ask AI / Read),
  mapping to `SelectionPopoverAction` dispatch cases, accent slot
  (Ask AI), stable accessibility identifiers, well-formed SF Symbol
  names. `SelectionPopoverView` SwiftUI overlay built and
  compile-validated; no production wiring (long-press still routes
  through the legacy UIMenu via `TXTBridgeShared.buildReaderEditMenu`).
- **WI-7b (foundational, shipping):**
  `SelectionPopoverActionRouter` pure-logic glue mapping a
  `SelectionPopoverAction` to the existing reader-bridge notification
  surface (`.readerHighlightRequested`, `.readerAnnotationRequested`,
  `.readerTranslateRequested`). Returns a `Result` enum
  (`.dispatched(name)` | `.deferredNotYetWired(action)`) so the
  deferred `.askAI` / `.read` cases are explicit rather than silent
  no-ops. `userInfo["color"]` carries the chosen
  `NamedHighlightColor.rawValue` as an additive payload — existing
  observers that ignore `userInfo` continue to fall back to the
  pipeline's default "yellow" color. 10 router tests pin the
  contract enum-case-exhaustively. **No production wiring yet** —
  the router exists; WI-7c will call it from the production
  long-press path.
- **WI-7c1 (foundational, shipping):**
  Presentation infrastructure for the long-press popover.
  `SelectionPopoverPresenter.swift` adds (a) the
  `.readerSelectionPopoverRequested` notification name, (b) a small
  `SelectionPopoverRequest` enum with `post(selection:on:)` and
  `selection(from:)` helpers (typed wire format), and (c) a
  `SelectionPopoverPresenterModifier` SwiftUI ViewModifier that
  observes the notification, stashes the latest selection in
  `@State`, and presents `SelectionPopoverView` (WI-7a) as a sheet.
  Tap callbacks route through `SelectionPopoverActionRouter`
  (WI-7b). **No production bridge has been swapped yet** — legacy
  `TXTBridgeShared.buildReaderEditMenu` still drives long-press in
  every bridge. 6 contract tests pin the notification name + parse
  / post round-trip + tolerance for invalid payloads.
- **WI-7c2 (behavioral, separate PR):** TXT non-chunked bridge.
  Replace the long-press `UIMenu` built by
  `TXTBridgeShared.buildReaderEditMenu` with
  `SelectionPopoverRequest.post(selection:on:)` from the bridge's
  `editMenuInteraction` delegate (return an empty menu to suppress
  the iOS surface) and attach
  `.selectionPopoverPresenter(theme:)` to `TXTReaderContainerView`.
  Slice verify on TXT war-and-peace fixture.
- **WI-7c3 (behavioral, separate PR):** TXT chunked bridge. Mirror
  the WI-7c2 swap in `TXTChunkedReaderBridge`.
- **WI-7c4 (behavioral, shipped v3.24.8 / PR #783):** MD bridge.
  Producer side was already shared via `TXTTextViewBridge` (MD
  renders through it; WI-7c2's `editMenuForTextIn` swap covered MD
  implicitly). This WI attached `.selectionPopoverPresenter(theme:)`
  to `MDReaderContainerView`. 8-line diff. Codex `019e2ef0`, 1
  round, ship-as-is.
- **WI-7c5a (foundational, separate PR):** Typed payload + request-
  token plumbing in the shared popover infrastructure. Per Codex
  plan-v10 round 2 High: storing the token only in `userInfo` and
  re-scraping at action time loses it across the
  post→present→tap→route chain. Fix: introduce a typed payload that
  carries the token through the in-memory state.
  Changes:
  1. **New type**: `SelectionPopoverRequestPayload { let selection:
     TextSelectionInfo; let requestToken: UUID? }`, `Equatable +
     Sendable`. Defined adjacent to `SelectionPopoverRequest` in
     `SelectionPopoverPresenter.swift` (or a new file if size
     warrants).
  2. **`SelectionPopoverRequest.post(selection:on:requestToken:)`**:
     builds the payload and sets it as the notification `object`
     (not bare `TextSelectionInfo`). Default `requestToken: nil`
     for back-compat against TXT/MD/chunked producers that don't
     need identity.
  3. **`SelectionPopoverRequest.payload(from:)`** (replaces
     `selection(from:)`): returns the payload, accepting both the
     new shape (`object as? SelectionPopoverRequestPayload`) and
     the legacy bare-`TextSelectionInfo` shape (wraps with
     `requestToken: nil`). Migration-safe.
  4. **`TXTBridgeShared.postSelectionNotification(name:from:range:chunkOffset:requestToken:)`**:
     adds an optional `requestToken` parameter (default `nil`).
     Existing TXT/MD/chunked call sites (which all pass `nil`)
     compile unchanged.
  5. **`SelectionPopoverPresenterModifier`**: changes `@State
     private var pending: TextSelectionInfo?` to `@State private
     var pending: SelectionPopoverRequestPayload?`. The
     `.onReceive` handler calls `payload(from:)` instead of
     `selection(from:)`. The sheet's `selection.selectedText`
     access becomes `pending.selection.selectedText`.
  6. **`SelectionPopoverActionRouter.route(action:payload:notificationCenter:)`**:
     signature change from `(action, selection)` to `(action,
     payload)`. Reads `payload.requestToken` and, when non-nil,
     attaches it to the resulting action notifications via
     `userInfo["selectionRequestToken"] as UUID` (Codex round 2
     Medium: UUID-not-String — notifications are in-process, no
     `Codable` boundary, so storing as `UUID` preserves type
     safety).
  Token is **optional everywhere** — existing TXT/MD/chunked
  posters that pass `nil` continue to work; consumers that don't
  care (TXT/MD via `ReaderNotificationModifier`) ignore the
  `userInfo` key; only EPUB looks it up.
  **No production behavior change** — the token field is `nil`
  for all current posters; the typed payload is a structural
  refactor of the in-memory state. The shared popover continues
  to present the same view for the same inputs.
  Tests: round-trip token through post → parse → router → action
  notification (`userInfo["selectionRequestToken"] as? UUID` ==
  posted UUID); nil-token compatibility (legacy bare-
  `TextSelectionInfo` object form decodes via `payload(from:)`
  with `requestToken: nil`); router does NOT attach the userInfo
  key when token is nil. ~150 LOC across
  `SelectionPopoverPresenter.swift`, `SelectionPopoverActionRouter.swift`,
  `TXTBridgeShared.swift`, and 3 test files (presenter +
  action-router + TXT bridge tests).
  Foundational tier — structural refactor of internal types; no
  user-visible delta on any of the 4 already-swapped paths.
- **WI-7c5b (behavioral, separate PR):** EPUB producer/consumer
  swap using the WI-7c5a token. Four layered changes:
  1. **Producer** (in `EPUBReaderContainerView.onSelectionEvent`
     closure, **NOT** `EPUBWebViewBridgeCoordinator` per Codex
     plan-v10 round 1 Medium finding — bridge stays presentation-
     agnostic): cache the `ReaderSelectionEvent` keyed by a freshly
     minted `UUID` request token in a single-entry token→event
     cache `@State pendingEPUBSelection: (token: UUID, event:
     ReaderSelectionEvent)?` (per Codex round 2 Low: not a
     general map, a single pending entry that's replaced on each
     new selection). Post `.readerSelectionPopoverRequested` via
     `SelectionPopoverRequest.post(selection:on:requestToken:)`
     with that token. The legacy `pendingSelectionEvent` +
     `showHighlightSheet` flow is removed.
  2. **Consumer attach**: `.selectionPopoverPresenter(theme:)` on
     `EPUBReaderContainerView.body`.
  3. **EPUB-side action handlers**: `.onReceive` on
     `.readerHighlightRequested` + `.readerAnnotationRequested` —
     each handler extracts `userInfo["selectionRequestToken"] as?
     UUID` (UUID type per Codex round 2 Medium, not String), looks
     up the cached event from `pendingEPUBSelection` (token must
     match), and routes to existing helpers. Highlight: call
     `handleHighlightAction(event:container:color:)` with the
     chosen color from `resolveHighlightColor(from:)`. Note:
     set `pendingSelectionEvent = event` (preserved as the
     parameter that `noteInputSheet` consumes — that sheet's
     internals don't change) + `showNoteSheet = true`. Cache entry
     is removed after consumption + on sheet dismiss to bound
     memory + prevent stale-action races.
  4. **Color parameter on `handleHighlightAction`**:
     `handleHighlightAction(event:container:color:)` gains a
     `color: String` parameter (default `"yellow"` for the
     feature-#53 WI-4 call site to preserve behavior). Internally
     calls `coordinator.create(..., color:)` /
     `persistence.addHighlight(..., color:)` — both already accept
     color. The plan does **NOT** modify `EPUBHighlightActions.persistHighlight`
     signature (per Codex plan-v10 round 1 Low — that's a fallback
     helper, color flows through the locator-level call instead).
  **Removed legacy surface**:
  - `.confirmationDialog(...)` with Highlight / Add Note / Copy /
    Cancel
  - `@State var showHighlightSheet`
  - `onSelectionEvent: { event in pendingSelectionEvent = event;
    showHighlightSheet = true }` is replaced with the producer
    described in (1)
  **Copy regression — explicit acceptance**: the legacy EPUB
  `confirmationDialog` had a `Copy` action that the new
  `SelectionPopoverView` does NOT have. This regression is
  **accepted as scope-of-WI-7** (Codex plan-v10 round 1 High
  flagged it; product call recorded here). The TXT/MD legacy
  surfaces also lost their iOS-default Copy when WI-7c2/c3/c4
  returned an empty `UIMenu`; EPUB's swap is consistent. If user
  feedback warrants, a follow-up may add `.copy` to
  `SelectionPopoverAction` + a Copy button slot to the action row;
  filed as a deferred-IDEA row, NOT a regression bug.
  Tests:
  - Producer post: container `onSelectionEvent` closure caches
    event + posts notification with non-nil token; cache size
    stays at 1.
  - Token→event resolution: happy path (action notification with
    matching token resolves to cached event); miss (action
    notification with unknown token is a no-op, NOT a crash);
    same-text duplicate selections at different DOM anchors
    (each gets a distinct token, both resolve correctly when
    actioned in sequence).
  - Stale-action handling: cache cleared on sheet dismiss → action
    notification with stale token is a safe no-op.
  - Legacy absence (negative pin): `confirmationDialog` no longer
    appears in the view body (search assertion).
  - `color:` parameter propagation: explicit per-color persistence
    smoke test.
  Device verify (Gate 5a): long-press in mini-epub3 fixture,
  popover appears, tap each of the 4 colors (one per run),
  HighlightRecord persisted with chosen color, the CSS Highlight
  API renders it. **Out of scope for verification this WI**:
  EPUB content inside iframes (the existing JS bridge is
  document-scoped; iframe support is a pre-existing limitation
  documented in `EPUBHighlightJS.swift`; cross-frame selection has
  never worked in EPUB and is not introduced or regressed by this
  swap). Behavioral tier. ~250 LOC.
- **Why WI-7c5 split** (per Codex Gate 2 plan-v10 round 1 audit +
  pre-swap read pass): EPUB's selection model is fundamentally
  different from TXT/MD's. TXT/MD use UTF-16 offsets in the source
  string; EPUB uses a `EPUBSerializedRange` (DOM
  `startContainerPath` + `startOffset` + `endContainerPath` +
  `endOffset`). The WI-7c1 presenter infrastructure was designed
  around `TextSelectionInfo` (UTF-16 offsets only) and can't carry
  EPUB anchors directly. Two approaches were considered: (a)
  extend `TextSelectionInfo` with optional EPUB anchors — rejected,
  pollutes a TXT/MD-focused type; (b) **request-token plumbing** —
  shared types stay simple (`TextSelectionInfo` unchanged), the
  notification carries an optional opaque `UUID` token in
  `userInfo`, and each format may stash an extra payload keyed by
  that token in a local registry. Accepted. WI-7c5a foundationally
  ships the token plumbing across `SelectionPopoverRequest` +
  `SelectionPopoverActionRouter`; WI-7c5b ships the EPUB-side
  producer/consumer with a registry keyed by the token. Identity-
  by-token is robust against same-text reselection at different
  DOM anchors and against dismiss/action timing races (each
  selection mints a fresh UUID; stale actions become safe no-ops).
- **Regression guard** (all of WI-7c2..7c5): tap-on-existing-
  highlight path (feature #53) still routes through
  `HighlightActionPresenting`, unchanged.
- Device verify (Gate 5a) — **WI-7c2..7c5 only**: long-press in
  each format's fixture, confirm popover; tap a color, confirm
  HighlightRecord persisted with the chosen color. WI-7a, WI-7b,
  and WI-7c1 are foundational (no UI delta in production) so unit
  + integration tests + audit are sufficient per the rule 47 Gate 5
  matrix.

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
- 2026-05-16 v5: **WI-6 split into WI-6a + WI-6b**. WI-6a (foundational
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
- 2026-05-16 v6: **WI-7b further split into WI-7b (foundational router)
  + WI-7c (behavioral wiring)**. WI-7b now ships
  `SelectionPopoverActionRouter` — the pure-logic enum-glue mapping a
  `SelectionPopoverAction` to the existing
  `.readerHighlightRequested` / `.readerAnnotationRequested` /
  `.readerTranslateRequested` notification surface. The router
  returns a discriminated `Result` (`.dispatched(name)` |
  `.deferredNotYetWired(action)`) so the deferred `.askAI` / `.read`
  cases are explicit rather than silent no-ops; `userInfo["color"]`
  carries `NamedHighlightColor.rawValue` as an additive payload
  (existing observers fall back to "yellow"). 10 router tests pin
  the contract enum-case-exhaustively. Codex Gate 4 audit thread
  `019e2e83-0999-70f1-bb9c-f965bb6e8909`, 1 round, final verdict
  `ship-as-is` — no findings on dimensions 1-8. **What was previously
  scoped as WI-7b** (production view-wiring across TXT non-chunked /
  TXT chunked / MD / EPUB long-press handlers) is renamed to **WI-7c
  (behavioral, separate PR)**. The split keeps the foundational
  pure-logic dispatch contract independently audited and merge-able
  before the larger UIMenu-replacement diff lands. WI-7c carries the
  Gate 5a device-verify obligation (4-color HighlightRecord
  round-trip on TXT and MD fixtures); WI-7b is foundational so
  unit + integration tests + audit are sufficient per rule 47 Gate
  5.
- 2026-05-16 v8: **WI-7c split into WI-7c1 + WI-7c2..7c5.** WI-7c1
  ships the foundational presentation infrastructure: the
  `.readerSelectionPopoverRequested` notification name, a small
  typed `SelectionPopoverRequest` enum (`post(selection:on:)` +
  `selection(from:)`) for bridges to call and the modifier to read,
  and the `SelectionPopoverPresenterModifier` SwiftUI ViewModifier
  that observes the notification, holds the pending
  `TextSelectionInfo` in `@State`, and presents
  `SelectionPopoverView` (WI-7a) as a sheet. Tap callbacks route
  through `SelectionPopoverActionRouter` (WI-7b). 6 contract tests
  pin the notification name + parse / post round-trip + tolerance
  for invalid payloads. No production bridge has been swapped — the
  legacy `TXTBridgeShared.buildReaderEditMenu` still drives every
  bridge's long-press. WI-7c2..7c5 land the per-bridge swap one PR
  per bridge (TXT non-chunked, TXT chunked, MD, EPUB). Codex Gate
  4 audit thread `019e2ea9`, 2 rounds, ship-as-is — round 1 raised
  1 Medium (deferred-action sheet-dismiss would silently swallow
  taps once bridges swap) + 1 Low (docs/architecture.md notification
  bus drift). Medium fixed via new
  `SelectionPopoverDismissPolicy.nextPending(after:currentSelection:)`
  pure-logic helper (4 new dismiss-policy tests pin the contract;
  `TextSelectionInfo` gained additive `Equatable + Sendable`
  conformance so tests can compare). Low fixed via new arch.md
  Notification Bus row. Round 2 clean. Splitting like this lets the
  presenter contract be independently audited + the per-bridge
  swaps stay reviewable as isolated diffs.
- 2026-05-16 v7: **WI-6b UNBLOCKED — #760 design gap closed.** A
  fresh claude.ai/design handoff (share token
  `SEI7UfqurCl2Kuj6ctt__Q`) delivered the in-Reader Search placement
  + More-menu design that WI-6b was blocked on. The design note
  `design-notes/reader-search-and-more-menu.md` is committed under
  `dev-docs/designs/vreader-fidelity-v1/`. Decisions it pins:
  (1) **Search stays in the top chrome** between back-to-Library and
  Bookmark (`← Library | Title | 🔍 📑 ⋯`) — bottom toolbar is for
  in-place tools, Search is a jump-elsewhere action; rejection
  rationale recorded for the 4 alternatives. (2) **More menu = an
  anchored popover** from `⋯` with 6 items split by a divider
  (Read aloud, Auto-turn pages [toggle], Bilingual mode [toggle] |
  Book details, Share, Export annotations); closed/open/toggles-on
  states + per-theme rendering (all 5 themes) specified. (3) The
  top-bar icons get `accessibilityIdentifier`s matching WI-6a's
  `ReaderChromeButton` enum — `reader.chrome.search`,
  `reader.chrome.bookmark`, `reader.chrome.more`. Explicitly NOT in
  the menu: Search (top bar), Display/Contents/Notes/AI (bottom
  toolbar), Settings (Library-global), renderer switch (DEBUG-only).
  The note's §4 defers the Book Details sheet contents to a
  follow-up issue. **WI-6b is no longer `BLOCKED: needs-design` —
  it may now enter Gate 3.** GH #760 resolved + closed.
- 2026-05-16 v8: **WI-1 split into WI-1a + WI-1b; WI-1b deferred as a
  manual-ops step.** WI-1a (the `ReaderTypography` registry +
  `ReaderFontFamily` `.sourceSerif4` / `.inter` cases — pure code,
  dormant infra) is the cron-implementable half. WI-1b — vendoring
  the actual Source Serif 4 + Inter `.otf` binaries into
  `vreader/Resources/Fonts/` and registering them under `UIAppFonts`
  — is **deferred**: it requires fetching external font assets and
  verifying their licenses (both fonts are SIL OFL; the OFL text
  must be vendored alongside and the verification recorded), which a
  cron session cannot safely do (no external-binary fetch, no
  licensing judgement). A human performs WI-1b. **Downstream gate**:
  until WI-1b lands, `ReaderTypography.body(for:)` falls back to
  system fonts on device — so the typography legs of WI-5's Gate 5a
  device-verify, the Foliate font-bundling slice (Risk (c)), and the
  final Gate 5b acceptance pass cannot confirm "Source Serif 4
  renders". Those verifications are now explicitly gated on WI-1b.
  Tracked as GH #774.
- 2026-05-16 v9: **WI-1b SHIPPED (v3.24.5, PR #778).** The deferred
  manual-ops step was discharged in an interactive `/feature-workflow`
  session — the user directed fetching the binaries from the official
  GitHub releases (`adobe-fonts/source-serif` 4.005, `rsms/inter`
  4.1). 7 `.otf` faces vendored in `vreader/Resources/Fonts/`; both
  SIL OFL 1.1 license texts committed alongside; `UIAppFonts`
  registers all 7. Source Serif 4's Reserved Font Name 'Source' is
  satisfied — fonts bundled verbatim under their original names (the
  RFN only restricts modified derivatives). WI-1b **reclassified
  Foundational → Behavioral**: when the plan first deferred it the
  registry was dormant, but WI-4/5/7 have since merged and consume
  `ReaderTypography` + `cssFontStack`, so bundling the binaries flips
  real rendering. Gate 4: Codex `019e2ed0` + `019e2ed5`, 2 rounds,
  ship-as-is (round 1: 1 High untracked-assets + 1 Low stale-comments;
  round 2: 1 Low stale-header-ref; all fixed). Gate 5a slice: the
  `bundledFace_resolvesByPostScriptName` parameterized test proves all
  7 faces register + resolve via `UIFont(name:)` in the app-bundle
  test host. **Downstream gate lifted** — WI-5's typography Gate-5a
  device-verify, the Foliate font-bundling slice (Risk (c)), and the
  Gate 5b acceptance pass are no longer blocked on WI-1b. GH #774
  closed.
- 2026-05-16 v10: **WI-7c5 split into WI-7c5a (foundational) + WI-7c5b
  (behavioral).** Pre-swap read pass discharged the v8 hand-wave
  ("EPUB bridge. Replace the long-press menu path — needs a
  pre-swap read pass"). EPUB's selection model is
  `EPUBSerializedRange` (DOM `startContainerPath` + `startOffset` +
  `endContainerPath` + `endOffset`), incompatible with
  `TextSelectionInfo`'s UTF-16 offsets. **Codex Gate 2 round 1**
  (thread `019e2ef9-e2eb-7942-822c-708bbba50a07`) flagged 2 High +
  3 Medium + 1 Low against an initial cache-by-`selectedText`
  draft. Findings + resolutions:
  - **High** — cache-by-`selectedText` is fragile (same-text
    reselection at different DOM anchors, dismiss/action timing
    races). **Fixed** by replacing with request-token plumbing:
    `SelectionPopoverRequest.post(...)` gains an optional
    `requestToken: UUID`; `SelectionPopoverActionRouter` passes it
    through to action notifications' `userInfo`; EPUB stashes the
    event keyed by token. Identity-by-token is stable.
  - **High** — removing the legacy EPUB `confirmationDialog`
    drops `Copy`, which the new `SelectionPopoverView` lacks.
    **Resolution**: explicitly accept Copy removal as in-scope
    (consistent with TXT/MD post-WI-7c2..c4 losing iOS-default
    Copy when the empty `UIMenu` returned). Recorded as a product
    decision in the WI-7c5b description; a follow-up may add
    `.copy` to `SelectionPopoverAction` if feedback warrants
    (deferred-IDEA, not a regression bug).
  - **Medium** — WI-7c5a as initially drafted "rebranded existing
    state" (`pendingSelectionEvent` already exists). **Fixed** by
    redefining WI-7c5a as request-token plumbing in the shared
    popover infrastructure (genuine foundational generalization),
    not as adding duplicate EPUB cache state.
  - **Medium** — producer swap was at the wrong layer
    (`EPUBWebViewBridgeCoordinator.handleSelectionMessage`
    couples bridge plumbing to popover presentation). **Fixed** by
    moving the producer swap into `EPUBReaderContainerView`'s
    `onSelectionEvent` closure, keeping the bridge coordinator
    unchanged.
  - **Medium** — test catalogue too thin; missing same-text
    duplicate selections / stale-action / no-cache cases.
    **Fixed** by expanding the WI-7c5b test list to include
    distinct-DOM-anchor same-text selections, stale-action
    after-dismiss handling, and explicit iframe-content out-of-
    scope documentation.
  - **Low** — `color:` parameter scope overstated (don't need to
    touch `EPUBHighlightActions.persistHighlight` directly; the
    color flows through `coordinator.create(..., color:)` and
    `persistence.addHighlight(..., color:)` which both already
    accept color). **Fixed** by narrowing WI-7c5b to only modify
    `handleHighlightAction(event:container:color:)`.
  **Codex Gate 2 round 2** (same thread): 1 High + 1 Medium + 1
  Low. **High** — initial token plumbing was incomplete (token in
  `userInfo` only; presenter held bare `TextSelectionInfo` in
  state; router took `(action, selection)`; token lost across the
  post→present→tap→route chain). **Fixed** by introducing typed
  `SelectionPopoverRequestPayload { selection: TextSelectionInfo,
  requestToken: UUID? }` carried as the notification's `object`,
  threaded through `@State pending: SelectionPopoverRequestPayload?`
  in the presenter modifier, and into
  `SelectionPopoverActionRouter.route(action:payload:notificationCenter:)`.
  Token rides the in-memory state, not re-scraped from `userInfo`
  at action time. **Medium** — `userInfo["selectionRequestToken"]:
  String` was the wrong tradeoff ("Codable-friendliness" is
  irrelevant for in-process notifications). **Fixed** by using
  `as? UUID` directly. **Low** — `[UUID: ReaderSelectionEvent]`
  registry overstated single-entry behavior. **Fixed** by
  tightening to `(token: UUID, event: ReaderSelectionEvent)?`
  single pending entry, replaced on new selection. **Codex Gate 2
  round 3** (same thread): **"no new findings."** Quoted verdict:
  *"The revised WI-7c5 decomposition is coherent and ready to
  move from Gate 2 to Gate 3 ... Token identity is preserved
  across post → present → tap → route via a typed
  `SelectionPopoverRequestPayload`, so EPUB no longer depends on
  fragile text matching ... `UUID` in `userInfo` is the right
  shape for these in-process notifications ... The EPUB cache is
  now correctly scoped as a single pending `(token, event)` entry
  ... Producer ownership is at the container, not the bridge
  coordinator, which is the cleaner boundary."* Gate 2 closed
  after 3 rounds — within the rule-47 limit. **WI-7c5a + WI-7c5b
  may now enter Gate 3.**
