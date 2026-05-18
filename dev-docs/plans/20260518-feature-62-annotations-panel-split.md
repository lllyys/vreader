# Feature #62 — Annotations panel split — implementation plan

- **Feature row**: `docs/features.md` #62 (TODO)
- **GH issue**: #801
- **Design source** (committed, rule 51 satisfied):
  `dev-docs/designs/vreader-fidelity-v1/project/vreader-annotations.jsx`
  + `dev-docs/designs/vreader-fidelity-v1/project/design-notes/feature-60-followups.md` §3
- **Author**: feature-cron (Gate 1), 2026-05-18
- **Lineage**: v2 follow-on of feature #60 (VERIFIED). New feature per the
  close gate — not a #60 reopen. Resolves the IA-debt item that #60 WI-10
  left behind (it re-skinned the unified panel but did not split it).

## 1. Problem

`AnnotationsPanelView.swift` is a single 4-tab sheet (Contents /
Bookmarks / Highlights / Notes). Its own file header admits it covers
the design's two distinct sheets — `TOCSheet` and `HighlightsSheet` —
"as one 4-tab sheet". The committed design (#793 handoff →
`vreader-annotations.jsx`) decided to split it **by job-to-be-done**:

- **Navigating** the book (Contents + Bookmarks) — the user opens this
  to *leave the current page*. Titled with the book name.
- **Reviewing** what they collected (Highlights + Notes) — the user
  opens this to *revisit reading*. Titled "Annotations" (a cross-book
  concept).

