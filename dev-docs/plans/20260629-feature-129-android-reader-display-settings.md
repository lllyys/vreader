# Feature #129 — Android reader display settings (the "Display" / Aa sheet)

Parity-checklist item **E** — the typography slice. The "Display" settings sheet (the Aa entry) applied
across the Android readers: the 5 reader themes, font family/size, line spacing, and horizontal margin —
persisted and applied live. iOS parity: #60 WI-10 (`ReaderSettingsStore` + `ReaderThemeV2` +
`TypographySettings`).

> **Scope note (Gate-2 round-2, Medium):** checklist item E also lists the **layout (scroll/paged)**
> toggle. #129 deliberately does NOT include it — TXT/MD are scroll-only Compose hosts, so a layout
> toggle would be a non-functional control there (the established "omit non-functional controls"
> precedent). Layout is tracked as a **separate follow-up feature** (needs a paged TXT/MD renderer
> first). Therefore **box E checks only when BOTH #129 (typography) AND the layout follow-up are
> VERIFIED** — #129 alone does not complete item E. `docs/features.md` #129 + the checklist box-E note
> are updated to say so at the PLANNED flip.

## Problem

The Android readers (EPUB/TXT/MD/PDF/AZW3) render with **hardcoded** styling — only the Paper theme
exists (`VReaderColors`), font size/family/spacing are fixed per host, and there is no way for a user
to change how a book looks. iOS has had a full reader-display system (5 themes, typography, layout)
since #60 WI-10. This feature brings that to Android: a persisted `ReaderSettings` model + the designed
"Display" sheet + per-host application, so a reader looks the way the user chose and the choice sticks.

## Surface area (file-by-file, concrete signatures)

### New — foundational model + store

- `android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderTheme.kt` (new):
  `enum class ReaderTheme { Paper, Sepia, Dark, Oled, Photo }` with color accessors mirroring the iOS
  `ReaderThemeV2` (exact RGB from the design / `ReaderThemeV2.swift`): `background`, `ink`, `inkMuted`,
  `accent`, `surface`/`chrome`, `isDark`. Compose `Color` values.
  - Design colors (committed `vreader-themes.jsx`): Paper `bg #f4eee0 / ink #1d1a14 / accent #8c2f2f`,
    Sepia `#e6d6b6 / #3a2913 / #7a3a1f`, Dark `#1a1815 / #d8d2c5 / #d6885a`, Oled `#000 / #b9b6b0 /
    #d6885a`, Photo `#2a2520 / #e8e0d0 / #e8b465`.
- `android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettings.kt` (new): a value type
  `data class ReaderSettings(theme: ReaderTheme, fontFamily: ReaderFontFamily, fontSizeSp: Float,
  lineSpacing: Float, marginDp: Float)` + `enum class ReaderFontFamily { Serif, Sans }`. Default = the
  current look (Paper / Serif / 18sp / 1.5 / 20dp). Ranges (from the design): fontSize 13–26, lineSpacing
  1.3–2.0, margin 16–48. **The layout (paged/scroll) toggle is OMITTED from #129** (Library precedent —
  TXT/MD are scroll-only Compose hosts, so a layout toggle would be a non-functional control for them;
  EPUB keeps its current scroll default, AZW3 its current mode). Layout is a deferred follow-up once
  paged TXT/MD exists. Brightness is device-screen-brightness, not a render setting — also deferred.
- `android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt` (new):
  `class ReaderSettingsStore(dataStore: DataStore<Preferences>)` following the **OpdsSourceStore /
  AiProviderStore / WebDavServerStore** DataStore precedent. Exposes `val settings: StateFlow<ReaderSettings>`
  (or `Flow` + a cached `StateFlow` in the VM) and suspend setters `setTheme/setFontFamily/setFontSize/
  setLineSpacing/setMargin` that persist each field (clamped to its range). One instance in
  `VReaderApp` (DI container) — global, not per-book (iOS #60 is global; per-book overrides are out of
  scope).

### New — the designed "Display" sheet + entry

- `android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheet.kt` (new): a Compose
  `ModalBottomSheet` recreating the committed `vreader-panels.jsx` `ReaderSettingsSheet` (title
  **"Display"**): theme 5-button row, font-family 2-button toggle, and sliders for font-size /
  line-spacing / margin. (Layout toggle + brightness OMITTED per the model note above.) Pure function of
  `ReaderSettings` + callbacks; extracted content composable for direct UI testing (the #127 sheet
  precedent). Uniform across the reflowable readers (EPUB/TXT/MD/AZW3) — every control applies to all of
  them, so no per-format hiding (which the Gate-2 audit flagged as a fidelity risk).
