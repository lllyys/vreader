# Feature #99 — Translation settings re-entry (edit-framed)

- **Status**: Gate 1 v3 (2026-06-11) — Gate 2 PASSED (3 rounds; r3 clean.
  Codex sessions: r1 `019eb5e2-b13c-7882-8d4f-0eed42233e65`, r2
  `019eb5ed-f9ff-7783-b61c-79161e43f2e8`, r3
  `019eb5f8-2f13-72c1-b984-0d513a9a502d`)
- **Revision history**:
  - v1: initial draft.
  - v3 (Gate-2 round 2, 2 Medium, 1 Low — all addressed):
    (M1) the `.readerMoreTranslationSettings` contract stated ONCE: both
    post sites (the popover row funnel and the pill-tap closure — both
    composed by `ReaderContainerView`, which knows the book) include
    `userInfo: ["fingerprintKey": String]`, and every host observer
    filters on it. This is intentionally STRICTER than today's payload-
    free `.readerMoreBilingual` (those observers rely on one-reader-open;
    the new notification starts keyed so the contract never needs a
    breaking retrofit).
    (M2) provider-name sourcing defined concretely: `ReaderContainerView`
    resolves the active profile's `name` from the `ProviderProfileStore`
    actor with a generation-stamped MainActor fetch (the feature-#101
    fetcher precedent) each time the More popover OPENS (one actor hop,
    popover-frequency); the result lands in `@State providerDisplayName:
    String?`; nil (not yet landed / no profile) → the subtitle drops the
    provider segment ("Chinese · Paragraph"). A profile flip while the
    popover is open re-resolves on the next open — accepted staleness on
    a transient surface. Tests pin nil/loaded/segment-dropping.
    (L) pill press-style transcription corrected to the design's hex
    alphas: pressed = accent fill at hex-33 alpha (20%) + 2pt ring at
    hex-55 alpha (33%); rest = today's hex-1a (10%) pill background.
  - v2 (Gate-2 round 1, 2 High, 4 Medium, 1 Low — all addressed):
    (H1) `.readerBilingualDidChange` does NOT carry granularity and the
    container mirrors only active+language — v2 makes the contract change
    explicit: `postDidChange()` adds `"granularity"` to the payload and
    `ReaderContainerView` gains a `bilingualGranularity` mirror, with the
    producer + every consumer updated in one WI (WI-3).
    (H2) the popover subtitle prop was the wrong seam — the popover stays
    presentational; the row contract gains a value-type render context
    (`ReaderMoreMenuBilingualContext`: language/granularity/provider
    display strings + cluster grouping) consumed by the row's
    subtitle/grouping accessors, mirroring how `BilingualRowState`
    already parameterises the bilingual row.
    (M1) `ReaderSheetChrome` ALREADY has a default-empty `leading` slot
    (`ReaderSheetChrome.swift:43`) — the Cancel button uses it, no chrome
    change.
    (M2) `hasBeenConfigured` is VM-private — no host logic touches it;
    edit mode is driven purely by the new mode enum (the Problem section
    cites it only as background).
    (M3) the pill stays presentational — `ReaderTopChrome` gains an
    explicit `onBilingualPillTap: (() -> Void)?` and owns the Button +
    press style; nil keeps today's static render.
    (M4) the async `cachedLanguages` resolution is generation-stamped
    per host (the feature-#101 `BookDetailsReadingTimeFetcher` precedent)
    and re-checks fingerprint + presentation state on the MainActor
    before writing.
    (L) host topology corrected: 6 presentation sites (legacy EPUB incl.
    its continuous path is ONE host).
    (Cohesion) WI split re-cut: foundational store/model WI first, then
    sheet rendering, then affordances, then host fan-out.
- **Design**: landed (PR #1652) — `vreader-bilingual-suite.jsx`
  (`BSMorePopover` / `BSSettingsSheet` / `BSLangTile` / `BSCostStrip` /
  `BSRetranslateBanner` / `BSBilingualPill`) +
  `design-notes/bilingual-suite-issues.md` §#1640. Committed decision: a
  **"Translation settings" row inside the More menu's bilingual cluster**
  (canonical) + **tapping the EN↔中 pill** (secondary) — both reopen the
  existing setup sheet **edit-framed**.
- **Tracker row**: `docs/features.md` #99 (Medium). Design request #1640
  closed (bundle landed); feature GH issue created at the PLANNED flip.

## Problem

Once bilingual mode is on, there is no way to change the target language
or the paragraph-vs-sentence granularity: the setup sheet appears only on
FIRST enable. The model layer is fully built —
`BilingualReadingViewModel.setTargetLanguage(_:)` and
`setGranularity(_:)` persist, reset the trigger state, and post
`.readerBilingualDidChange` — but no UI calls them after first enable
(the sheet raise is gated inside the VM on the book's never-configured
state; that gate is VM-private and stays untouched). User: "cant change
the target language or translate mode(paragraph or sentences) after
bilingual mode is switched on".

## Surface area

| File | Change |
|---|---|
| `vreader/Views/Reader/Bilingual/BilingualSettingsEditModel.swift` (NEW, ~110 lines) | The pure edit-mode decision seam — all CTA/strip/banner rules live here so the sheet + hosts stay wiring. `enum DirtyKind { case none, newLanguage, cachedLanguage, granularityOnly }`; `static func dirtyKind(currentLanguage: String, currentGranularity: TranslationGranularity, draft: BilingualSetupSheetState, cachedLanguages: Set<String>) -> DirtyKind` — language change dominates: changed language NOT in cache → `.newLanguage`; changed language IN cache → (granularity also changed ? `.newLanguage` — re-translation is owed anyway, CTA "Apply · re-translate as you read" : `.cachedLanguage`); granularity-only change → `.granularityOnly`. `static func ctaLabel(dirty:draftLanguageDisplay:) -> String` ("Done" / "Switch to {lang}" / "Apply · re-translate as you read"); `var ctaIsAccent: Bool` (`dirty != .none`); `languageStripKind(dirty:)` (cost strip under the grid for new/cached) + `granularityStripKind(dirty:)` (strip under the segmented control for granularity-only — mirroring the jsx's two render slots); `static func shouldShowRetranslateBanner(dirty:) -> Bool` (`.newLanguage` only, per the design note's confirmed state). |
| `vreader/Services/ChapterTranslationStore.swift` | NEW `func cachedLanguages(forBookWithKey:) async -> Set<String>` — distinct `targetLanguage` over the book's parseable rows (corrupt rows excluded, same rule as `cachedUnits`; promptVersion/granularity NOT filtered — the badge means "was translated before", which is all the cached-lang strip copy commits to). Same actor, same `ModelContext(modelContainer)` pattern as `cachedUnits`. |
| `vreader/Views/Reader/Bilingual/BilingualSetupSheet.swift` + `+Sections.swift` | Edit framing on the EXISTING sheet: `enum BilingualSetupSheetMode: Equatable { case firstEnable; case edit(bookTitle: String) }` (new prop, default `.firstEnable` — zero-delta for existing callers). In `.edit`: title "Translation settings"; **Cancel** text button in `ReaderSheetChrome`'s EXISTING default-empty `leading` slot (round-1 M1 — no chrome change); the context strip under the title ("Bilingual mode is on · *{book title}*", translate glyph, 11.5pt sub, single line tail-truncated); language tiles gain the **green tick badge** (15pt disc `#3a6a5a` / dark `#3f6a58`, white check, 2pt surface ring, top-right −4pt offset) for keys in `cachedLanguages`; the caption "Already translated — switching back is instant" (11pt green dot + 10.5 sub) under the grid when ≥1 badge renders; `BilingualCostStrip` per the model's two slot kinds; the CTA uses the model's label + accent-vs-quiet fill (quiet = `isDark ? white(0.08) : black(0.06)`, ink text; accent keeps today's shadow). New props: `mode`, `cachedLanguages: Set<String>`, `currentLanguageKey: String?`, `currentGranularity: TranslationGranularity?` (dirty inputs; nil in firstEnable). First-enable renders byte-identical to today. |
| `vreader/Views/Reader/Bilingual/BilingualCostStrip.swift` (NEW, ~70 lines) | The designed strip (`BSCostStrip`): `.newLanguage` (accent-12% bg, accent-44 border, sparkle, head "{Lang} is new for this book", sub "Pages re-translate as you read.") / `.cachedLanguage` (neutral bg, check glyph, "Cached — switches instantly" / "This language was translated before. Nothing is re-paid.") / `.granularityOnly` ("Granularity change re-translates" / "Cached rows are per-granularity · starts from this page."). **Adaptation**: the mock's "≈ $0.31" clause is sample data needing a per-model price table that does not exist (`BookTranslationEstimate` carries unit count + approximate tokens, no dollars) — v1 drops the cost clause; Known limitations. |
| `vreader/Views/Reader/ReaderMoreMenuRow.swift` | New `case translationSettings` ordered directly after `.bilingual`; `isVisible` gate = `bilingualOn` (the `.reTranslateChapter` precedent); chevron trailing control; label "Translation settings". **Row render context** (round-1 H2 — the popover stays presentational): a value type `ReaderMoreMenuBilingualContext { languageDisplay: String; granularityDisplay: String; providerDisplay: String? }` with `var settingsSubtitle: String` ("{lang} · {gran} · {provider}", provider segment dropped when nil) consumed by the row-subtitle accessor (`subtitle(bilingualContext:)` alongside the existing `trailingControl(bilingualState:autoTurnOn:)` pattern). The notification: `.readerMoreTranslationSettings` registered in `ReaderNotifications.swift`, posted with `userInfo: ["fingerprintKey": String]` by BOTH affordances (v3 M1 — the container composes both post sites); every host observer filters on the key. |
| `vreader/Views/Reader/ReaderMorePopover.swift` (+`Parts`) | Renders the **bilingual cluster** when bilingual is on: the `.bilingual` + `.translationSettings` rows wrap in one accent-tinted group (radius 12, accent at 8% dark / 5% light, inset divider from x≈54); off → flat rows as today, settings row absent (gated out by `visibleRows`). New pass-through prop: `bilingualContext: ReaderMoreMenuBilingualContext?` handed to the row accessors — presentation only, no logic (round-1 H2). |
| `vreader/ViewModels/BilingualReadingViewModel+Prefetch.swift` + `ReaderContainerView.swift` | (round-1 H1, explicit contract change) `postDidChange()` adds `"granularity": granularity.rawValue` to the `.readerBilingualDidChange` payload; `ReaderContainerView`'s existing mirror gains `@State bilingualGranularity: TranslationGranularity?` alongside `bilingualActive`/`bilingualLanguage`. Consumers audited: the container mirror is the only payload READER of language today (renderers re-read the VM directly); the architecture doc's Notification Bus row updates in the same WI. The container builds `ReaderMoreMenuBilingualContext` from the mirrored state + `@State providerDisplayName` — resolved from the `ProviderProfileStore` actor via a generation-stamped MainActor fetch each time the More popover opens (v3 M2); nil drops the provider segment. |
| `vreader/Views/Reader/Bilingual/BilingualPill.swift` + `ReaderTopChrome.swift` | (round-1 M3) the pill STAYS presentational. `ReaderTopChrome` gains `var onBilingualPillTap: (() -> Void)? = nil`; when non-nil the chrome wraps the pill in a `Button` with the designed press style (rest = today's hex-1a/10% pill bg; pressed = accent fill at hex-33 alpha (20%) + 2pt ring at hex-55 alpha (33%) via a `ButtonStyle` — the design's `accent33`/`accent55` tokens); nil renders today's static pill (back-compat for previews/tests). `ReaderContainerView` passes a closure posting `.readerMoreTranslationSettings` (one re-entry channel for both affordances). |
| `vreader/Views/Reader/Bilingual/BilingualRetranslateBanner.swift` (NEW, ~70 lines) | The confirmed-state floating banner (`BSRetranslateBanner`): under the top chrome, accent-44 border, spinner glyph, "Re-translating in {lang}…" + "Cached {previous lang} stays — switch back anytime"; auto-dismisses after ~4s. **Adaptation**: the mock's trailing "p. 3 →" chip omitted (host-specific page indicator on a ~4s transient); Known limitations. |
| `vreader/Views/Reader/ReaderContainerView.swift` / `+Sheets.swift` | Banner overlay: `@State retranslateBanner: (language: String, previous: String)?` set from a new `.readerBilingualRetranslateStarted` notification (`["fingerprintKey", "language", "previousLanguage"]`, fingerprint-keyed) posted by a host's edit-confirm when the model says banner; rendered under `ReaderTopChrome` while non-nil (bundled into an existing modifier or one new chain link — the body is near the type-checker ceiling). |
| 6 host presentation sites (`TXTReaderContainerView+Bilingual`, `MDReaderContainerView+Bilingual`, legacy `EPUBReaderContainerView+Bilingual` incl. its continuous path, `ReadiumEPUBHost+Bilingual`, `PDFReaderContainerView+Bilingual`, `FoliateBilingualContainerView`) | Each: (a) a `.readerMoreTranslationSettings` observer (fingerprint-filtered like the host's existing bilingual observers) → `ensureBilingualViewModel()`, prefill `bilingualSetupState` from the VM, set the host's new `bilingualSetupMode = .edit(bookTitle:)`, present the existing sheet, and resolve `cachedLanguages` via a **generation-stamped MainActor fetch** (round-1 M4 — the feature-#101 fetcher precedent: a superseded/dismissed presentation's completion is dropped; the result re-checks fingerprint + the sheet still presenting before writing the host's `@State cachedLanguages`); (b) `confirmBilingualSetup()` branches on mode: edit-confirm computes the model's dirty kind BEFORE applying, applies via the EXISTING `setTargetLanguage`/`setGranularity` (equality-guarded no-ops), never touches `needsSetupSheet`/`setEnabled`, posts `.readerBilingualRetranslateStarted` when the model says banner, then kicks the existing `triggerBilingualPositionChange` warm (the same call first-enable confirm makes). Cancel keeps the no-persist contract. |

**Files OUT of scope**: `BilingualReadingViewModel` core setters (reused
verbatim); the translation pipeline, cache schema, count contract (#343
divergence absorbs switches as today); `ChapterReTranslateViewModel`;
whole-book translate (`BookTranslationCoordinator` — see Edge cases);
the AI providers push (`BilingualSetupSheetContainer` flow inherited);
`ReaderSheetChrome` (the leading slot exists — round-1 M1).

## Prior art / precedent / rejected alternatives

- **The sheet exists** (#56 WI-9 `BilingualSetupSheet`, #81 container with
  the AI-providers push, #344 `sentenceGranularityAvailable` dim) — edit
  mode reuses all of it; the design "reuses BilingualSetupSheet vocabulary".
- **Conditional More-menu row**: `.reTranslateChapter`'s `bilingualOn` gate.
- **Row parameterisation**: `BilingualRowState` + `trailingControl(...)` —
  the new render context follows the same row-contract pattern (round-1 H2).
- **Fingerprint-keyed observers**: every bilingual host filters
  `.readerMoreBilingual` / `.readerBilingualDidChange` already.
- **Floating banner**: `ReaderTranslateBanner` (#56 WI-14).
- **Generation-stamped async fetch**: feature #101's
  `BookDetailsReadingTimeFetcher` (Gate-4-hardened precedent).
- **Rejected (design)**: editing inside the AI panel's Translate tab; a
  dedicated settings screen; long-press on the pill.

## Work items

- **WI-1 (foundational, ~130 lines)** — `ChapterTranslationStore.cachedLanguages`
  + `BilingualSettingsEditModel` (pure rules). No user-observable change.
  RED: model dirty/CTA/strip/banner matrix (parameterized); store
  distinct-language fetch (in-memory container; corrupt-row + other-book
  exclusion).
- **WI-2 (behavioral, ~250 lines)** — sheet edit-mode rendering: mode
  enum, Cancel in the existing leading slot, context strip, tick badges,
  caption, `BilingualCostStrip`, CTA variants.
  RED: composition pins (first-enable byte-identical defaults; edit
  title/CTA/badges/caption per model inputs); strip copy pins.
- **WI-3 (behavioral, ~220 lines)** — the two affordances + the granularity
  mirror: More-menu row (case, gate, context subtitle, cluster group,
  notification) + pill tap (`onBilingualPillTap` + press style) +
  `postDidChange` payload extension + container mirror + context build.
  RED: `visibleRows` gating/order; subtitle builder (provider dropped when
  nil / present when loaded); effect/notification mapping incl. the
  fingerprintKey payload pin on BOTH post sites; `.readerBilingualDidChange`
  payload pin (granularity present); press-style pins; provider-fetch
  race (superseded popover-open completion dropped).
- **WI-4 (behavioral, final, ~300 lines)** — host fan-out (6 sites) +
  banner: edit-mode observers with the generation-stamped cachedLanguages
  fetch, edit-confirm routing, `.readerBilingualRetranslateStarted` +
  container overlay.
  RED: edit-confirm routing tests on an extracted pure helper (dirty
  computed before apply; `needsSetupSheet` untouched; banner only for
  `.newLanguage`); fetch-race regression (superseded presentation
  dropped); banner notification keying. Device verification: full
  acceptance pass on ≥3 renderer families (TXT, Readium, Foliate).

## Edge cases

- **Language change mid-prefetch**: `setTargetLanguage` resets the trigger
  state + bumps the epoch — in-flight prefetches for the old language are
  discarded (existing #56 WI-7b machinery).
- **Switch back to a cached language**: per-language rows survive — the
  design's "switching back is instant" (subject to the #343 count guard).
- **Granularity change**: `setGranularity` clears the in-memory unit cache
  (#344) — re-translates at the new shape from the current page.
- **Whole-book translate in flight during a language change**: the job
  continues caching its ORIGINAL language (per-language rows — harmless;
  switching back finds them). No new coupling.
- **Sentence-unavailable formats**: edit mode threads the host's existing
  `sentenceGranularityAvailable` — the Sentence segment dims identically.
- **Cancel / swipe-dismiss**: no persistence (existing `onCancel`
  contract); the draft state is discarded; mode resets to avoid a stale
  edit frame on the next first-enable.
- **No AI provider configured**: engine strip + providers push inherited.
- **Same-language re-pick**: dirty `.none` → quiet "Done"; setters
  equality-guard; no banner.
- **Stale persisted language key**: `normalised()` canonicalises on appear.
- **Fast dismiss/reopen or book switch during the cachedLanguages fetch**:
  generation-stamped fetch drops the stale completion (round-1 M4).
- **Bilingual toggled off while the edit sheet is open** (DEBUG-bridge
  race): edit-confirm persists language/granularity only — `isEnabled`
  untouched; safe.
- **CJK/Unicode book titles in the context strip**: verbatim, single
  line, tail truncation.

## Test catalogue

- `vreaderTests/Views/Reader/Bilingual/BilingualSettingsEditModelTests.swift`
  (NEW): dirty matrix, CTA labels, strip slot kinds, banner rule.
- `vreaderTests/Services/ChapterTranslationStoreTests.swift` (extend):
  `cachedLanguages` — empty, multi-language, corrupt-row exclusion,
  other-book exclusion.
- `vreaderTests/Views/Reader/Bilingual/BilingualSetupSheetTests.swift`
  (extend or sibling): edit-mode composition pins; first-enable unchanged.
- `vreaderTests/Views/Reader/ReaderMoreMenuRowTests.swift` (extend):
  gating, ordering, subtitle context, trailing control, notification map.
- WI-3: `.readerBilingualDidChange` payload pin (granularity key).
- WI-4: routing helper tests; fetch-race regression; banner keying.

## Risks + mitigations

- **6-host fan-out drift**: the routing decision is centralised in
  `BilingualSettingsEditModel`; each host's delta is one observer + one
  confirm branch + one mode flag. The WI-4 device pass exercises TXT +
  Readium + Foliate (three renderer families).
- **Payload contract change** (`.readerBilingualDidChange` + granularity):
  additive key; the container mirror is today's only payload consumer of
  language — WI-3 updates producer, consumer, and the architecture doc
  row together (round-1 H1).
- **Popover cluster restyle regressions**: the cluster wrapper activates
  only when bilingual is on; off-state renders today's flat rows.
- **One notification channel for two affordances**: pill + menu row post
  the same fingerprint-keyed notification — single observer per host.

## Backward compat

No schema changes. `BilingualSetupSheetMode` defaults to `.firstEnable`
(existing presentations compile + render unchanged). `ReaderTopChrome`'s
`onBilingualPillTap` defaults nil (static pill, today's render). The
`.readerBilingualDidChange` granularity key is additive. Per-book files
untouched. Cache rows unchanged (`cachedLanguages` is read-only).

## Known limitations (v1, accepted)

- The new-language cost strip drops the mock's "≈ $0.31" clause — no
  per-model price table exists; the strip keeps the behavioral copy. A
  future estimator can append the clause without re-design.
- The re-translate banner omits the mock's trailing "p. 3 →" chip (a
  host-specific current-page indicator on a ~4s transient surface).