Bundling them means every Contents visit bumps the user past three tabs
they do not care about, and the title bar cannot be honest (a TOC is
*this book's*; annotations are cross-book). The feature also closes the
re-skin audit's item #3: the four list views still render plain
`ContentUnavailableView` empty states; the design specifies custom SVG
empty-state illustrations (`EmptyTOCArt` / `EmptyBookmarkArt` /
`EmptyHighlightsArt`) plus per-tab/per-filter count badges.

## 2. Surface area

### New files

- `vreader/Views/Reader/Annotations/AnnotationsSheetRoute.swift`
  — a Foundation-only enum modelling which annotations sheet the reader
  presents. **Replaces the `annotationsPanelInitialTab` /
  `showAnnotationsPanel` pair with one routing value**, the same pure
  decision-type pattern `ReaderMoreMenuEffect` (feature #61 WI-3) uses.
  ```swift
  enum AnnotationsSheetRoute: Equatable, Sendable {
      case toc(initialTab: TOCSheetTab)
      case highlights(initialFilter: HighlightsSheetFilter)
  }
  ```
  Plus the two tab/filter enums it carries (declared in this file so the
  routing type and the segment models share one home, and the test
  target gets them without SwiftUI):
  ```swift
  enum TOCSheetTab: String, CaseIterable, Identifiable, Sendable {
      case contents = "Contents"
      case bookmarks = "Bookmarks"
      var id: String { rawValue }
      var systemImage: String { ... }   // list.bullet / bookmark
  }
  enum HighlightsSheetFilter: String, CaseIterable, Identifiable, Sendable {
      case all = "All"
      case highlights = "Highlights"
      case notes = "Notes"
      case bookmarks = "Bookmarks"
      var id: String { rawValue }
  }
  ```
- `vreader/Views/Reader/Annotations/TOCSheet.swift`
  — the navigation sheet (Contents + Bookmarks). Wraps
  `ReaderSheetChrome` with **`title` set to the book title at runtime**
  (design `TOCSheet` titles with the book name; `ReaderSheetKind
  .tableOfContents.designTitle` is already `nil` "= runtime: the book
  title"). A 2-tab segmented `Picker` with per-tab count badges; routes
  to `TOCListView` and `BookmarkListView` unchanged. Signature:
  ```swift
  struct TOCSheet: View {
      let bookTitle: String
      let bookFingerprintKey: String
      let modelContainer: ModelContainer
      let tocEntries: [TOCEntry]
      let currentLocator: Locator?
      let theme: ReaderThemeV2
      let onNavigate: (Locator) -> Void
      let onOpenSearch: () -> Void      // Contents-empty CTA (design §3)
      let onDismiss: () -> Void
      init(..., initialTab: TOCSheetTab = .contents, ...)
  }
  ```
- `vreader/Views/Reader/Annotations/HighlightsSheet.swift`
  — the review sheet (All / Highlights / Notes / Bookmarks filters).
  Wraps `ReaderSheetChrome` with `title: "Annotations"` and the
  export/import buttons in the `trailing` slot. A horizontally-scrolling
  filter-chip row with per-filter count badges; routes to
  `HighlightListView` / `AnnotationListView` / `BookmarkListView`.
  **Owns the export/import flow** — the `exportAnnotations()` /
  `importAnnotationsFrom(url:)` methods + their `@State`
  (`isShowingExportShare`, `exportedFileURL`, `isShowingImporter`,
  `importMessage`) move here verbatim from `AnnotationsPanelView`
  (engines unchanged — see §7). Signature:
  ```swift
  struct HighlightsSheet: View {
      let bookFingerprintKey: String
      let modelContainer: ModelContainer
      let theme: ReaderThemeV2
      let onNavigate: (Locator) -> Void
      let onDismiss: () -> Void
      init(..., initialFilter: HighlightsSheetFilter = .all, ...)
  }
  ```
- `vreader/Views/Reader/Annotations/AnnotationsEmptyStateView.swift`
  — the design's `EmptyState` component: a centred `VStack` of art
  (96×96), a serif title, a body, and an optional CTA button. One
  reusable view; the three art shapes are passed in.
- `vreader/Views/Reader/Annotations/AnnotationsEmptyStateArt.swift`
  — the three SVG illustrations from `vreader-annotations.jsx`
  reproduced as SwiftUI `Shape`/`Path` values: `EmptyTOCArt`,
  `EmptyBookmarkArt`, `EmptyHighlightsArt`. Each is a `View` taking a
  `ReaderThemeV2` (the JSX `art` functions take `t` and draw with
  `t.rule` / `t.sub` / `t.accent` / `t.isDark`). Pure geometry — no
  data, no behavior. **`ContentUnavailableView` is replaced**, not kept.

### Modified files

- `vreader/Views/Reader/ReaderContainerView.swift`
  - Replace the two `@State` vars `showAnnotationsPanel` and
    `annotationsPanelInitialTab` with **one** optional route:
    `@State var annotationsRoute: AnnotationsSheetRoute?` (kept
    `internal`, not `private` — the More-menu router in `+Sheets.swift`
    writes it, exactly as the sibling `showBookDetails` is `internal`
    for the same reason). The `.sheet(item:)` form replaces
    `.sheet(isPresented:)`.
  - `.readerToolbarActionObservers(onContents:)` → sets
    `annotationsRoute = .toc(initialTab: .contents)`;
    `onNotes:` → `annotationsRoute = .highlights(initialFilter: .all)`.
    This is the design's bottom-chrome routing (design §3 table:
    Contents → TOCSheet, Notes → HighlightsSheet · All filter).
  - The `.sheet(isPresented: $showAnnotationsPanel)` block (lines
    390-410) becomes `.sheet(item: $annotationsRoute)` switching on the
    route to present `TOCSheet` or `HighlightsSheet`.
  - `.onChange(of: showAnnotationsPanel)` (line 449, deferred
    `ensureTOCReady()`) → `.onChange(of: annotationsRoute)`; still calls
    `ensureTOCReady()` when the route becomes non-nil (TOC entries are
    only needed by `TOCSheet`, so it may gate on `.toc`).
  - `exportAnnotationsAfterBookDetailsDismiss` handling in the
    `showBookDetails` `.sheet(onDismiss:)` (lines 426-436): the line
    `annotationsPanelInitialTab = .highlights; showAnnotationsPanel =
    true` becomes `annotationsRoute = .highlights(initialFilter:
    .highlights)`.
- `vreader/Views/Reader/ReaderContainerView+Sheets.swift`
  - `handleMoreMenuAction(_:)` — `case .presentAnnotationsExport:`
    (currently `annotationsPanelInitialTab = .highlights;
    showAnnotationsPanel = true`) → `annotationsRoute =
    .highlights(initialFilter: .highlights)`. The More-menu Export row
    keeps reaching the export action (it lives in `HighlightsSheet`'s
    trailing slot — design §3 puts the Share button there).
  - `bookDetailsSheet`'s `onExportAnnotations` doc-comment mentions "the
    annotations panel's Highlights tab" — update the wording to name
    `HighlightsSheet`. No behavior change.
- `vreader/Views/Bookmarks/TOCListView.swift` — replace the
  `ContentUnavailableView` `emptyState` with `AnnotationsEmptyStateView`
  + `EmptyTOCArt` and the design's copy ("This book doesn't ship a
  TOC. Use the scrubber to flip pages, or Search to jump to a
  passage.") + an "Open Search" CTA. `TOCListView` gains an
  `onOpenSearch: (() -> Void)?` parameter (default `nil`) so the CTA
  can call back; the existing `tocList` path is untouched. The
  `accessibilityIdentifier("tocEmptyState")` is preserved on the new
  view.
- `vreader/Views/Bookmarks/BookmarkListView.swift` — replace the
  `ContentUnavailableView` `emptyState` with `AnnotationsEmptyStateView`
  + `EmptyBookmarkArt` and the design copy ("Tap the bookmark icon in
  the top bar to save your place. Bookmarks let you jump back
  instantly."). `accessibilityIdentifier("bookmarkEmptyState")`
  preserved.
- `vreader/Views/Annotations/HighlightListView.swift` — replace the
  `ContentUnavailableView` `emptyState` with `AnnotationsEmptyStateView`
  + `EmptyHighlightsArt` and the design copy. `accessibilityIdentifier
  ("highlightEmptyState")` preserved.
- `vreader/Views/Annotations/AnnotationListView.swift` — replace the
  `ContentUnavailableView` `emptyState` with `AnnotationsEmptyStateView`
  + `EmptyHighlightsArt` (the design uses the *same* highlights
  illustration for the Notes filter — `vreader-annotations.jsx` passes
  `EmptyHighlightsArt` for every `HighlightsSheet` filter) and the
  filter-specific copy ("No notes yet."). `accessibilityIdentifier
  ("annotationEmptyState")` preserved.
- `vreader/Views/Reader/SheetSectionContract.swift` — no code change
  required (`ReaderSheetKind.tableOfContents` / `.annotations` already
  carry the correct section lists `["Contents","Bookmarks"]` and
  `["All","Highlights","Notes","Bookmarks"]`); the two new sheets read
  this contract for their segment labels so the design spec keeps one
  home.

### Files to DELETE

- `vreader/Views/Reader/AnnotationsPanelView.swift` — the unified
  sheet. Deleted in the final WI once both new sheets are wired and
  every call site is migrated. The `AnnotationsPanelTab` enum it
  declares is also removed (the new `TOCSheetTab` /
  `HighlightsSheetFilter` replace it).

### Files OUT of scope

- **The export / import engines** — `AnnotationExporter`,
  `AnnotationImporter`, `VReaderAnnotationParser`, `ShareActivityView`,
  the `.json` `fileImporter`, the `PersistenceActor` fetch methods, the
  `.readerHighlightsDidImport` notification. The export/import *flow*
  moves from `AnnotationsPanelView` into `HighlightsSheet` byte-for-byte
  (same methods, same `@State`, same error-channel `importMessage`
  alert); the engines themselves are not touched. (Feature #35.)
- **The four list views' non-empty rendering** —
  `TOCListView.tocList`, `BookmarkListView.bookmarkList`,
  `HighlightListView.highlightList`, `AnnotationListView
  .annotationList`, their row sub-views, swipe-to-delete, rename/edit
  context menus, the out-of-bounds highlight banner. Only each view's
  `emptyState` computed property is rewritten. The list views keep
  their own `@Bindable` view models.
- **The three list view models** — `BookmarkListViewModel`,
  `HighlightListViewModel`, `AnnotationListViewModel` are unchanged;
  both new sheets construct them the same way `AnnotationsPanelView`
  did (`PersistenceActor` + `bookFingerprintKey` in a `.task`).
- **TOC navigation / `ReaderTOCFactory` / `ensureTOCReady`** — the TOC
  build pipeline is wired in, not rebuilt. `TOCSheet` receives
  `tocEntries` exactly as `AnnotationsPanelView` did.
- **`ReaderSheetChrome`** — reused as-is; both sheets are new clients,
  no chrome change.
- **The reader bottom chrome (`ReaderBottomChrome`) and its
  notifications** — `.readerOpenContents` / `.readerOpenNotes` and the
  `ReaderBottomChromeButton` icons/labels are unchanged. The design's
  routing change ("same buttons, two destinations") is entirely on the
  `ReaderContainerView` *handler* side, not the chrome side.
- **The reader More-menu** — `ReaderMoreMenuRow` /
  `ReaderMoreMenuEffect` are unchanged; only the `@State` mutation
  `.presentAnnotationsExport` drives is updated.
- **The `HighlightsSheet` "Bookmarks" filter content** — the design's
  `vreader-annotations.jsx` shows a `bookmarks` filter chip in
  `HighlightsSheet` but renders `bookmarks: 0` count and an empty body
  for it (`filtered` returns `[]` for that case). This plan reproduces
  the design exactly: the chip is present with the live bookmark count,
  and selecting it shows `BookmarkListView` (so the count is honest and
  the filter is not a dead chip) — see Risk 4. No new bookmark surface
  is invented.

## 3. Prior art / project precedent / rejected alternatives

- **Precedent — `BookDetailsSheet` (feature #61)**: the most recent
  freshly-split reader sheet. This plan mirrors its structure — a
  dedicated `Views/Reader/<Feature>/` directory, a pure
  Foundation-only routing/contract type (`ReaderMoreMenuEffect`) pinned
  by tests, `ReaderSheetChrome` as the host, `.sheet` presentation from
  `ReaderContainerView` with `@State` declared on the struct (Swift
  forbids stored properties in the `+Sheets.swift` extension).
- **Precedent — `ReaderSheetChrome` + `SheetSectionContract`
  (feature #60 WI-10)**: the shared theme-tinted chrome and the
  design-pinned section contract. `ReaderSheetKind.tableOfContents`
  and `.annotations` already exist with the right titles/sections —
  the split *consumes* a contract that #60 already wrote.
- **Precedent — the four list views**: `TOCListView`,
  `BookmarkListView`, `HighlightListView`, `AnnotationListView` are
  reused unchanged for their non-empty bodies; this is the same
  "wrap, don't rebuild" move #60 WI-10 made when it put them inside
  `ReaderSheetChrome`.
- **Precedent — `ReaderMoreMenuEffect` as a pure routing type**:
  feature #61 extracted the row→host-effect decision into a
  Foundation-only enum so it is unit-testable without a SwiftUI render
  path. `AnnotationsSheetRoute` applies the identical pattern to the
  bottom-chrome→sheet routing.
- **Precedent — `ReaderToolbarActionObservers`**: the existing bundled
  modifier already funnels `.readerOpenContents` / `.readerOpenNotes`
  into closures on `ReaderContainerView`; only the closure *bodies*
  change. No new notification, no new observer.
- **Rejected — two independent `@State` `Bool` flags**
  (`showTOCSheet` / `showHighlightsSheet`) + two separate
  `initialTab`/`initialFilter` `@State` vars. The two sheets are
  mutually exclusive (Contents and Notes never open together), so two
  booleans admit an illegal "both true" state and need four state
  variables total. One `AnnotationsSheetRoute?` makes the
  mutual-exclusivity a type invariant, carries the initial
  tab/filter inline, and drives `.sheet(item:)` directly. This is the
  prompt's "one enum" option and it is the right one.
- **Rejected — keep one `AnnotationsPanelView` and just swap the tab
  set per entry point.** That is the status quo the design explicitly
  overturns (design §3 "Why split"): one sheet cannot have an honest
  title bar (book title vs "Annotations") and forces the navigation
  user past review tabs.
- **Rejected — keep `ContentUnavailableView` for empty states.** The
  feature row's "Scope note 2026-05-17" explicitly pulls the design's
  custom SVG illustrations + count badges into #62. `ContentUnavailable
  View` is undesigned chrome; rule 51 requires the designed surface.
- **Rejected — a shared `AnnotationsSheetChrome` wrapper abstracting
  both sheets.** The two sheets differ in title source (runtime book
  title vs literal "Annotations"), trailing slot (none vs
  export/import), and segment control style (2-tab segmented `Picker`
  vs scrolling filter chips). A shared abstraction would be mostly
  conditionals. `ReaderSheetChrome` is already the shared layer; each
  sheet composes it directly.
- **Rejected — a single shared empty-state art enum** keyed by case.
  The three shapes are genuinely different geometry; an enum returning
  `some Shape` per case is less readable than three small named
  `View`s. They share `AnnotationsEmptyStateView` (the layout); the
  art stays three views.

## 4. Work-item sequencing

| WI | Title | Tier | PR size |
|----|-------|------|---------|
| WI-1 | `AnnotationsSheetRoute` + `TOCSheetTab` + `HighlightsSheetFilter` pure types | **foundational** | small |
| WI-2 | `AnnotationsEmptyStateView` + the three SVG art views; adopt in the 4 list views | **behavioral** | medium |
| WI-3 | `TOCSheet` (Contents + Bookmarks, book-titled, count badges) | **behavioral** | medium |
| WI-4 | `HighlightsSheet` (filters, count badges, export/import moved in) | **behavioral** | medium |
| WI-5 | Rewire `ReaderContainerView` routing to the two sheets; delete `AnnotationsPanelView` | **behavioral** (final WI) | small–medium |

- **WI-1** — the pure routing/segment types. No user-observable change;
  nothing presents them yet. RED:
  `AnnotationsSheetRouteTests` — `.toc`/`.highlights` equality, the
  carried initial tab/filter, `TOCSheetTab`/`HighlightsSheetFilter`
  raw values + `systemImage` + `allCases` cardinality. Foundational →
  `patch`.
- **WI-2** — the empty-state component + art + the four list-view
  adoptions. Behavioral (the empty states change visibly), but it
  ships *before* the split so the re-skinned empty states are exercised
  inside the still-live `AnnotationsPanelView` and can be device-verified
  independently. RED:
  `AnnotationsEmptyStateArtTests` (each art view builds for all 5
  themes), `AnnotationsEmptyStateViewTests` (CTA present iff a CTA
  closure is supplied; title/body wired). Behavioral, not final →
  `patch`.
- **WI-3** — `TOCSheet`. Presented as a standalone sheet but not yet
  routed from the chrome (WI-5 does the rewire); a DEBUG preview /
  the test target exercises it. RED: `TOCSheetTests` — builds for
  every theme; the chrome title equals the passed `bookTitle`; the
  Contents/Bookmarks count badges equal `tocEntries.count` /
  bookmark count; `initialTab` seeds the segment. Behavioral →
  `patch`.
- **WI-4** — `HighlightsSheet`. The export/import flow moves in here;
  the WI-4 PR re-runs `AnnotationExporterTests` /
  `AnnotationImporterTests` / `Feature35AnnotationsExportVerification
  Tests` as named must-stay-green regression guards (the flow moved,
  the engines did not). RED: `HighlightsSheetTests` — builds for every
  theme; chrome title is "Annotations"; filter chips equal
  `HighlightsSheetFilter.allCases`; per-filter counts; `initialFilter`
  seeds the filter. Behavioral → `patch`.
- **WI-5** — the rewire + deletion. `ReaderContainerView` swaps the
  two `@State` vars for `annotationsRoute`, the bottom-chrome closures
  and the More-menu `.presentAnnotationsExport` case point at the new
  route, and `AnnotationsPanelView.swift` + `AnnotationsPanelTab` are
  deleted. This is the WI that completes the feature. RED:
  `AnnotationsRouteWiringTests` — the Contents button yields
  `.toc(initialTab: .contents)`, the Notes button yields
  `.highlights(initialFilter: .all)`, the More-menu Export effect
  yields `.highlights(initialFilter: .highlights)`. Behavioral, final
  WI → `minor`.

Five WIs → "Medium" by the rule-47 audit-count table is exceeded by
one; this is a 5-WI feature, so it is **Large** (5+ WIs): 1 plan audit
(1+ rounds until clean), 1 PR audit per WI. WI-2's four list-view
edits share one surface (each is the same `emptyState`-property
rewrite) and MAY batch under one PR audit per the table's
"mechanical low-risk WIs" allowance — but they ship in WI-2's single
PR anyway.

## 5. Test catalogue

All new tests use **Swift Testing** (`import Testing`, `@Suite`,
`@Test`) per rule 10 — these are pure-type and view-construction
tests, none need `XCTestExpectation`. Test files mirror the source
tree.

- `vreaderTests/Views/Reader/Annotations/AnnotationsSheetRouteTests.swift`
  (WI-1):
  - `.toc(initialTab:)` and `.highlights(initialFilter:)` `Equatable`
    — same case + same payload equal, different payload unequal,
    different case unequal.
  - `TOCSheetTab.allCases` is exactly `[.contents, .bookmarks]`; raw
    values are "Contents"/"Bookmarks"; `systemImage` is
    "list.bullet"/"bookmark"; `id == rawValue`.
  - `HighlightsSheetFilter.allCases` is exactly `[.all, .highlights,
    .notes, .bookmarks]`; raw values match the design chips; the
    ordered raw-value list equals `ReaderSheetKind.annotations
    .sections` (the split must not drift from the #60 design
    contract).
- `vreaderTests/Views/Reader/Annotations/AnnotationsEmptyStateArtTests.swift`
  (WI-2): each of `EmptyTOCArt` / `EmptyBookmarkArt` /
  `EmptyHighlightsArt` builds (`_ = view.body`) for all 5
  `ReaderThemeV2` cases — the WI-9 "a re-skin must not drop wiring"
  regression lesson, applied to the new shapes.
- `vreaderTests/Views/Reader/Annotations/AnnotationsEmptyStateViewTests.swift`
  (WI-2): the view builds with and without a CTA; when a CTA closure +
  label are supplied the CTA is part of the composition, when omitted
  it is not (a pure flag the test reads, mirroring `BookDetailsSheet
  .metadataRows`-style composition assertions — not a pixel snapshot).
- `vreaderTests/Views/Reader/Annotations/TOCSheetTests.swift` (WI-3),
  `@MainActor`:
  - builds for every `ReaderThemeV2`;
  - the `ReaderSheetChrome` title equals the passed `bookTitle` (the
    design's book-titled TOC sheet — exposed via a
    `sheetChromeTitleForTesting` accessor, the same testability hook
    `ReaderSettingsPanel` uses in `SheetReSkinSnapshotTests`);
  - the Contents tab badge count equals `tocEntries.count`; the
    Bookmarks tab badge count equals the loaded bookmark count;
    **zero counts** render "0" (not a hidden badge — the design always
    shows the count);
  - `initialTab` seeds the selected segment;
  - **edge — empty TOC**: `tocEntries: []` still builds, the Contents
    badge reads "0", and `TOCListView`'s `AnnotationsEmptyStateView`
    (with the Open Search CTA) is the rendered body;
  - **edge — CJK book title**: a long CJK `bookTitle` builds and is
    passed to the chrome (truncation is `ReaderSheetChrome`'s
    `.lineLimit(1)` job — verified not to crash).
- `vreaderTests/Views/Reader/Annotations/HighlightsSheetTests.swift`
  (WI-4), `@MainActor`:
  - builds for every `ReaderThemeV2`;
  - chrome title is exactly "Annotations" (=`ReaderSheetKind
    .annotations.designTitle`);
  - the filter-chip set equals `HighlightsSheetFilter.allCases` in
    design order;
  - per-filter counts: All = highlights+notes, Highlights = items with
    no note, Notes = items with a note, Bookmarks = bookmark count —
    pinned against a seeded in-memory `PersistenceActor`;
  - `initialFilter` seeds the active filter;
  - **edge — zero counts** every chip reads "0" and the active
    filter's body is the `AnnotationsEmptyStateView` with the
    filter-specific copy;
  - **edge — large highlight set** (e.g. 500 seeded highlights): the
    sheet builds and the All count reads "500" (guards the count
    computation against the list, not a fixed cap);
  - **edge — CJK highlight text + note**: a highlight whose
    `selectedText` and `note` are CJK builds and is counted correctly
    (`note != nil` classification is byte-agnostic).
- `vreaderTests/Views/Reader/Annotations/AnnotationsRouteWiringTests.swift`
  (WI-5): the bottom-chrome Contents action resolves to
  `.toc(initialTab: .contents)`, Notes resolves to
  `.highlights(initialFilter: .all)`, and the More-menu
  `ReaderMoreMenuEffect.presentAnnotationsExport` resolves to
  `.highlights(initialFilter: .highlights)`. The route values are
  produced by small pure helpers (a `static func route(for:)` on
  `AnnotationsSheetRoute` keyed by chrome button / More-menu effect)
  so the mapping is testable without a SwiftUI render path — the
  `ReaderMoreMenuEffect`/`BookDetailsRouteTests` precedent.
- `vreaderTests/Views/Reader/AnnotationsPanelViewTests.swift`
  (WI-5): **deleted** with `AnnotationsPanelView.swift` — its
  `AnnotationsPanelTab` assertions are superseded by
  `AnnotationsSheetRouteTests`' `TOCSheetTab`/`HighlightsSheetFilter`
  coverage. The WI-5 PR notes the deletion.
- `vreaderTests/Views/SheetReSkinSnapshotTests.swift` (WI-5,
  modified): the four `*StillBuilds` tests that build the list views
  stay (the views still exist); add a `TOCSheet` + `HighlightsSheet`
  "still builds re-skinned" pair so the #60 composition suite covers
  the post-split surfaces too.
- UI verification (Gate 5) —
  `vreaderUITests/Verification/Feature62AnnotationsSplitVerificationTests.swift`
  (WI-5): seed a book with bookmarks + highlights + notes via
  `vreader-debug://seed`; tap the bottom-chrome **Contents** button →
  assert a sheet titled with the book name shows Contents/Bookmarks
  tabs; dismiss; tap **Notes** → assert a sheet titled "Annotations"
  shows the four filter chips; assert the export button
  (`annotationsExportButton`) is hittable in `HighlightsSheet`.
  DebugBridge-drivable, CU-free. Empty-state verification (WI-2)
  uses a no-annotations seed to assert each
  `*EmptyState` identifier resolves.

## 6. Risks + mitigations

1. **`.sheet(isPresented:)` → `.sheet(item:)` migration.** Switching
   the presentation API changes how dismissal nils the state.
   `AnnotationsSheetRoute` must be `Identifiable` for `.sheet(item:)`
   (or the `item:` overload that takes `Equatable` + `Hashable`); the
   route enum gets a stable `id`. *Mitigation*: WI-1 makes the enum
   `Identifiable` with a deterministic `id` (e.g. `"toc"` /
   `"highlights"` — the *route kind*, not the initial tab, so
   re-presenting the same sheet kind with a different initial tab
   re-presents cleanly); `AnnotationsRouteWiringTests` pins it.
2. **Export/import flow regression when moved into `HighlightsSheet`.**
   The flow is ~100 lines of `@State` + two `async` methods + a
   `.fileImporter` + a `.sheet` + an `.alert`. Moving it risks dropping
   a modifier. *Mitigation*: WI-4 moves it verbatim (same method
   bodies, same `@State` names, same `importMessage` error channel);
   the WI-4 PR names `AnnotationExporterTests`,
   `AnnotationImporterTests`, and `Feature35AnnotationsExportVerification
   Tests` as must-stay-green regression guards, and the WI-4 device
   slice exercises an export round-trip.
3. **`HighlightListViewModel.totalTextLengthUTF16` is `nil` today.**
   `AnnotationsPanelView` constructs `HighlightListViewModel(...,
   totalTextLengthUTF16: nil)` — the out-of-bounds detection is
   inert. *Mitigation*: `HighlightsSheet` reproduces the exact same
   `nil` argument; this feature does not change out-of-bounds
   behavior (it is `HighlightListView`'s concern, out of scope §2). No
   regression because no change.
4. **The `HighlightsSheet` "Bookmarks" filter.** The design's JSX
   shows a Bookmarks chip in `HighlightsSheet` but hard-codes its
   count to `0` and renders an empty body (it is a layout placeholder
   in the prototype). Shipping a chip that always says "0" and is
   always empty is a dead affordance. *Mitigation*: the chip ships
   with the **live** bookmark count, and selecting it shows
   `BookmarkListView` — i.e. the same data the TOCSheet's Bookmarks
   tab shows. This is *more* honest than the JSX and invents no new
   surface (`BookmarkListView` already exists; the count is real). The
   design note §3 "HighlightsSheet states" lists a "Bookmarks · empty"
   state with filter-specific copy, confirming the filter is intended
   to be real, not a placeholder. **Flag for Gate-2**: confirm this
   reading of design §3 vs the JSX's `bookmarks: 0` stub — if the
   auditor reads the JSX as authoritative (chip present, content
   intentionally empty), WI-4 instead renders the
   `AnnotationsEmptyStateView` for that filter with the design's
   "Tap the bookmark icon…" copy and the count still live. Either way
   no undesigned surface.
5. **File size (rule 50 §9, ~300 lines).** `HighlightsSheet` carries
   the filter row + the moved export/import flow — the largest new
   file. *Mitigation*: the export/import flow is ~100 lines; the
   filter-chip row is ~40; the body switch is ~30. If `HighlightsSheet`
   approaches 300, the export/import flow extracts to a
   `HighlightsSheet+ExportImport.swift` extension file (the same
   `+Sheets.swift` split pattern `ReaderContainerView` uses). WI-4
   decides at implementation time; the plan pre-authorizes the split.
6. **`TOCListView` gains an `onOpenSearch` parameter.** Adding a
   parameter to a view used by `SheetReSkinSnapshotTests` would break
   its call site. *Mitigation*: the parameter defaults to `nil`
   (`onOpenSearch: (() -> Void)? = nil`) — existing call sites
   (`SheetReSkinSnapshotTests`, and `AnnotationsPanelView` before its
   deletion) compile unchanged; only `TOCSheet` passes a non-nil
   closure.
7. **`onOpenSearch` from `TOCSheet` must reach the reader's search
   sheet.** `TOCSheet` is itself a sheet; presenting `showSearch` while
   `TOCSheet` is up risks the double-sheet drop that feature #61's
   `exportAnnotationsAfterBookDetailsDismiss` works around.
   *Mitigation*: `TOCSheet`'s Contents-empty "Open Search" CTA
   dismisses `TOCSheet` first (`onDismiss()`), then the
   `ReaderContainerView` route handler opens `showSearch` from the
   `.sheet(item:)`'s `onDismiss` — the exact pattern feature #61
   established for sheet-to-sibling-sheet hand-off. WI-3 wires the CTA
   to `onOpenSearch`; WI-5 wires `onOpenSearch` to the deferred
   `showSearch = true`.

## 7. Backward compatibility

- **No schema change, no migration, no persisted state.** Neither the
  unified panel nor the two new sheets persist anything — sheet
  presentation is transient `@State` on `ReaderContainerView`. There is
  no stored "last annotations tab", so the `annotationsPanelInitialTab`
  → `AnnotationsSheetRoute` swap touches no UserDefaults / SwiftData /
  per-book settings.
- **Reader bottom-chrome routing**: behavior-preserving in *intent* —
  the Contents button still opens a Contents view, the Notes button
  still opens a Highlights/Notes view. The visible change is that they
  now open *two different sheets* instead of two tabs of one sheet
  (the committed design's explicit goal). The `.readerOpenContents` /
  `.readerOpenNotes` notifications and `ReaderBottomChrome` are
  unchanged, so any other observer is unaffected.
- **Reader More-menu**: the Export-annotations row still reaches the
  export action — it now lands on `HighlightsSheet` (filter
  `.highlights`) whose trailing slot carries the export/import buttons,
  instead of `AnnotationsPanelView`'s Highlights tab. Same destination
  semantics.
- **Export / import flow**: byte-for-byte preserved — same
  `AnnotationExporter`/`AnnotationImporter` engines, same JSON format,
  same `.readerHighlightsDidImport` post-import notification. An export
  file produced before this feature imports identically after it; the
  format did not change. Older app versions are unaffected (the file
  format is the contract, and it is untouched).
- **`AnnotationsPanelView` / `AnnotationsPanelTab` deletion**: both
  are internal types with no external/persisted dependents — grep
  confirms the only references are `ReaderContainerView`,
  `ReaderContainerView+Sheets.swift`, and the test/UI-test files, all
  migrated in WI-5. No older-client concern (this is an iOS app, not a
  library with downstream consumers).

## 8. Revision history / Gate-2 audit trail

| Version | Date | Change |
|---|---|---|
| v1 | 2026-05-18 | Initial draft (feature-cron, Gate 1). |
| v2 | 2026-05-18 | Gate 2 round 1 (Codex `019e3b4f`) — 4 High / 1 Medium / 1 Low. Finding 2 is a design blocker → `needs-design` [#860](https://github.com/lllyys/vreader/issues/860) filed, feature `BLOCKED`. The other five findings are resolved below for the eventual v3 revision. |

### Gate 2 — Independent plan audit — round 1 (BLOCKED)

Audited by Codex MCP (thread
`019e3b4f-aca6-7a91-9373-12390951a5c4`), 2026-05-18. The audit
independently confirmed every model assumption in the Verification
list below, confirmed no concurrency hazard, and confirmed the
foundational/behavioral WI tiering. It returned **6 findings**
(4 High, 1 Medium, 1 Low) — one of which is a design blocker.

**Outcome: BLOCKED — Gate 2 did not pass; Gate 3 does not start.**
Finding 2 cannot be closed by revising the plan: the committed design
provides no surface for the app's standalone `AnnotationRecord`
notes. `needs-design` issue
[#860](https://github.com/lllyys/vreader/issues/860) is filed and the
`docs/features.md` #62 row is marked `BLOCKED: needs-design (#860)`.
When the design lands, this plan resumes at a v3 revision that applies
the #860 design decision **plus** the five resolutions tabled below,
then re-runs Gate 2 from round 1.

| # | Sev | Finding | Resolution for the v3 revision |
|---|---|---|---|
| 1 | High | `.sheet(item:)` was mis-specified: there is no "`Equatable` + `Hashable`" `item:` overload, and a route `id` keyed only on kind (`"toc"`/`"highlights"`) would not re-present "same kind, different initial tab" — init-seeded `@State` would not reset. | `AnnotationsSheetRoute` conforms to `Identifiable` with `id` = the **full payload** (`"toc:contents"` / `"highlights:all"` …) so each distinct route is a distinct sheet identity. Drop Risk 1's "Equatable+Hashable overload" wording and the "kind-only id re-presents cleanly" claim. Note for v3: the route only ever changes while no annotations sheet is presented (the bottom chrome + More-menu are occluded by any open sheet), so init-seeded `@State` is never actually stale — the full-payload `id` is correctness insurance, not a behavior the UI exercises. |
| 2 | High | **Design blocker.** §5's WI-4 catalogue derives "Notes" from `HighlightRecord.note`, but §2 routes the Notes filter to `AnnotationListView` (`AnnotationRecord`). These are two different live data types — the design's `HighlightsSheetV2` models All/Highlights/Notes on one `HighlightRecord`-shaped list (`h.note`), while the app also has standalone `AnnotationRecord` notes (own `@Model`, `PersistenceActor+Annotations` CRUD, a `ReaderNotificationHandlers` creation path, the current panel's 4th tab, export/import/backup/CloudKit). The committed design has no surface for standalone annotations. | **Not plan-fixable.** See `needs-design` #860 — the resolution is a design/product decision (fold into highlight-notes / extend the design / deprecate). v3's §2 / §4 / §5 `HighlightsSheet` content is rewritten once #860 resolves. |
| 3 | High | Risk 4 proposed a live bookmark count + `BookmarkListView` content for the `HighlightsSheet` Bookmarks filter. The committed JSX is explicit (`bookmarks: 0`, `filtered = []`) and design-notes §3 lists only a `Bookmarks · empty` state — live `BookmarkListView` there would be self-designed UI (rule 51). | v3: the `HighlightsSheet` Bookmarks filter renders the empty state only — `AnnotationsEmptyStateView` + `EmptyHighlightsArt` (the JSX reuses the highlights art for every filter's empty state) + copy "No bookmarks yet." / "Tap the bookmark icon in the top bar to save your place." Its count badge reads `0` (the filter surfaces no content here — consistent with `filtered == []`); the real bookmark surface is `TOCSheet`'s Bookmarks tab. No `BookmarkListView` inside `HighlightsSheet`. Rewrite §2 "out of scope" + §6 Risk 4. |
| 4 | High | TOC-loading race: `ensureTOCReady()` is deferred to sheet-open and runs async; `TOCListView` treats `entries.isEmpty` as a true empty state, so the new designed "No TOC" empty state would flash for books whose TOC has not finished loading. The design depicts no TOC loading state. | v3: WI-5 moves `ensureTOCReady()` from the deferred sheet-open `onChange` to an **eager preload** on reader appearance (`ReaderContainerView` `.task`), so `tocEntries` is populated well before the user can reach the Contents chrome button — the empty state then reliably means "this book has no TOC". No loading-state UI is invented. Add to §2 (`ReaderContainerView` modified) + §6 as a resolved risk. |
| 5 | Med | WI-2's TOC `Open Search` CTA is not independently verifiable "inside the still-live `AnnotationsPanelView`" — its only current caller passes no `onOpenSearch`, so the CTA path cannot be exercised until WI-5 wires `TOCSheet`. | v3: WI-2 ships the empty-state art + the four list-view visual adoptions and adds `onOpenSearch: (() -> Void)? = nil` (the CTA renders iff non-nil); WI-2 verification covers the visual empty states only. The CTA **behavior** (tap → search opens) is verified in WI-5, when `TOCSheet` passes a real closure. Update §4 WI-2/WI-5 + §5. |
| 6 | Low | `SheetSectionContract` path is wrong — the file is `vreader/Models/SheetSectionContract.swift`, not `vreader/Views/Reader/SheetSectionContract.swift`. | v3: fix the path in §2 modified-files. |

The plan's standing "open question" (Risk 4 — `HighlightsSheet`
Bookmarks filter) is resolved by Finding 3 above: the JSX
`bookmarks: 0` stub is authoritative and the filter is
empty-state-only.

### Verification (model assumptions confirmed in this draft)

The following were verified by reading the current codebase while
drafting (Gate-2 will independently re-verify):

- `ReaderSheetChrome` exists with the `init(theme:title:onClose:
  leading:trailing:content:)` signature; `title` may be runtime-set;
  the `trailing` slot accepts arbitrary views (used today by
  `AnnotationsPanelView`'s export/import buttons).
- `ReaderSheetKind` exists with `.tableOfContents` (`designTitle ==
  nil`, sections `["Contents","Bookmarks"]`) and `.annotations`
  (`designTitle == "Annotations"`, sections `["All","Highlights",
  "Notes","Bookmarks"]`).
- `AnnotationsPanelView` is at `vreader/Views/Reader/AnnotationsPanel
  View.swift`, declares `AnnotationsPanelTab` (4 cases: `.toc`,
  `.bookmarks`, `.highlights`, `.annotations`), owns the export/import
  flow, and is presented by `ReaderContainerView`'s
  `.sheet(isPresented: $showAnnotationsPanel)` with
  `initialTab: annotationsPanelInitialTab`.
- `ReaderContainerView` declares `@State var showAnnotationsPanel`
  and `@State var annotationsPanelInitialTab: AnnotationsPanelTab =
  .toc`; the `.readerToolbarActionObservers(onContents:onNotes:...)`
  closures set them; `.onChange(of: showAnnotationsPanel)` defers
  `ensureTOCReady()`.
- `ReaderContainerView+Sheets.swift` `handleMoreMenuAction(_:)`
  `case .presentAnnotationsExport:` sets `annotationsPanelInitialTab
  = .highlights; showAnnotationsPanel = true`.
- `ReaderMoreMenuEffect` exists with a `.presentAnnotationsExport`
  case; `ReaderMoreMenuRow.exportAnnotations` maps to it.
- `TOCListView`, `BookmarkListView`, `HighlightListView`,
  `AnnotationListView` each have a `private var emptyState` rendering
  `ContentUnavailableView` with the accessibility identifiers
  `tocEmptyState` / `bookmarkEmptyState` / `highlightEmptyState` /
  `annotationEmptyState`.
- `TOCListView` is at `vreader/Views/Bookmarks/TOCListView.swift`;
  `BookmarkListView` at `vreader/Views/Bookmarks/BookmarkListView.swift`;
  `HighlightListView` + `AnnotationListView` at
  `vreader/Views/Annotations/`.
- `ReaderThemeV2` exposes `accentColor`, `inkColor`, `subColor`,
  `ruleColor`, `sheetSurfaceColor`, and the `isDark` predicate — the
  exact tokens the JSX art functions reference (`t.accent`, `t.ink`,
  `t.sub`, `t.rule`, `t.isDark`).
- `TOCEntry`, `BookmarkRecord`, `HighlightRecord`, `AnnotationRecord`,
  `Locator`, `DocumentFingerprint` exist as named; `HighlightRecord`
  carries `note: String?` (the design's highlight-vs-note
  classification basis); `LibraryBookItem.title` is non-optional
  `String` (the `TOCSheet` book title source — `ReaderContainerView`
  holds `book: LibraryBookItem` and already passes `book.title` to
  `ReaderTopChrome`).
- No `TOCSheet`, `HighlightsSheet`, `EmptyTOCArt`, `EmptyBookmarkArt`,
  or `EmptyHighlightsArt` symbol exists yet (grep over `vreader/`,
  `vreaderTests/`, `vreaderUITests/` returned nothing) — the new
  files do not collide.