- The **entry** — `android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderBottomChrome.kt` (new):
  the **designed** `ReaderBottomChrome` from `vreader-reader.jsx` (a bottom bar = a progress scrubber + a
  row of slot affordances Contents / Notes / Display / AI). **Gate-2 ruled (Critical) that a standalone Aa
  button is NOT design-grounded** — the design shows Display only *inside* this chrome. So #129 builds the
  real `ReaderBottomChrome`, shipping the **Display slot + the progress scrubber functional** and
  **omitting** the Contents / Notes / AI slots until their features land — the established `LibraryScreen`
  nav-bar precedent ("the design's settings + search pills are added when those features land; shipping
  non-functional controls is a fidelity defect, so they're omitted now"). Contents (TOC/bookmarks), Notes
  (annotations), and AI are added by feature **F** / **D** later; #129 owns the bottom-chrome shell. (The
  TXT `TtsEntryBar` — itself a non-designed centered "Read aloud" simplification per the Gate-2 finding —
  is reconciled in WI-3 (the chrome host wiring): either its action moves to a chrome slot or it stays
  until F formalizes the TTS slot.)

### Modified — per-host application

- `reader/TxtReaderActivity.kt`: thread `ReaderSettings` (collected via `collectAsStateWithLifecycle`)
  into the `Text` composable — `fontSize`, `lineHeight`, `fontFamily`, `color` (theme ink), the
  `Surface`/background (theme background), and the horizontal `padding` (margin). Add the Display entry.
  **MD reuses this host** (#112) so MD's `MarkdownRenderer` `SpanStyle`s inherit the same settings
  (size scale, family, theme color).
- `reader/ReaderActivity.kt` (EPUB / Readium): apply settings through **Readium 3.3.0 `EpubPreferences`**
  — confirmed (Gate-2, via jar inspection) to expose `fontSize`, `fontFamily`, `lineHeight`,
  `pageMargins`, `backgroundColor`, `textColor`, `scroll`, `theme`. **Readium prefs are unitless
  `Double` multipliers + Readium `Color`/`FontFamily` types, NOT sp/dp — so define exact conversions**
  (the `EpubPreferencesMappingTest` pins them): `fontSize = fontSizeSp / 18.0` (18sp default → 1.0 = 100%;
  13→0.722, 26→1.444); `lineHeight = lineSpacing` (1.3–2.0 already a multiplier); `pageMargins =
  marginDp / 20.0` calibrated so 20dp ≈ the current default margin; `backgroundColor =
  Color(theme.background.toArgb())`, `textColor = Color(theme.ink.toArgb())`; `fontFamily` → Readium
  `FontFamily.SERIF`/`SANS_SERIF`. The 5 themes use explicit `backgroundColor`/`textColor` (Readium's
  `Theme` enum is only light/sepia/dark — insufficient). Submit on change via
  **`EpubNavigatorFragment.submitPreferences(EpubPreferences): Job`** (confirmed present); `scroll` is
  left at its current default (layout out of scope).
- `reader/Azw3ReaderActivity.kt` (foliate-js WebView): inject theme + typography CSS through the foliate
  bridge (mirrors the iOS `ReaderThemeV2+EPUBCSS` blob: `html/body { background-color … color … }`,
  font-family stack, `font-size`, `line-height`, padding). (AZW3 keeps its current reading mode — layout
  toggle is out of #129's scope.)
- `reader/PdfReaderActivity.kt` (PdfRenderer bitmaps): **theme background ONLY** — apply the theme
  background color to the viewer backdrop. Font/size/spacing don't apply to rasterized PDF (it can't
  reflow), and PDF has no Display sheet / no Aa slot (a theme-only reduced sheet would be undesigned —
  rule 51), so PDF silently inherits the theme bg from the global store. (Honest limitation, see Risks R3.)

### Files OUT of scope

- The full reader navigation chrome's OTHER slots (Contents/TOC, bookmarks, Notes, find-in-book, More
  menu, AI) — that's checklist box **F** / feature **D**. #129 builds the `ReaderBottomChrome` shell but
  wires only the Display slot (+ scrubber); the other slots are omitted until their features land.
- **The layout (scroll/paged) toggle** — a tracked **follow-up feature** (not #129). The Compose TXT/MD
  hosts are scroll-only (LazyColumn); a layout toggle needs a paged TXT/MD renderer first, which is a
  separate larger piece. Box E checks only when #129 AND the layout follow-up are both VERIFIED.
- **Screen brightness** — the design's brightness slider controls device brightness, not a reader render
  setting; deferred (it needs `WindowManager.LayoutParams.screenBrightness`, a different concern).
- **Per-book setting overrides** — global only (iOS #60 is global too).
- iOS code, contracts, backup format (display settings are device-local, NOT in the backup contract).

## Prior art / project precedent / rejected alternatives

- **iOS `ReaderSettingsStore`** (`vreader/Services/ReaderSettingsStore.swift`) is the model source of
  truth: `@Observable @MainActor` over UserDefaults, `ReaderThemeV2` (paper/sepia/dark/oled/photo) +
  `TypographySettings` (fontSize 12–64, lineSpacing 1.0–2.0, fontFamily), `EPUBLayoutPreference`. The
  Android `ReaderSettingsStore` mirrors the fields; persistence is DataStore (the Android idiom) not
  UserDefaults.
- **Android DataStore precedent**: `OpdsSourceStore` / `AiProviderStore` / `WebDavServerStore` already
  use `DataStore<Preferences>` — same pattern, no new dependency.
- **Per-host application precedent**: iOS applies per host (EPUB CSS, TXT UITextView attrs, PDF none) —
  Android mirrors (EPUB Readium prefs, TXT Compose attrs, AZW3 foliate CSS, PDF bg-only).
- **Rejected**: (a) a single global Compose theme — readers need independent typography/layout, not app
  chrome theming; (b) Readium's built-in `Theme` enum for the 5 themes — only 3 values, so explicit
  `backgroundColor`/`textColor` prefs instead; (c) building a paged TXT renderer now — out of scope,
  deferred; (d) per-book overrides — global matches iOS.

## Work-item sequencing

| WI | tier | scope | PR size |
|---|---|---|---|
| WI-1 | foundational | `ReaderTheme` (5 themes + colors) + `ReaderSettings` value type (theme/fontFamily/fontSize/lineSpacing/margin — NO layout) + `ReaderSettingsStore` (DataStore) + DI in `VReaderApp`. Tests: store round-trip + clamping + defaults + the 5 theme colors (JVM/Robolectric). | M |
| WI-2 | behavioral | The designed **"Display" `ReaderSettingsSheet`** Compose UI (theme 5-button + font 2-button + size/spacing/margin sliders — no layout toggle) — pure function of `ReaderSettings` + callbacks, rendered standalone (no host wiring yet). Built BEFORE the chrome so the chrome's Display slot has a real sheet to open. Tests: connected UI on the extracted content composable (`useUnmergedTree`). | M |
| WI-3 | behavioral | The designed **`ReaderBottomChrome`** shell (progress scrubber + the Display slot, which opens the WI-2 sheet; Contents/Notes/AI slots **omitted** until F/D land — Library precedent) wired into the reflowable reader hosts; reconcile the TXT `TtsEntryBar`. Tests: connected chrome smoke (the Display slot opens the real sheet; omitted slots absent — no dead placeholders). | M |
| WI-4 | behavioral | **TXT + MD** application: thread settings into `TxtReaderActivity`'s `Text` + `MarkdownRenderer` (fontSize/family/lineHeight/color + margin padding + theme bg). Tests: a JVM mapping test (`ReaderSettings → TextStyle`/`SpanStyle`) FIRST, then a connected re-render-on-change test. | M |
| WI-5 | behavioral | **EPUB** application. Prerequisite: a JVM **`EpubPreferencesMappingTest`** (`ReaderSettings → EpubPreferences` — fontSize/family/lineHeight/pageMargins/backgroundColor/textColor) guarding the Readium-API assumption, THEN wire `submitPreferences()` into `ReaderActivity`. Tests: the mapping test + a connected smoke. | M |
| WI-6 | behavioral | **AZW3** application. Prerequisite: a JVM **`Azw3DisplayCssTest`** (deterministic theme+typography CSS blob, JS-escape-safe), THEN inject via the foliate bridge. Tests: the CSS test + a connected smoke. | M |
| WI-7 | behavioral | **PDF**: apply the **theme background only** to the viewer backdrop (reads the global `ReaderSettingsStore` theme). PDF has **no Display sheet / no Aa slot** — font/size/spacing don't apply to rasterized PDF, and a theme-only reduced sheet would be undesigned (rule 51), so PDF simply inherits the theme bg set from a reflowable reader. Tests: a connected smoke (theme bg applies to the PDF backdrop). | S |
| WI-8 | behavioral (final) | Acceptance on the emulator: open each reflowable format (EPUB/TXT/MD/AZW3), open Display via the chrome, change theme/font/size/spacing/margin, confirm the live render changes + persists across reopen; confirm PDF picks up the theme bg. Evidence file → VERIFIED. | M |

## Test catalogue

- `ReaderSettingsStoreTest` (JVM/Robolectric, WI-1): persist/round-trip each field; clamp out-of-range
  (fontSize 13–26, lineSpacing 1.3–2.0, margin 16–48); default when unset; enum (de)serialization
  (theme/font); the `StateFlow` emits on change.
- `ReaderThemeTest` (JVM, WI-1): the 5 themes' colors match the design RGB exactly; `isDark` correct.
- `ReaderSettingsSheetUiTest` (connected, WI-2, `useUnmergedTree` for in-row testTags per #127): theme
  button → `onTheme`, font toggle → `onFontFamily`, sliders → `onFontSize`/`onLineSpacing`/`onMargin`.
- `ReaderBottomChromeUiTest` (connected, WI-3): the Display slot opens the WI-2 sheet; the omitted
  Contents/Notes/AI slots are absent (no dead placeholders).
- `TxtDisplaySettingsTest` / mapping tests (WI-4): `ReaderSettings → Compose TextStyle` (size sp, family,
  lineHeight, color) + MD `SpanStyle` size-scale; a connected re-render-on-change test.
- `EpubPreferencesMappingTest` (JVM, WI-5): `ReaderSettings → EpubPreferences` with **exact** conversions
  (NOT just "field populated"): default 18sp → Readium `fontSize = 1.0` (100%); min 13sp → `13/18 ≈ 0.722`,
  max 26sp → `26/18 ≈ 1.444` (bounded scale); lineSpacing 1.3–2.0 → `lineHeight` the same Double;
  marginDp → `pageMargins` (the Readium pageMargins multiplier, calibrated so 20dp ≈ the current default);
  the 5 themes → Readium `Color(backgroundColor)`/`Color(textColor)` from the theme RGB; fontFamily →
  Readium `FontFamily`. Cases: default, min, max, each theme's color conversion. Runs BEFORE WI-5 wiring.
- `Azw3DisplayCssTest` (JVM, WI-6): the generated CSS blob for each theme + typography (deterministic
  string), JS-escaping safe (FoliateJSEscaper analog); runs BEFORE the WI-6 UI wiring.
- `ReaderDisplayAcceptanceTest` / per-host connected smokes (WI-8): the end-to-end flow.

## Risks + mitigations

- **R1 — Display entry (rule 51) — RESOLVED by Gate-2 round 1**: a standalone Aa button is NOT
  design-grounded (the design shows Display only inside `ReaderBottomChrome`). #129 now builds the
  **designed `ReaderBottomChrome`** shell (WI-3) with the Display slot + scrubber functional and the
  Contents/Notes/AI slots **omitted until F/D land** (the `LibraryScreen` nav-bar "omit non-functional
  controls" precedent). Nothing not depicted is added; #129 owns the chrome shell, F/D extend it.
- **R2 — Readium 3.3.0 `EpubPreferences` — RESOLVED by Gate-2 round 1**: confirmed (jar inspection) to
  expose `fontSize`, `fontFamily`, `lineHeight`, `pageMargins`, `backgroundColor`, `textColor`, `scroll`,
  `theme`; `EpubNavigatorFragment.submitPreferences(EpubPreferences): Job` is the live-submit seam. The
  5 themes map to explicit `backgroundColor`/`textColor`. `EpubPreferencesMappingTest` (WI-5) is the guard.
- **R3 — PDF can't reflow**: rasterized PDF can't apply font/size/spacing. Mitigation: PDF gets the
  **theme background only** (reads the global store) and has **no Display sheet / no Aa slot** — a
  theme-only reduced sheet would be undesigned (rule 51), so PDF silently inherits the theme bg.
- **R4 — layout (paged/scroll) scoped OUT of #129**: TXT/MD are scroll-only Compose hosts; a layout
  toggle would be a non-functional control for them (fidelity defect). Mitigation: omit the toggle
  (Library precedent); EPUB/AZW3 keep their current modes. Layout is a deferred follow-up once paged
  TXT/MD exists.
- **R5 — live propagation**: a settings change must update the live reader. Mitigation: each host
  collects the `StateFlow<ReaderSettings>` with `repeatOnLifecycle`/`collectAsStateWithLifecycle`;
  TXT/MD recompose, EPUB re-submits `EpubPreferences`, AZW3 re-injects CSS. Close/cancel on `onDestroy`.

## Backward compat

Additive + device-local: a new DataStore file, no schema/migration, not in the backup contract. An
existing install with no stored settings gets the defaults (the current hardcoded look) — zero visible
change until the user opens Display and chooses. No older-client / backup concerns (display settings
are not backed up — they're per-device, matching iOS UserDefaults which is also not in the backup).

## Revision history

- v3 (2026-06-29) — **Gate-2 round-2 fixes** (Codex `b4wpc446y`, gpt-5.5/high; round-1 Critical + High
  CONFIRMED resolved — the `ReaderBottomChrome`-shell-with-omitted-slots is design-grounded "as long as
  no dead placeholders," and Readium `pageMargins` + `submitPreferences()` confirmed; round-2 raised 4
  Mediums, all applied): **(M1 — layout parity)** #129 is reframed as "item E **minus** the layout
  toggle"; layout is a tracked follow-up feature, box E checks only when BOTH land — scope note added +
  `docs/features.md`/checklist to be updated at the PLANNED flip. **(M2 — stale layout hooks)** removed
  `setLayout`, the layout enum (de)serialization test, the `onLayout` sheet test, the AZW3 "Layout
  paged/scroll via foliate API", and the TXT/MD "hidden/disabled toggle" language. **(M3 — WI ordering)**
  swapped so the **Display sheet is WI-2** (standalone) and the **chrome shell is WI-3** (its Display slot
  opens the real WI-2 sheet — no dead Display control / no impossible test). **(M4 — Readium unit
  semantics)** defined EXACT conversions (`fontSizeSp/18.0` → Readium scale; `lineSpacing` → `lineHeight`
  Double; `marginDp/20.0` → `pageMargins`; theme RGB → Readium `Color`; family → Readium `FontFamily`)
  with default/min/max/color mapping-test cases, not "field populated."
- **Gate-2 round-3 (Codex `b8rcau0c4`, gpt-5.5/high) — PASS.** The auditor confirmed all substance clean
  ("the Readium conversion plan is self-consistent … no remaining setLayout/onLayout/AZW3 layout-toggle
  stragglers"; class metadata re-confirms `EpubPreferences` fontSize/fontFamily/lineHeight/pageMargins/
  backgroundColor/textColor/scroll/theme + `submitPreferences`). The only 2 findings were **mechanical
  WI-number typos** left from the WI-2/WI-3 swap (the chrome-shell + TtsEntryBar reconciliation still said
  "WI-2") — corrected to WI-3. Zero open substantive Critical/High/Medium → **Gate-2 clean** (3 rounds).
- v2 (2026-06-29) — **Gate-2 round-1 fixes** (Codex `bfq3etx44`, gpt-5.5/high; 1 Critical + 1 High +
  cohesion → verdict "needs revision before Gate-2 pass", all applied): **(Critical, R1)** a standalone
  Display Aa button is NOT design-grounded — the design shows Display only inside `ReaderBottomChrome`,
  and the TXT `TtsEntryBar` is itself a non-designed simplification → #129 now builds the **designed
  `ReaderBottomChrome` shell** (new WI-2) with the Display slot + scrubber and the Contents/Notes/AI slots
  **omitted until F/D land** (Library nav-bar precedent); the standalone-button approach is dropped.
  **(High)** EPUB margin was missing → map `marginDp → EpubPreferences.pageMargins` (Readium 3.3.0 exposes
  it). **(R2 confirmed)** `EpubPreferences` exposes fontSize/fontFamily/lineHeight/pageMargins/
  backgroundColor/textColor/scroll/theme + `submitPreferences()` — WI-5 is buildable; the standalone
  WI now leads with a mapping test. **(Cohesion)** EPUB (WI-5) + AZW3 (WI-6) lead with a JVM mapping/CSS
  test BEFORE UI wiring; the Display sheet (WI-3) lands after the chrome shell (WI-2) and ships uniform
  controls (no per-format hiding — the audit's fidelity flag). **(Scope)** the layout (paged/scroll)
  toggle + brightness are OMITTED (TXT/MD are scroll-only → a layout toggle is non-functional there;
  brightness is device-brightness, not a render setting) — deferred follow-ups. PDF = theme-bg-only, no
  Display sheet. WIs 7→8. Pending Gate-2 round-2 re-audit.
- v1 (2026-06-29) — initial plan. Pending Gate-2 independent audit (Codex). The two model assumptions
  Gate-2 must verify: (R1) is the per-host Display Aa entry a design-grounded slice or box-F chrome?
  (R2) the exact Readium 3.3.0 `EpubPreferences` field set.
