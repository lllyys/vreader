# Feature #62 — Annotations panel split — implementation plan

- **Feature row**: `docs/features.md` #62 (TODO → resumes at PLANNED once this v3 passes Gate 2)
- **GH issue**: #801
- **Plan version**: **v3** (2026-05-19) — see §8 revision history.
- **Design source** (committed, rule 51 satisfied):
  - `TOCSheet` (Contents + Bookmarks) + the three empty-state
    illustrations: `dev-docs/designs/vreader-fidelity-v1/project/vreader-annotations.jsx`
    (`TOCSheetV2`, `EmptyTOCArt`, `EmptyBookmarkArt`, `EmptyHighlightsArt`,
    `EmptyState`) + `design-notes/feature-60-followups.md` §3.
  - `HighlightsSheet` (Annotations): the **#860 issue-canvas handoff** —
    `dev-docs/designs/vreader-fidelity-v1/project/vreader-notes-unified.jsx`
    (`HighlightsSheetV3`, `HighlightCardV3`, `StandaloneNoteCard`) +
    `design-notes/needs-design-issues.md` §#860 + `VReader Issues Canvas.html`.
    **This supersedes** `vreader-annotations.jsx`'s `HighlightsSheetV2`
    for the Highlights/Notes surface — `vreader-notes-unified.jsx`'s
    own header and the `needs-design-issues.md` cross-reference table
    name `HighlightsSheetV3` as the canonical version.
- **Partial design gap — annotation IMPORT affordance (`needs-design`
  [#963](https://github.com/lllyys/vreader/issues/963))**: the committed
  design depicts annotation file operations in exactly two places —
  `HighlightsSheetV3`'s trailing Share/export button and
  `BookDetailsSheet`'s "Export annotations…" Actions row — and **both
  are export-only**. The legacy `AnnotationsPanelView` also carries an
  `annotationsImportButton` (`.fileImporter` for `.json`); the design
  has **no import affordance anywhere**. v3 ships `HighlightsSheet` with
  only the designed Share/export button; the import affordance is
  deferred to `needs-design` #963 — a **narrow, isolated** block that
  does NOT block the rest of #62 (rule 51's "continue designed
  slices"). See §2 `HighlightsSheet` and the WI-4 import-deferral note.
- **Author**: feature-cron (Gate 1 v1; v2 / v3 revisions), 2026-05-18 / 2026-05-19
- **Lineage**: v2 follow-on of feature #60 (VERIFIED). New feature per the
  close gate — not a #60 reopen. Resolves the IA-debt item that #60 WI-10
  left behind (it re-skinned the unified panel but did not split it).

## 1. Problem

`AnnotationsPanelView.swift` is a single 4-tab sheet (Contents /
Bookmarks / Highlights / Notes). Its own file header admits it covers
the design's two distinct sheets — `TOCSheet` and `HighlightsSheet` —
"as one 4-tab sheet". The committed design (#793 handoff →
`vreader-annotations.jsx`, then the #860 issue-canvas handoff →
`vreader-notes-unified.jsx`) decided to split it **by job-to-be-done**:

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

### v3 — the #860 design landed, and it changes the `HighlightsSheet` shape

The Gate-2 round-1 audit (Codex `019e3b4f`) found a design blocker
(finding 2): the then-committed `HighlightsSheetV2` modelled its
All/Highlights/Notes filters on a single `HighlightRecord`-shaped list
(splitting "Highlights" vs "Notes" by `h.note != nil`), but the
production app *also* has standalone `AnnotationRecord` notes (own
`@Model`, `PersistenceActor+Annotations` CRUD, a `ReaderNotificationHandlers`
creation path, the unified panel's 4th tab, export/import/backup/CloudKit).
The committed design had **no surface** for standalone annotations.
`needs-design` #860 was filed; feature #62 went `BLOCKED`.

The #860 design landed 2026-05-18 (commit `ab2a1e5`, the issue-canvas
bundle). Its **decision — option (2) from the issue: extend the design.**
`HighlightsSheetV3` (`vreader-notes-unified.jsx`) renders BOTH record
types in one sheet:

- **Filter chips unchanged** — `All · Highlights · Notes · Bookmarks` —
  but the **semantics change**:
  - `Highlights` → `HighlightRecord` rows (the passage; note optional).
  - `Notes` → BOTH standalone `AnnotationRecord` rows **and**
    `HighlightRecord` rows that carry a note. *Notes are notes,
    regardless of anchor* — the user does not have to learn which
    "kind" of note they made.
  - `All` → the union, in one chronological stream.
  - `Bookmarks` → unchanged (empty-state-only — see Risk 3 / round-1
    finding 3).
- **Two card components** — `HighlightCardV3` (the passage card, visually
  identical to the v2 design) and a NEW `StandaloneNoteCard` (the note
  body is the hero; no quoted passage; a `Standalone` pill + a dashed
  accent rule distinguish it from a highlight row).
- **`All` interleaves both card types** in one list; the visual
  difference (colour swatch + solid rule vs `Standalone` pill + dashed
  rule) lets the user scan the stream without grouping headers.

This is a **structural change from the v2 plan**: the v2 plan routed the
`HighlightsSheet` Notes filter to the existing `AnnotationListView` and
the Highlights filter to the existing `HighlightListView` (two separate
`List`-based views, "wrap, don't rebuild"). The #860 design overturns
that — `HighlightsSheet` is a *single* sheet with a *unified card
stream*, not a tab container over the two legacy list views. v3 §2 / §4
/ §5 below are rewritten for the unified-card design. `HighlightListView`
and `AnnotationListView` are no longer rendered inside the split sheets
at all — see §2 "Files that become unused" for their fate.

## 2. Surface area

### New files

- `vreader/Views/Reader/Annotations/AnnotationsSheetRoute.swift`
  — a Foundation-only enum modelling which annotations sheet the reader
  presents. **Replaces the `annotationsPanelInitialTab` /
  `showAnnotationsPanel` pair with one routing value**, the same pure
  decision-type pattern `ReaderMoreMenuEffect` (feature #61) uses.
  ```swift
  enum AnnotationsSheetRoute: Equatable, Hashable, Identifiable, Sendable {
      case toc(initialTab: TOCSheetTab)
      case highlights(initialFilter: HighlightsSheetFilter)

      /// Full-payload identity so `.sheet(item:)` re-presents cleanly
      /// even for "same kind, different initial tab" (round-1 finding 1).
      var id: String {
          switch self {
          case .toc(let tab):          return "toc:\(tab.rawValue)"
          case .highlights(let filter): return "highlights:\(filter.rawValue)"
          }
      }
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
  (design `TOCSheetV2` titles with the book name; `ReaderSheetKind
  .tableOfContents.designTitle` is already `nil` "= runtime: the book
  title"). A 2-tab segmented control with per-tab count badges; the
  body switches on the selected tab between **new design-faithful row
  views** (see below). The sheet **owns its bookmark loading** — a
  `BookmarkListViewModel` constructed in the sheet's `.task` (so the
  Bookmarks count badge is live the moment the sheet appears, even when
  it opens on the Contents tab — round-2 finding 5). Signature:
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
  **Bookmark-count loading (round-2 finding 5)**: `TOCSheet` constructs
  `BookmarkListViewModel(bookFingerprintKey:store:)` in its own `.task`
  and calls `loadBookmarks()` on appear — *not* deferred to the
  Bookmarks tab body's render. The Bookmarks count badge reads
  `viewModel.bookmarks.count` from that sheet-owned model; the Contents
  badge reads `tocEntries.count`. The Bookmarks-tab body then reuses
  the same already-loaded view model (no second load). Before the load
  resolves, the badge reads "0" and is updated reactively when
  `loadBookmarks()` returns — a count badge ticking 0→N on a freshly
  opened sheet is acceptable (the design shows a count, not a spinner;
  bookmark fetch is a fast indexed query). `TOCSheetTests` pins that
  the badge reflects the loaded count.
- `vreader/Views/Reader/Annotations/HighlightsSheet.swift`
  — the review sheet (All / Highlights / Notes / Bookmarks filters).
  Wraps `ReaderSheetChrome` with `title: "Annotations"` and **a single
  designed Share/export button** in the `trailing` slot
  (`HighlightsSheetV3`'s trailing slot is one Share button — see
  round-2 finding 2). A horizontally-scrolling filter-chip row with
  per-filter count badges; the body is a **unified card stream**
  (`ScrollView` + `LazyVStack`) rendering `HighlightAnnotationCard` per
  `AnnotationStreamItem` (see the two new types below). **Owns the
  export flow** — the `exportAnnotations()` method + its `@State`
  (`isShowingExportShare`, `exportedFileURL`, `exportMessage`) move
  here verbatim from `AnnotationsPanelView` (engine unchanged — see §7).
  **The import flow is deferred** — `importAnnotationsFrom(url:)`, the
  `.fileImporter`, the `isShowingImporter` state, and the
  `annotationsImportButton` are NOT carried into `HighlightsSheet`
  (round-2 finding 2 — the committed design has no import affordance;
  `needs-design` #963). See the WI-4 import-deferral note in §4 for
  exactly what ships and what is held. Signature:
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
- `vreader/Views/Reader/Annotations/AnnotationStreamItem.swift`
  — a Foundation-only value type unifying the two record kinds for the
  card stream + the filter/count math. The #860 design's `HighlightsSheetV3`
  builds an `allStream` of `{kind: 'highlight' | 'standalone', ...}`
  objects and counts `all / highlights / notes / bookmarks` off record
  type + `h.note`. This type is the Swift home of that pure logic so it
  is unit-testable without SwiftUI:
  ```swift
  enum AnnotationStreamItem: Equatable, Identifiable, Sendable {
      case highlight(HighlightRecord)
      case standalone(AnnotationRecord)

      var id: UUID { ... }          // highlightId / annotationId
      var createdAt: Date { ... }   // for chronological merge
      /// True when this item is a "note" per the #860 semantics —
      /// a standalone annotation, OR a highlight carrying a non-empty note.
      var isNote: Bool { ... }
  }

  /// Pure builder — input the two fetched record arrays, output the
  /// filtered + sorted stream and the four chip counts. No SwiftUI.
  struct AnnotationStreamBuilder {
      static func stream(
          highlights: [HighlightRecord],
          annotations: [AnnotationRecord],
          filter: HighlightsSheetFilter
      ) -> [AnnotationStreamItem]      // newest-first

      static func counts(
          highlights: [HighlightRecord],
          annotations: [AnnotationRecord]
      ) -> [HighlightsSheetFilter: Int]
  }
  ```
  Count semantics, pinned to `vreader-notes-unified.jsx` lines 84-90:
  - `all` = `highlights.count + annotations.count`
  - `highlights` = `highlights.count`
  - `notes` = `annotations.count + highlights.filter { $0.note?.isEmpty == false }.count`
  - `bookmarks` = `0` (the Bookmarks chip count in `HighlightsSheet` is
    a hard `0` in the design — `counts.bookmarks: 0`; the real bookmark
    surface is `TOCSheet`'s Bookmarks tab — see Risk 3).
- `vreader/Views/Reader/Annotations/HighlightAnnotationCard.swift`
  — the two card components from `vreader-notes-unified.jsx`. A single
  file (the cards are small and always rendered together):
  - `HighlightCardV3` view — the passage card. Meta row (colour swatch
    10×10 + chapter + `p. <page>` + date), a serif-italic quoted
    passage with a 2pt solid colour left-rule, and — when
    `HighlightRecord.note` is non-empty — a `note.text`-glyphed note
    block beneath. Visually identical to `vreader-annotations.jsx`'s
    `HighlightCard` (the design says "no change").
  - `StandaloneNoteCard` view — NEW. Meta row (a small filled
    note-glyph pictogram in an `accent`-tinted rounded square + chapter
    + `p. <page>` + a `Standalone` uppercase pill + date), and the note
    body as the hero — serif, `t.ink`, behind a 2pt **dashed** accent
    left-rule (no colour swatch — no highlight backs it).
  Both take a `ReaderThemeV2` and an `onJump` closure.
- `vreader/Views/Reader/Annotations/TOCSheetRows.swift`
  — the **design-faithful** Contents + Bookmark row views for
  `TOCSheet`'s filled states. Round-2 finding 1: the existing
  `TOCListView` / `BookmarkListView` row renderers do **not** match the
  committed `TOCSheetV2` design (`TOCListView` renders only indented
  titles — no chapter ordinal, no page number; `BookmarkListView`
  renders a title/date `List` row — no italic preview, no chapter, no
  chevron). So `TOCSheet` ships its own rows, drawn from `vreader-annotations.jsx`'s
  `TOCSheetV2`:
  - `TOCContentsRow` — chapter ordinal (right-aligned, serif, `sub`),
    chapter title (serif; `accent` + bold when it is the current
    chapter), and `p. <page>` trailing. The current-chapter row gets an
    `accent`-tinted background. The "current chapter" determination
    reuses `TOCListView`'s existing `activeEntryIndex` logic (matching
    `currentLocator` against `TOCEntry` by `charOffsetUTF16` / `href` /
    `page`) — that *logic* is correct and is lifted into `TOCSheet`;
    only the *row rendering* is new.
  - `TOCBookmarkRow` — `bookmark.fill` accent glyph, a serif-italic
    1-line preview, a `chapter · p. <page> · <date>` sub-line, a
    trailing chevron, a 0.5pt hairline separator. Drawn from
    `TOCSheetV2`'s bookmark card.
  Both are pure `View`s taking a `ReaderThemeV2`; tapping calls
  `onNavigate` + `onDismiss`. The Contents/Bookmark rows render inside
  `TOCSheet`'s own `ScrollView`/`LazyVStack` (matching the design's
  scrolled list, not a `List`). Each row keeps a stable
  `accessibilityIdentifier` (`tocRow-<chapterIndex>` /
  `tocBookmarkRow-<bookmarkId>`).
- `vreader/Views/Reader/Annotations/AnnotationsEmptyStateView.swift`
  — the design's `EmptyState` component: a centred `VStack` of art
  (96×96), a serif title, a body, and an optional CTA button. One
  reusable view; the three art shapes are passed in.
- `vreader/Views/Reader/Annotations/AnnotationsEmptyStateArt.swift`
  — the three SVG illustrations from `vreader-annotations.jsx`
  reproduced as SwiftUI `Shape`/`Path` views: `EmptyTOCArt`,
  `EmptyBookmarkArt`, `EmptyHighlightsArt`. Each is a `View` taking a
  `ReaderThemeV2` (the JSX `art` functions take `t` and draw with
  `t.rule` / `t.sub` / `t.accent` / `t.isDark`). Pure geometry — no
  data, no behavior. **`ContentUnavailableView` is replaced**, not kept.

### Modified files

- `vreader/Views/Reader/ReaderContainerView.swift`
  - Replace the two `@State` vars `showAnnotationsPanel` (line 59) and
    `annotationsPanelInitialTab` (line 63) with **one** optional route:
    `@State var annotationsRoute: AnnotationsSheetRoute?` (kept
    `internal`, not `private` — the More-menu router in `+Sheets.swift`
    writes it, exactly as the sibling `showBookDetails` is `internal`
    for the same reason). The `.sheet(item:)` form replaces
    `.sheet(isPresented:)`.
  - `.readerToolbarActionObservers(onContents:)` (lines 200-203) → sets
    `annotationsRoute = AnnotationsSheetRoute.route(forChromeButton: .contents)`
    = `.toc(initialTab: .contents)`; `onNotes:` (lines 204-207) →
    `AnnotationsSheetRoute.route(forChromeButton: .notes)` =
    `.highlights(initialFilter: .all)`. This is the design's
    bottom-chrome routing (`feature-60-followups.md` §3 table: Contents
    → TOCSheet, Notes → HighlightsSheet · **All** filter — note: All,
    not Highlights; the v2 plan said `.all` for Notes already, this is
    unchanged but now also matches the #860 doc explicitly).
  - The `.sheet(isPresented: $showAnnotationsPanel)` block (lines
    378-398) becomes `.sheet(item: $annotationsRoute)` switching on the
    route to present `TOCSheet` or `HighlightsSheet`.
  - **`ensureTOCReady()` moves to an eager preload** (round-1
    finding 4). Today `ensureTOCReady()` is called from
    `.onChange(of: showAnnotationsPanel)` (lines 437-439) — deferred to
    sheet-open and async, so for a book whose TOC has not finished
    loading, `TOCSheet`'s Contents tab would briefly show the new
    designed "No TOC" empty state before entries arrive. The design
    depicts no TOC loading state. v3 moves the `ensureTOCReady()` call
    to the reader's existing appearance hook so `tocEntries` is
    populated well before the user can reach the Contents chrome
    button — the empty state then reliably means "this book ships no
    TOC". Concretely: add `ensureTOCReady()` to the
    `ReaderContainerView` `.task` / `.onAppear` that already runs on
    reader load (the WI-5 implementer confirms the exact existing hook;
    `ensureTOCReady()` is already idempotent — it early-returns when
    entries are present), and drop the `.onChange`-driven call. No
    loading-state UI is invented.
  - `exportAnnotationsAfterBookDetailsDismiss` handling in the
    `showBookDetails` `.sheet(onDismiss:)` (lines 419-423): the lines
    `annotationsPanelInitialTab = .highlights; showAnnotationsPanel =
    true` become `annotationsRoute = .highlights(initialFilter:
    .highlights)`.
- `vreader/Views/Reader/ReaderContainerView+Sheets.swift`
  - `handleMoreMenuAction(_:)` — `case .presentAnnotationsExport:`
    (lines 337-339, currently `annotationsPanelInitialTab = .highlights;
    showAnnotationsPanel = true`) → `annotationsRoute =
    .highlights(initialFilter: .highlights)`. The More-menu Export row
    keeps reaching the export action (it lives in `HighlightsSheet`'s
    trailing slot — design puts the Share button there).
  - `bookDetailsSheet`'s `onExportAnnotations` (line 239) doc-comment
    (lines 321-322) mentions "the annotations panel" — update the
    wording to name `HighlightsSheet`. No behavior change.
- *(round-2 finding 1 — `TOCListView` / `BookmarkListView` are no
  longer modified.)* The v2 plan modified these two views' `emptyState`
  computed properties in-place. v3 does NOT: because `TOCSheet` ships
  its own design-faithful rows (`TOCSheetRows.swift`) AND its own empty
  states (`AnnotationsEmptyStateView` + the art), `TOCListView` and
  `BookmarkListView` are no longer rendered by anything once the split
  lands. They join the deletion list — see "Files that become unused"
  below. The `tocEmptyState` / `bookmarkEmptyState` accessibility
  identifiers are re-homed onto `TOCSheet`'s own empty-state views
  (`AnnotationsEmptyStateView` exposes a configurable identifier so the
  existing XCUITest identifier strings keep resolving — see §5).
- `vreader/Models/SheetSectionContract.swift` — **path corrected**
  (round-1 finding 6: the file is `vreader/Models/`, not
  `vreader/Views/Reader/`). No code change required —
  `ReaderSheetKind.tableOfContents` / `.annotations` already carry the
  correct section lists `["Contents","Bookmarks"]` and
  `["All","Highlights","Notes","Bookmarks"]`; the two new sheets read
  this contract for their segment/chip labels so the design spec keeps
  one home. The file-header `@coordinates-with` comment mentions
  `AnnotationsPanelView.swift` / `HighlightListView.swift` — update it
  to name `TOCSheet.swift` / `HighlightsSheet.swift` in the WI that
  deletes the panel (rule 22 — comment maintenance).

### Files that become unused (deleted in WI-5)

The split replaces every legacy `List`-based annotations view with the
two new sheets' own design-faithful rendering. Once it lands, these
four `View` structs have **no caller**:

- `vreader/Views/Annotations/HighlightListView.swift` +
  `HighlightRowView` — was `AnnotationsPanelView`'s Highlights tab.
  `HighlightsSheet`'s unified card stream replaces it.
- `vreader/Views/Annotations/AnnotationListView.swift` +
  `AnnotationRowView` — was `AnnotationsPanelView`'s Notes tab.
  `HighlightsSheet`'s `StandaloneNoteCard` replaces it.
- `vreader/Views/Bookmarks/TOCListView.swift` + its private rows — was
  `AnnotationsPanelView`'s Contents tab. `TOCSheet` + `TOCContentsRow`
  (`TOCSheetRows.swift`) replace it; `TOCListView`'s `activeEntryIndex`
  current-chapter logic is *lifted into* `TOCSheet` (the logic is
  reused, the `View` is not — round-2 finding 1).
- `vreader/Views/Bookmarks/BookmarkListView.swift` + its private rows —
  was `AnnotationsPanelView`'s Bookmarks tab. `TOCSheet` + `TOCBookmarkRow`
  replace it.

**v3 decision: DELETE all four `View` structs in WI-5**, alongside
`AnnotationsPanelView`. Rationale:
- Keeping a dead, unstyled, unreachable `List`-based view "just in
  case" is exactly the undesigned-surface debt rule 51 warns against.
  The design has one TOC surface (`TOCSheet`) and one highlights
  surface (`HighlightsSheet`); a second unreachable copy of each is rot.
- Their view *models* (`HighlightListViewModel`, `AnnotationListViewModel`,
  `BookmarkListViewModel`) are **kept** — the new sheets consume them
  for data loading (see §2 OUT of scope). Only the `View` structs +
  their private `Row` sub-views are deleted.
- This is appropriately scoped *for this feature*, not over-broad: the
  whole point of #62 is "replace the unified panel"; the panel's four
  tab bodies (these four views) ARE the thing being replaced. Deleting
  them is the feature, not a drive-by. (Round-1's earlier "audit flag"
  about keeping them as a fallback is dropped — v3 commits to the
  deletion; `TOCSheet`/`HighlightsSheet` are full replacements, leaving
  unreachable duplicates would fail the rule-51 no-dead-surface bar.)
- WI-5 migrates every XCUITest that referenced these views' identifiers
  — see the complete inventory in §5 (round-2 finding 3).

### Files to DELETE

- `vreader/Views/Reader/AnnotationsPanelView.swift` — the unified
  sheet. Deleted in WI-5 once both new sheets are wired and every call
  site is migrated. The `AnnotationsPanelTab` enum it declares is also
  removed (the new `TOCSheetTab` / `HighlightsSheetFilter` replace it).
- `vreader/Views/Annotations/HighlightListView.swift`,
  `vreader/Views/Annotations/AnnotationListView.swift`,
  `vreader/Views/Bookmarks/TOCListView.swift`,
  `vreader/Views/Bookmarks/BookmarkListView.swift` — see "Files that
  become unused" above; all four deleted in WI-5.

### Files OUT of scope

- **The export / import engines** — `AnnotationExporter`,
  `AnnotationImporter`, `VReaderAnnotationParser`, `ShareActivityView`,
  the `PersistenceActor` fetch methods, the `.readerHighlightsDidImport`
  notification. The **export** *flow* moves from `AnnotationsPanelView`
  into `HighlightsSheet` byte-for-byte (same `exportAnnotations()`
  method, same `@State`); the engines are not touched. (Feature #35.)
  The **import** flow — `importAnnotationsFrom(url:)`, the `.json`
  `.fileImporter`, the `annotationsImportButton` — is **NOT moved into
  `HighlightsSheet`**: the committed design has no import affordance,
  so it is deferred to `needs-design` #963 (round-2 finding 2). The
  `AnnotationImporter` engine + `importAnnotationsFrom(url:)` method
  body are **retained** in the codebase (not deleted — #963's design
  will need them) but become temporarily unreachable from the UI once
  `AnnotationsPanelView` is deleted; see the WI-4 import-deferral note
  in §4 for exactly how (the method moves into `HighlightsSheet` as
  `private` dead-but-retained code with a `// reachable once #963 lands`
  marker, OR is parked in a small `HighlightsSheet+ImportDeferred.swift`
  — WI-4 decides; either keeps the engine code alive for #963 without
  shipping an undesigned button). Import being briefly UI-unreachable
  is a known, tracked regression (#963), not a silent drop — see §7.
- **The list view models** — `BookmarkListViewModel`,
  `HighlightListViewModel`, `AnnotationListViewModel` are unchanged and
  **kept**. `TOCSheet` constructs `BookmarkListViewModel` in its own
  `.task` (round-2 finding 5 — for the live Bookmarks count badge);
  `HighlightsSheet` constructs `HighlightListViewModel` +
  `AnnotationListViewModel` in a `.task` and reads their `highlights` /
  `annotations` arrays to feed `AnnotationStreamBuilder`. (The new
  sheets need the records, not the legacy `List` views — so the view
  models stay, the `View` structs go.)
- **TOC navigation / `ReaderTOCFactory` / `ensureTOCReady`'s
  implementation** — the TOC build pipeline is wired in, not rebuilt.
  v3 only changes *when* `ensureTOCReady()` is *called* (eager preload,
  round-1 finding 4), not the function itself. `TOCSheet` receives
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
- **The reader's tap-on-EXISTING-highlight popover** —
  `HighlightActionPresenter` / the in-reader `UIEditMenuInteraction`
  highlight menu, and the new-selection `SelectionPopoverView`. **#62
  does not touch any reader highlight-tap or popover code.** This is
  the surface **feature #64** ("Styled highlight-action popover", GH
  #822) owns; #62's `HighlightsSheet` is a *review-list* sheet, an
  entirely separate surface from the in-reader popover. No file overlap
  with #64 — see the cross-feature note in the return summary.
- **`AnnotationEditSheet`** — the inline note-edit sheet
  `AnnotationListView` presented. The #860 `HighlightsSheetV3` design's
  card `onJump` only *navigates* to the locator (it does not open an
  inline editor — editing a highlight's note is `HighlightActionPopover`'s
  job, feature #64). So `AnnotationEditSheet` is not wired into the new
  cards. It is **not deleted** by this feature (it may have other
  callers / future use; out of scope to audit that). The card `onJump`
  closures call `onNavigate` + `onDismiss` only.
- **The `HighlightsSheet` "Bookmarks" filter content** — the #860
  design (`vreader-notes-unified.jsx`) keeps the Bookmarks chip with a
  hard `0` count and an empty body (`stream` returns `[]` for that
  case). v3 reproduces the design exactly: the chip is present, its
  count badge reads `0`, and selecting it shows the
  `AnnotationsEmptyStateView` + `EmptyHighlightsArt` + the design's
  "No bookmarks yet." / "Tap the bookmark icon in the top bar to save
  your place." copy. The real bookmark surface is `TOCSheet`'s
  Bookmarks tab. No `BookmarkListView` is rendered inside
  `HighlightsSheet` (round-1 finding 3).

## 3. Prior art / project precedent / rejected alternatives

- **Precedent — `BookDetailsSheet` (feature #61, VERIFIED)**: the most
  recent freshly-split reader sheet. This plan mirrors its structure — a
  dedicated `Views/Reader/<Feature>/` directory, a pure Foundation-only
  routing/contract type (`ReaderMoreMenuEffect` →
  `AnnotationsSheetRoute`) pinned by tests, `ReaderSheetChrome` as the
  host, `.sheet` presentation from `ReaderContainerView` with `@State`
  declared on the struct (Swift forbids stored properties in the
  `+Sheets.swift` extension).
- **Precedent — `ReaderSheetChrome` + `SheetSectionContract`
  (feature #60 WI-10)**: the shared theme-tinted chrome and the
  design-pinned section contract. `ReaderSheetKind.tableOfContents`
  and `.annotations` already exist with the right titles/sections —
  the split *consumes* a contract that #60 already wrote.
- **Precedent — `LibraryCardTokens` / `SheetSectionContract` as
  pure design-data types**: the #860 design's count math + filter
  semantics live in `AnnotationStreamBuilder` (a pure type) for the
  same reason — the spec gets one Foundation-only home, unit-testable
  without a SwiftUI render path.
- **Precedent — reuse the data layer, rebuild the row chrome.**
  `TOCSheet` reuses the existing *data + logic* — `BookmarkListViewModel`
  for loading, `TOCListView`'s `activeEntryIndex` current-chapter
  matching — but **not** the legacy row *views*. Round-2 finding 1
  established that `TOCListView` / `BookmarkListView` render plain
  rows that do not match the committed `TOCSheetV2` design (no chapter
  ordinal / page on TOC rows; no italic preview / chapter / chevron on
  bookmark rows). So `TOCSheet` ships new design-faithful rows
  (`TOCSheetRows.swift`); the legacy views are deleted (§2 "Files that
  become unused"). This is the same split #61's `BookDetailsSheet`
  made — reuse `BookDetailsViewModel`, draw new design rows.
- **Precedent — `ReaderMoreMenuEffect` as a pure routing type**:
  feature #61 extracted the row→host-effect decision into a
  Foundation-only enum so it is unit-testable. `AnnotationsSheetRoute`
  applies the identical pattern to the bottom-chrome→sheet routing,
  plus a `static func route(forChromeButton:)` and
  `route(forMoreMenuEffect:)` so the mapping itself is pinned by
  tests (the `BookDetailsRouteTests` precedent).
- **Precedent — `ReaderToolbarActionObservers`**: the existing bundled
  modifier already funnels `.readerOpenContents` / `.readerOpenNotes`
  into closures on `ReaderContainerView`; only the closure *bodies*
  change. No new notification, no new observer.
- **Rejected — route the `HighlightsSheet` filters to the existing
  `HighlightListView` / `AnnotationListView`** (the v2 plan's
  approach). The #860-committed design (`HighlightsSheetV3`) is a
  *single unified card stream*: the `Notes` filter merges
  `AnnotationRecord` + annotated `HighlightRecord` into one list, and
  `All` interleaves highlight cards and standalone-note cards
  chronologically. A tab container over two separate `List` views
  cannot produce a merged/interleaved stream — it would show two
  unrelated lists and could not implement the "notes are notes
  regardless of anchor" semantics. v3 builds the unified stream
  (`AnnotationStreamBuilder` + `HighlightAnnotationCard`) per the
  committed design.
- **Rejected — two independent `@State` `Bool` flags**
  (`showTOCSheet` / `showHighlightsSheet`) + two separate
  `initialTab`/`initialFilter` `@State` vars. The two sheets are
  mutually exclusive (Contents and Notes never open together), so two
  booleans admit an illegal "both true" state and need four state
  variables total. One `AnnotationsSheetRoute?` makes the
  mutual-exclusivity a type invariant, carries the initial
  tab/filter inline, and drives `.sheet(item:)` directly.
- **Rejected — keep one `AnnotationsPanelView` and just swap the tab
  set per entry point.** That is the status quo the design explicitly
  overturns (`feature-60-followups.md` §3 "Why split"): one sheet cannot
  have an honest title bar (book title vs "Annotations") and forces the
  navigation user past review tabs.
- **Rejected — keep `ContentUnavailableView` for empty states.** The
  feature row's "Scope note 2026-05-17" explicitly pulls the design's
  custom SVG illustrations + count badges into #62. `ContentUnavailableView`
  is undesigned chrome; rule 51 requires the designed surface.
- **Rejected — fold standalone `AnnotationRecord` notes into
  highlight-notes** (the #860 issue's option 1). That is a data-model
  change + a SwiftData migration for existing standalone-annotation
  data, and the #860 design note explicitly rejects it ("out of design
  scope; the model is already wired"). The committed decision is
  option 2 — extend the design, render both record types — which is
  local to `HighlightsSheet`.
- **Rejected — deprecate the standalone-annotation feature** (#860
  option 3). Deletes a working production surface (own `@Model`,
  `PersistenceActor+Annotations` CRUD, reader creation path, export /
  import / backup / CloudKit) and breaks the export JSON shape. The
  #860 design note rejects it for the same reasons.
- **Rejected — a shared `AnnotationsSheetChrome` wrapper abstracting
  both sheets.** The two sheets differ in title source (runtime book
  title vs literal "Annotations"), trailing slot (none vs a Share/export
  button), segment style (2-tab segmented control vs scrolling filter
  chips), and body (row list vs unified card stream). A shared
  abstraction would be mostly conditionals. `ReaderSheetChrome` is
  already the shared layer; each sheet composes it directly.
- **Rejected — a single shared empty-state art enum** keyed by case.
  The three shapes are genuinely different geometry; an enum returning
  `some Shape` per case is less readable than three small named
  `View`s. They share `AnnotationsEmptyStateView` (the layout); the
  art stays three views.

## 4. Work-item sequencing

| WI | Title | Tier | PR size |
|----|-------|------|---------|
| WI-1 | `AnnotationsSheetRoute` + `TOCSheetTab` + `HighlightsSheetFilter` + `AnnotationStreamItem` + `AnnotationStreamBuilder` — pure types | **foundational** | small–medium |
| WI-2 | `AnnotationsEmptyStateView` + the three SVG art views — reusable empty-state components (no caller yet) | **foundational** | small–medium |
| WI-3 | `TOCSheet` + `TOCSheetRows` (Contents + Bookmarks, book-titled, count badges, design-faithful rows, empty states) | **behavioral** | medium |
| WI-4 | `HighlightAnnotationCard` (`HighlightCardV3` + `StandaloneNoteCard`) + `HighlightsSheet` (filters, count badges, unified card stream, export button moved in, import deferred to #963) | **behavioral** | medium–large |
| WI-5 | Rewire `ReaderContainerView` routing to the two sheets; eager `ensureTOCReady` preload; delete `AnnotationsPanelView` + `HighlightListView` + `AnnotationListView` + `TOCListView` + `BookmarkListView`; migrate the full XCUITest inventory | **behavioral** (final WI) | medium–large |

- **WI-1** — the pure routing/segment/stream types. No user-observable
  change; nothing presents them yet. RED:
  - `AnnotationsSheetRouteTests` — `.toc`/`.highlights` equality, the
    carried initial tab/filter, the full-payload `id`
    (`"toc:Contents"` ≠ `"toc:Bookmarks"` — round-1 finding 1),
    `TOCSheetTab`/`HighlightsSheetFilter` raw values + `systemImage` +
    `allCases` cardinality, and the `route(forChromeButton:)` /
    `route(forMoreMenuEffect:)` mappings.
  - `AnnotationStreamBuilderTests` — the `counts` math and the
    `stream` filtering/sorting against seeded record arrays (see §5).
  Foundational → `patch`.
- **WI-2** — the reusable empty-state component (`AnnotationsEmptyStateView`)
  + the three SVG art views (`EmptyTOCArt` / `EmptyBookmarkArt` /
  `EmptyHighlightsArt`). **Foundational** (round-2 finding 1
  consequence): unlike the v2 plan, WI-2 does NOT adopt these into
  `TOCListView` / `BookmarkListView` — those legacy views are deleted
  whole in WI-5, and `TOCSheet`/`HighlightsSheet` own their empty
  states directly. So WI-2 ships only the *component definitions*; they
  have no caller until WI-3 (`TOCSheet`) and WI-4 (`HighlightsSheet`)
  consume them. They are pure SwiftUI value-type views (`Shape`/`Path`
  geometry + a layout `View`) with no app-behavior change of their own
  — foundational, no device verification needed (the no-regression
  component-slice pattern feature #60 WI-7a used). RED:
  `AnnotationsEmptyStateArtTests` (each art view builds for all 5
  themes), `AnnotationsEmptyStateViewTests` (CTA present iff a CTA
  closure is supplied; the configurable accessibility identifier is
  applied; title/body wired). Foundational → `patch`.
  - *Why not fold WI-2 into WI-3*: keeping the empty-state component +
    art as their own small WI keeps WI-3's PR (the whole `TOCSheet`)
    from ballooning, and the three art shapes are self-contained pure
    geometry worth their own focused audit. WI-3 and WI-4 both depend
    on WI-2 — WI-2 ships first.
- **WI-3** — `TOCSheet` + `TOCSheetRows`. Presented as a standalone
  sheet but not yet routed from the chrome (WI-5 does the rewire); a
  DEBUG preview / the test target exercises it. Ships the
  design-faithful `TOCContentsRow` / `TOCBookmarkRow` (round-2
  finding 1), the 2-tab segmented control, the count badges, the
  sheet-owned `BookmarkListViewModel` load (round-2 finding 5), and the
  Contents/Bookmarks empty states (consuming WI-2's components). RED:
  `TOCSheetTests` — builds for every theme; the chrome title equals the
  passed `bookTitle`; the Contents badge equals `tocEntries.count`; the
  Bookmarks badge reflects the loaded bookmark count; `initialTab` seeds
  the segment; the empty-TOC body is the empty state. Behavioral →
  `patch`.
- **WI-4** — `HighlightAnnotationCard` + `HighlightsSheet`. The
  unified card stream + the **export** flow move in here.
  **Import-deferral (round-2 finding 2)**: `HighlightsSheet` ships
  ONLY the designed Share/export button in its trailing slot. The
  `importAnnotationsFrom(url:)` method is carried over from
  `AnnotationsPanelView` as `private` **retained-but-unreachable** code
  (so the `AnnotationImporter` engine stays compiled + tested and
  `needs-design` #963 has it ready to wire) with a
  `// Import UI deferred to needs-design #963` marker; the
  `.fileImporter` modifier, the `isShowingImporter` `@State`, and the
  `annotationsImportButton` are NOT added. WI-4 may instead park the
  retained method in `HighlightsSheet+ImportDeferred.swift` if that
  reads cleaner — implementer's choice; either keeps the engine alive
  without an undesigned button. The WI-4 PR re-runs `AnnotationExporterTests`
  / `AnnotationImporterTests` / `Feature35AnnotationsExportVerificationTests`
  as named must-stay-green regression guards (the export flow moved,
  the engines did not; the import engine is retained). RED:
  `HighlightAnnotationCardTests` (both card views build for every
  theme; `HighlightCardV3` renders the note block iff `note != nil`;
  `StandaloneNoteCard` builds with CJK body),
  `HighlightsSheetTests` — builds for every theme; chrome title is
  "Annotations"; the trailing slot has exactly one (export) button, no
  import button; filter chips equal `HighlightsSheetFilter.allCases`;
  per-filter counts come from `AnnotationStreamBuilder`; `initialFilter`
  seeds the filter; the All stream interleaves both card kinds.
  Behavioral → `patch`. (PR size medium–large — the biggest WI; see
  Risk 5 on the file-size split.)
- **WI-5** — the rewire + deletions. `ReaderContainerView` swaps the
  two `@State` vars for `annotationsRoute`, moves `ensureTOCReady()` to
  the eager preload, the bottom-chrome closures + the More-menu
  `.presentAnnotationsExport` case point at the new route, and FIVE
  view files are deleted: `AnnotationsPanelView.swift` (+
  `AnnotationsPanelTab`), `HighlightListView.swift`,
  `AnnotationListView.swift`, `TOCListView.swift`,
  `BookmarkListView.swift`. The **complete** XCUITest inventory
  (round-2 finding 3 — 12 files + `TestConstants.swift`; see §5) is
  migrated to the new sheet identifiers in this WI. This is the WI that
  completes the feature. RED: `AnnotationsRouteWiringTests` — the
  Contents button yields `.toc(initialTab: .contents)`, the Notes
  button yields `.highlights(initialFilter: .all)`, the More-menu
  Export effect yields `.highlights(initialFilter: .highlights)`.
  Behavioral, final WI → `minor`.
  - *PR size note*: WI-5 is medium–large because the XCUITest
    migration touches 12+ files. Those edits are mechanical (swap an
    identifier / a tap target) and share one surface — per the rule-47
    audit-count table they batch under WI-5's single PR audit.

Five WIs → **Large** (5+ WIs) by the rule-47 audit-count table: 1 plan
audit (1+ rounds until clean), 1 PR audit per WI.

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
  - `id` is the **full payload** — `.toc(.contents).id == "toc:Contents"`,
    `.toc(.bookmarks).id == "toc:Bookmarks"`, the two are **distinct**
    (round-1 finding 1: a kind-only id would not re-present
    "same kind, different initial tab").
  - `TOCSheetTab.allCases` is exactly `[.contents, .bookmarks]`; raw
    values "Contents"/"Bookmarks"; `systemImage` "list.bullet"/"bookmark";
    `id == rawValue`.
  - `HighlightsSheetFilter.allCases` is exactly `[.all, .highlights,
    .notes, .bookmarks]`; raw values match the design chips; the
    ordered raw-value list equals `ReaderSheetKind.annotations.sections`
    (the split must not drift from the #60 design contract).
  - `AnnotationsSheetRoute.route(forChromeButton:)` — `.contents` →
    `.toc(initialTab: .contents)`, `.notes` →
    `.highlights(initialFilter: .all)`; `route(forMoreMenuEffect:
    .presentAnnotationsExport)` → `.highlights(initialFilter:
    .highlights)`.
- `vreaderTests/Views/Reader/Annotations/AnnotationStreamBuilderTests.swift`
  (WI-1) — the #860 count + filter semantics, the highest-value new
  pure test:
  - `counts` against a seeded mix (e.g. 3 highlights of which 1 has a
    note, + 2 standalone annotations): `all == 5`, `highlights == 3`,
    `notes == 3` (1 annotated highlight + 2 standalone), `bookmarks == 0`.
  - `stream(filter: .highlights)` returns only `.highlight` items,
    count 3.
  - `stream(filter: .notes)` returns the 2 standalone + the 1 annotated
    highlight = 3 items, and the annotated highlight is a `.highlight`
    item (not mis-cast to `.standalone`).
  - `stream(filter: .all)` returns all 5, interleaved, **newest-first**
    by `createdAt` — pinned with explicit `createdAt` values so the
    sort order is asserted, not assumed.
  - `stream(filter: .bookmarks)` returns `[]`.
  - **edge — empty inputs**: `counts` all-zero, every `stream` returns
    `[]`.
  - **edge — highlight with `note: ""`** (empty string, not nil): it is
    NOT a note — `notes` count excludes it, `stream(.notes)` excludes
    it (the design's `h.note` truthiness → Swift `note?.isEmpty == false`).
  - **edge — CJK note text**: a `HighlightRecord` with a CJK `note` and
    an `AnnotationRecord` with CJK `content` both classify correctly
    (byte-agnostic).
  - **edge — large set** (e.g. 500 highlights + 500 annotations):
    `counts.all == 1000`, the `.all` stream has 1000 items (guards the
    math against a fixed cap).
  - **edge — tie-break on equal `createdAt`**: two records with an
    identical timestamp produce a deterministic order (by `id`) so the
    stream is stable.
- `vreaderTests/Views/Reader/Annotations/AnnotationsEmptyStateArtTests.swift`
  (WI-2): each of `EmptyTOCArt` / `EmptyBookmarkArt` /
  `EmptyHighlightsArt` builds (`_ = view.body`) for all 5
  `ReaderThemeV2` cases — the #60 "a re-skin must not drop wiring"
  regression lesson, applied to the new shapes.
- `vreaderTests/Views/Reader/Annotations/AnnotationsEmptyStateViewTests.swift`
  (WI-2): the view builds with and without a CTA; when a CTA closure +
  label are supplied the CTA is part of the composition, when omitted
  it is not (a pure flag the test reads, mirroring `BookDetailsSheet`-style
  composition assertions — not a pixel snapshot).
- `vreaderTests/Views/Reader/Annotations/TOCSheetTests.swift` (WI-3),
  `@MainActor`:
  - builds for every `ReaderThemeV2`;
  - the `ReaderSheetChrome` title equals the passed `bookTitle` (the
    design's book-titled TOC sheet — exposed via a
    `sheetChromeTitleForTesting` accessor, the same testability hook
    `ReaderSettingsPanel` uses in `SheetReSkinSnapshotTests`);
  - the Contents tab badge count equals `tocEntries.count`; the
    Bookmarks tab badge count equals the loaded bookmark count from the
    sheet-owned `BookmarkListViewModel` (round-2 finding 5 — pinned
    against a seeded in-memory `PersistenceActor`);
    **zero counts** render "0" (not a hidden badge — the design always
    shows the count);
  - `initialTab` seeds the selected segment;
  - the current-chapter row (`TOCContentsRow` with the `accent` tint)
    is the one whose `TOCEntry` matches `currentLocator` per the
    lifted `activeEntryIndex` logic;
  - **edge — empty TOC**: `tocEntries: []` still builds, the Contents
    badge reads "0", and `TOCSheet`'s own `AnnotationsEmptyStateView`
    (with the Open Search CTA) is the rendered Contents body — the CTA
    fires `onOpenSearch` on tap (recorded-closure assertion);
  - **edge — empty bookmarks**: with no bookmarks the Bookmarks badge
    reads "0" and the Bookmarks body is the empty state;
  - **edge — CJK book title**: a long CJK `bookTitle` builds and is
    passed to the chrome (truncation is `ReaderSheetChrome`'s
    `.lineLimit(1)` job — verified not to crash).
- `vreaderTests/Views/Reader/Annotations/HighlightAnnotationCardTests.swift`
  (WI-4), `@MainActor`:
  - `HighlightCardV3` builds for every theme; with a `HighlightRecord`
    whose `note` is non-empty the note block is part of the
    composition, with `note == nil` it is not;
  - `StandaloneNoteCard` builds for every theme; builds with a CJK
    `AnnotationRecord.content`;
  - both cards' `onJump` closure is invoked with the record's
    `locator` on tap (a recorded-closure assertion).
- `vreaderTests/Views/Reader/Annotations/HighlightsSheetTests.swift`
  (WI-4), `@MainActor`:
  - builds for every `ReaderThemeV2`;
  - chrome title is exactly "Annotations" (=`ReaderSheetKind.annotations
    .designTitle`);
  - the filter-chip set equals `HighlightsSheetFilter.allCases` in
    design order;
  - per-filter count badges equal `AnnotationStreamBuilder.counts`
    against a seeded in-memory `PersistenceActor` (highlights + standalone
    annotations);
  - `initialFilter` seeds the active filter;
  - the **All** filter's stream interleaves `HighlightCardV3` and
    `StandaloneNoteCard` (assert both card kinds appear in the
    composition for a mixed seed);
  - the **Notes** filter shows standalone notes + annotated highlights
    and the count badge matches;
  - **edge — zero counts**: every chip reads "0" and the active
    filter's body is the `AnnotationsEmptyStateView` with the
    filter-specific copy (All gets the standalone-note hint copy,
    Bookmarks gets "No bookmarks yet.");
  - **edge — Bookmarks filter**: count badge "0", body is the
    empty-state with the "Tap the bookmark icon…" copy (round-1
    finding 3 — no `BookmarkListView` here);
  - **edge — large highlight set** (500 seeded): the sheet builds and
    the All count reads against the actual count;
  - **edge — CJK highlight text + note**: a highlight whose
    `selectedText` and `note` are CJK builds and is counted correctly.
- `vreaderTests/Views/Reader/Annotations/AnnotationsRouteWiringTests.swift`
  (WI-5): the bottom-chrome Contents action resolves to
  `.toc(initialTab: .contents)`, Notes resolves to
  `.highlights(initialFilter: .all)`, and the More-menu
  `ReaderMoreMenuEffect.presentAnnotationsExport` resolves to
  `.highlights(initialFilter: .highlights)`. The route values are
  produced by the `AnnotationsSheetRoute.route(forChromeButton:)` /
  `route(forMoreMenuEffect:)` pure helpers so the mapping is testable
  without a SwiftUI render path — the `ReaderMoreMenuEffect` /
  `BookDetailsRouteTests` precedent. (Overlaps WI-1's route-helper
  tests; WI-5's suite is the wiring-level assertion that
  `ReaderContainerView` actually calls those helpers.)
- `vreaderTests/Views/Reader/AnnotationsPanelViewTests.swift`
  (WI-5): **deleted** with `AnnotationsPanelView.swift` — its
  `AnnotationsPanelTab` assertions are superseded by
  `AnnotationsSheetRouteTests`' `TOCSheetTab`/`HighlightsSheetFilter`
  coverage. Any `HighlightListViewTests` / `AnnotationListViewTests`
  (if present) are deleted with their views; their behavior is
  re-covered by `HighlightAnnotationCardTests` +
  `AnnotationStreamBuilderTests`. The WI-5 PR notes every deletion.
- `vreaderTests/Views/SheetReSkinSnapshotTests.swift` (WI-5,
  modified): this #60 composition suite builds `TOCListView` (in
  `tocViewStillBuilds`) and `HighlightListView` (in
  `highlightsViewStillBuilds`) — **both views are deleted in WI-5**, so
  both tests are **removed** and replaced by `tocSheetStillBuilds`
  (builds the new `TOCSheet`) + `highlightsSheetStillBuilds` (builds
  the new `HighlightsSheet`), so the #60 composition suite keeps
  covering the (now post-split) surfaces. The `displayPanelStillBuilds`
  / `appSettingsViewStillBuilds` tests are untouched.
- **XCUITest migration — complete inventory** (WI-5, round-2
  finding 3). The full set of XCUITest files that reference
  `annotationsPanelSheet` / `highlightRow-*` / `annotationRow-*` /
  `annotationsImportButton` / the unified-panel tab labels, verified by
  repo grep:
  - `vreaderUITests/Helpers/TestConstants.swift` — the **shared
    constants**: `annotationsPanelSheet`, `annotationsExportButton`,
    `annotationsImportButton`, `annotationEmptyState`,
    `annotationEditCancel`/`annotationEditSave`, and the
    `highlightRow(_:)` / `annotationRow(_:)` id helpers. WI-5 updates
    this file first — it adds the new identifiers (`tocSheet`,
    `highlightsSheet`, `tocRow(_:)`, `tocBookmarkRow(_:)`,
    `highlightCard(_:)`, `standaloneNoteCard(_:)`,
    `tocSheetContentsTab`/`tocSheetBookmarksTab`, the four
    `highlightsSheetFilter*` chips) and either retires or re-points the
    stale ones. `annotationsImportButton` is removed (no import button
    ships — #963). The other 11 files consume these constants, so the
    constants file changes once and the rest follow.
  - `vreaderUITests/Annotations/AnnotationsPanelPlaceholderTests.swift`
    — drives the panel + its 4 tabs + each tab's `ContentUnavailableView`
    placeholder copy. The panel is gone; this file is **rewritten** as
    `TOCSheetUITests` + folded into the new `Feature62…` verification
    test (it tests TOC/Bookmarks/Highlights/Notes presence — now
    `TOCSheet`'s 2 tabs + `HighlightsSheet`'s 4 filters). WI-5 either
    rewrites it in place or deletes it and moves its assertions into the
    Feature62 file; the WI-5 PR states which.
  - `vreaderUITests/Accessibility/GlobalAccessibilityAuditTests.swift`
    (`testAnnotationsPanelAudit`) — opens `annotationsPanelSheet` and
    runs the a11y audit. WI-5 re-points it to audit `TOCSheet` +
    `HighlightsSheet` (two audits, or one per sheet).
  - `vreaderUITests/Navigation/NavigationFlowTests.swift` and
    `vreaderUITests/Reader/ReaderNavigationTests.swift` — reference
    `annotationsPanelSheet` in navigation-flow assertions. Re-pointed to
    the new sheet identifiers.
  - `vreaderUITests/Reader/ReaderAnnotationsPanelTests.swift` — the
    panel's own UITest. Rewritten to drive `TOCSheet` + `HighlightsSheet`.
  - `vreaderUITests/Reader/TXTHighlightGestureVerificationTests.swift`,
    `vreaderUITests/Reader/TXTChapterModeHighlightVerificationTests.swift`,
    `vreaderUITests/Verification/Feature11EPUBHighlightVerificationTests.swift`
    — open the panel's Highlights tab and assert `highlightRow-*`.
    Re-pointed to `HighlightsSheet` (Highlights filter) +
    `highlightCard-<id>`.
  - `vreaderUITests/Verification/Feature35AnnotationsExportVerificationTests.swift`
    — opens the panel, drives the export button. Re-pointed to
    `HighlightsSheet`'s `annotationsExportButton`. (This file's
    **import** assertions, if any, are descoped to #963 — WI-5 marks
    them skipped/removed with a `// import UI deferred to #963` note.)
  - `vreaderUITests/Verification/Feature23TXTTocVerificationTests.swift`,
    `vreaderUITests/Reader/MDTOCVerificationTests.swift` — open the
    panel's Contents tab. Re-pointed to `TOCSheet`'s Contents tab.
  - `vreaderUITests/Verification/Feature55NotePreviewVerificationTests.swift`
    — references the panel / `annotationRow-*`. Re-pointed to
    `HighlightsSheet`'s Notes filter + the standalone-note card id.
  All re-points are mechanical (swap an identifier constant / a tap
  target). The new cards + sheets keep stable `accessibilityIdentifier`s
  defined in WI-3 (`TOCSheet`) / WI-4 (`HighlightsSheet`,
  `highlightCard-<id>` / `standaloneNoteCard-<id>`). The WI-5 PR's test
  gate (`xcodebuild test`) is the proof the migration is complete — a
  missed reference fails to compile.
- UI verification (Gate 5) —
  `vreaderUITests/Verification/Feature62AnnotationsSplitVerificationTests.swift`
  (WI-5): seed a book with bookmarks + highlights + standalone notes
  via `vreader-debug://seed`; tap the bottom-chrome **Contents** button
  → assert a sheet titled with the book name shows Contents/Bookmarks
  tabs with count badges; dismiss; tap **Notes** → assert a sheet
  titled "Annotations" shows the four filter chips; assert the **All**
  filter shows both a highlight card and a standalone-note card; assert
  the **Notes** filter shows the standalone note + the annotated
  highlight; assert the export button (`annotationsExportButton`) is
  hittable. DebugBridge-drivable, CU-free. Empty-state verification
  (WI-2) uses a no-annotations seed to assert each `*EmptyState`
  identifier resolves.

## 6. Risks + mitigations

1. **`.sheet(isPresented:)` → `.sheet(item:)` migration** (round-1
   finding 1, resolved). `.sheet(item:)` requires `Identifiable`.
   `AnnotationsSheetRoute` conforms to `Identifiable` with `id` = the
   **full payload** (`"toc:Contents"` / `"highlights:All"` …) so each
   distinct route is a distinct sheet identity and "same kind, different
   initial tab" re-presents cleanly. *Note*: the route only ever changes
   while no annotations sheet is presented (the bottom chrome + More-menu
   are occluded by any open sheet), so init-seeded `@State` is never
   actually stale at runtime — the full-payload `id` is correctness
   insurance, not a behavior the UI exercises. `AnnotationsSheetRouteTests`
   pins the distinct ids.
2. **Export-flow regression when moved into `HighlightsSheet`.** The
   export flow is the `exportAnnotations()` `async` method + its
   `@State` (`isShowingExportShare` / `exportedFileURL` / the
   export-status alert) + a `.sheet` for `ShareActivityView`. Moving it
   risks dropping a modifier. *Mitigation*: WI-4 moves it verbatim
   (same method body, same `@State` names, same error-status channel —
   renamed `exportMessage` since import no longer shares the alert);
   the WI-4 PR names `AnnotationExporterTests`,
   `Feature35AnnotationsExportVerificationTests` as must-stay-green
   regression guards, and the WI-4 device slice exercises an export
   round-trip. The **import** flow is NOT moved (round-2 finding 2 /
   #963) — `AnnotationImporterTests` still runs as a guard because the
   `AnnotationImporter` engine + the retained `importAnnotationsFrom`
   method stay compiled, but no `.fileImporter` UI ships, so there is no
   import-UI regression *risk* — there is a deliberate, tracked import-UI
   *deferral* (§7).
3. **The `HighlightsSheet` "Bookmarks" filter** (round-1 finding 3,
   resolved). The #860 design (`vreader-notes-unified.jsx`) keeps the
   Bookmarks chip with a hard `0` count and an empty body. v3
   reproduces the design exactly: the chip ships with a `0` count
   badge and selecting it shows `AnnotationsEmptyStateView` +
   `EmptyHighlightsArt` + the design's "No bookmarks yet." copy. No
   `BookmarkListView` is rendered inside `HighlightsSheet` — that
   would be self-designed UI. The real bookmark surface is `TOCSheet`'s
   Bookmarks tab.
4. **TOC-loading race** (round-1 finding 4, resolved). `ensureTOCReady()`
   was deferred to sheet-open and runs async; `TOCListView` treats
   `entries.isEmpty` as a true empty state, so the new designed
   "No TOC" empty state could flash for books whose TOC has not
   finished loading. The design depicts no TOC loading state.
   *Mitigation*: WI-5 moves `ensureTOCReady()` from the deferred
   `.onChange(of:)` to an **eager preload** on reader appearance (the
   `ReaderContainerView` `.task`/`.onAppear` hook that already runs on
   load), so `tocEntries` is populated well before the user can reach
   the Contents chrome button — the empty state then reliably means
   "this book ships no TOC". `ensureTOCReady()` is already idempotent.
   No loading-state UI is invented.
5. **File size (rule 50 §9, ~300 lines).** `HighlightsSheet` carries
   the filter-chip row + the unified card stream + the export flow +
   the retained-but-deferred import method — the largest new file.
   *Mitigation*: the card *views* live in their own file
   (`HighlightAnnotationCard.swift`); the stream/count logic lives in
   `AnnotationStreamBuilder` (its own file). If `HighlightsSheet` still
   approaches 300 lines, the export flow extracts to a
   `HighlightsSheet+Export.swift` extension file and the retained
   import method to `HighlightsSheet+ImportDeferred.swift` (the same
   `+Sheets.swift` split pattern `ReaderContainerView` uses). WI-4
   decides at implementation time; the plan pre-authorizes both splits.
6. **The Contents-empty "Open Search" CTA wiring** (round-2 finding 1
   consequence). The v2 plan added an `onOpenSearch` parameter to the
   legacy `TOCListView`; v3 deletes `TOCListView`, so the CTA closure
   is instead a first-class parameter on `TOCSheet`
   (`onOpenSearch: () -> Void`, non-optional — `TOCSheet` always has a
   reader behind it). The `TOCContentsRow` empty state (via
   `AnnotationsEmptyStateView`'s `cta:` slot) invokes it. No legacy
   call site is affected because no legacy view gains a parameter —
   `TOCSheet` is a new type. WI-3 wires the CTA into `AnnotationsEmptyStateView`;
   WI-5 wires `TOCSheet.onOpenSearch` to the reader's deferred
   `showSearch` (see Risk 7).
7. **`onOpenSearch` from `TOCSheet` must reach the reader's search
   sheet** (round-1 finding 5 — verifiability). `TOCSheet` is itself a
   sheet; presenting `showSearch` while `TOCSheet` is up risks the
   double-sheet drop that feature #61's
   `exportAnnotationsAfterBookDetailsDismiss` works around.
   *Mitigation*: WI-3 ships `TOCSheet` with the `onOpenSearch: () -> Void`
   parameter and the Contents-empty CTA wired to it; WI-3's standalone
   verification covers the **visual** empty state + that tapping the CTA
   fires the closure (a recorded-closure test). The CTA's end-to-end
   **behavior** (tap → reader search sheet opens) is wired and verified
   in WI-5: `TOCSheet`'s "Open Search" CTA dismisses `TOCSheet` first
   (`onDismiss()`), then the `ReaderContainerView` route handler opens
   `showSearch` from the `.sheet(item:)`'s `onDismiss` — the exact
   pattern feature #61 established for sheet-to-sibling-sheet hand-off.
8. **Deleting four legacy `List` views** (`HighlightListView`,
   `AnnotationListView`, `TOCListView`, `BookmarkListView` — v3,
   round-2 finding 1 + the #860 unified-card design). The split
   replaces every one with the new sheets' own rendering, so all four
   become unreachable. *Mitigation*: WI-5 deletes all four with
   `AnnotationsPanelView`; their view *models* (`HighlightListViewModel`,
   `AnnotationListViewModel`, `BookmarkListViewModel`) are kept and
   consumed by the new sheets. The XCUITests that drive `highlightRow-*`
   / `annotationRow-*` / `tocEmptyState` etc. are migrated to the new
   identifiers in the same WI. The deletion is **decided** (not a
   conditional) — these four views *are* the unified panel's four tab
   bodies, so deleting them is the feature itself, not a drive-by; the
   round-1 "keep them as a fallback" audit flag is dropped (§2 "Files
   that become unused" carries the rationale). Leaving unreachable
   duplicates would fail the rule-51 no-dead-surface bar.
9. **Standalone-note chapter/page in the card meta row** (v3-new). The
   #860 `StandaloneNoteCard` meta row shows `chapter` + `p. <page>`.
   `AnnotationRecord` carries a `Locator`, not a pre-resolved
   chapter-name/page string. *Mitigation*: the card derives its meta
   string from `AnnotationRecord.locator` using the **same** display
   helper the existing `AnnotationRowView` uses (`locator.textQuote`
   for context; `Locator`'s page/href/charOffset for the position) —
   no new locator-resolution logic. `HighlightCardV3` does the same off
   `HighlightRecord.locator`. WI-4 reuses whatever locator→display
   formatter the codebase already has (the implementer locates it; if
   none exists as a shared helper, WI-4 adds a small pure
   `AnnotationLocatorLabel` formatter with its own tests — flagged for
   the WI-4 audit, not a blocker). The card meta row is the design's
   "Chapter 6 · p. 47" — for formats without a page concept (TXT/MD)
   the formatter degrades to what `AnnotationRowView` shows today.

## 7. Backward compatibility

- **No schema change, no migration, no persisted state.** Neither the
  unified panel nor the two new sheets persist anything — sheet
  presentation is transient `@State` on `ReaderContainerView`. There is
  no stored "last annotations tab", so the `annotationsPanelInitialTab`
  → `AnnotationsSheetRoute` swap touches no UserDefaults / SwiftData /
  per-book settings. The `AnnotationRecord` `@Model` is **unchanged** —
  the #860 decision (option 2) explicitly avoids the data-model change
  that folding-into-highlight-notes would require.
- **Reader bottom-chrome routing**: behavior-preserving in *intent* —
  the Contents button still opens a Contents view, the Notes button
  still opens a Highlights/Notes view. The visible change is that they
  now open *two different sheets* instead of two tabs of one sheet
  (the committed design's explicit goal). The `.readerOpenContents` /
  `.readerOpenNotes` notifications and `ReaderBottomChrome` are
  unchanged, so any other observer is unaffected.
- **Reader More-menu**: the Export-annotations row still reaches the
  export action — it now lands on `HighlightsSheet` (filter
  `.highlights`) whose trailing slot carries the designed Share/export
  button, instead of `AnnotationsPanelView`'s Highlights tab. Same destination
  semantics.
- **Standalone notes are NOT lost** — they were the round-1 blocker.
  The #860 design surfaces every `AnnotationRecord` in `HighlightsSheet`
  under the `All` and `Notes` filters via `StandaloneNoteCard`. The
  reader creation path (`ReaderNotificationHandlers`) is untouched, so
  users keep creating standalone notes exactly as before; they just
  review them in the new sheet.
- **Export flow**: byte-for-byte preserved — same `AnnotationExporter`
  engine, same JSON format (highlights + bookmarks + standalone notes
  all still exported), same `.readerHighlightsDidImport` post-import
  notification. The export entry point moves from `AnnotationsPanelView`'s
  trailing slot to `HighlightsSheet`'s designed Share button — same
  destination semantics.
- **Import flow — a known, tracked, temporary regression** (round-2
  finding 2 / `needs-design` #963). The `annotationsImportButton` lived
  only on `AnnotationsPanelView`, which #62 deletes; the committed
  design has no import affordance, so v3 does not ship one. **Effect**:
  after this feature merges, importing an annotation `.json` file has
  no UI trigger until #963's design lands and a follow-up wires the
  retained `importAnnotationsFrom(url:)` engine to the new affordance.
  This is a deliberate, documented loss of a UI affordance — NOT a
  silent drop: the `AnnotationImporter` engine + the import method are
  retained (compiled, tested), `needs-design` #963 tracks the
  re-introduction, and the #62 row + GH #801 note the deferral.
  Export-produced JSON files from before/after this feature are
  byte-identical (the format is untouched); only the *import button* is
  temporarily absent. (An alternative — keep `AnnotationsPanelView`
  alive solely to host the import button — was rejected: it defeats the
  whole feature and leaves the undesigned 4-tab panel in the app.)
- **`AnnotationsPanelView` / `AnnotationsPanelTab` / the four legacy
  `List` views deletion**: all are internal types with no
  external/persisted dependents. The **only** non-test, non-comment
  reference to `AnnotationsPanelView` in `vreader/` is
  `ReaderContainerView` (the `.sheet` presenter; `ReaderContainerView+Sheets.swift`
  drives the `@State`). `SheetSectionContract.swift` and `SearchView.swift`
  mention it **only in comments** — `SearchView.swift` is NOT a caller
  (corrected from an earlier v3-draft error; it is not a "TOC entry
  point"). `TOCListView` / `BookmarkListView` / `HighlightListView` /
  `AnnotationListView` are each called only by `AnnotationsPanelView`.
  WI-5 deletes the five `View` files, updates the two comment
  references (`SheetSectionContract.swift`, `SearchView.swift`) per
  rule 22, and migrates the unit-test + 12 XCUITest files (§5). No
  older-client concern (this is an iOS app, not a library with
  downstream consumers).

## 8. Revision history / Gate-2 audit trail

| Version | Date | Change |
|---|---|---|
| v1 | 2026-05-18 | Initial draft (feature-cron, Gate 1). |
| v2 | 2026-05-18 | Gate 2 round 1 (Codex `019e3b4f`) — 4 High / 1 Medium / 1 Low. Finding 2 is a design blocker → `needs-design` [#860](https://github.com/lllyys/vreader/issues/860) filed, feature `BLOCKED`. The other five findings' resolutions tabled below for the v3 revision. |
| v3 (round 1) | 2026-05-19 | #860 design landed (commit `ab2a1e5`, the issue-canvas bundle; `needs-design-issues.md` §#860 + `vreader-notes-unified.jsx`). Plan revised: `HighlightsSheet` re-specified as a **unified card stream** (`HighlightsSheetV3` — `HighlightCardV3` + new `StandaloneNoteCard`, `Notes` filter merges `AnnotationRecord` + annotated `HighlightRecord`), NOT a tab container over the legacy `HighlightListView`/`AnnotationListView`. New types `AnnotationStreamItem` + `AnnotationStreamBuilder` carry the design's count/filter logic. The five v2-round-1 findings (1, 3, 4, 5, 6) applied. Gate 2 re-run fresh (Codex `019e402a`) — `CHANGES REQUIRED`, 3 High + 2 Medium. |
| v3 (round 2) | 2026-05-19 | Round-1 (v3) findings applied: (R2-1) `TOCSheet` ships new design-faithful rows (`TOCSheetRows.swift`) — `TOCListView`/`BookmarkListView` row renderers don't match the design, so all four legacy `List` views are deleted in WI-5 (view models kept); (R2-2) `HighlightsSheet` ships only the designed Share/export button — the import affordance is filed as `needs-design` [#963](https://github.com/lllyys/vreader/issues/963), `AnnotationImporter` engine retained, import UI deferred (a narrow, tracked block); (R2-3) §5 carries the complete 12-file XCUITest migration inventory; (R2-4) the model-assumption appendix corrected (`anchor`/`profileKey` fields; `SearchView.swift` is comment-only, not a caller); (R2-5) `TOCSheet` owns its `BookmarkListViewModel` load for the live count badge. Gate 2 round 2 — see below. |

### Gate 2 — round 1 (v2, BLOCKED — historical, design blocker now resolved)

Audited by Codex MCP (thread
`019e3b4f-aca6-7a91-9373-12390951a5c4`), 2026-05-18. The audit
independently confirmed every model assumption, confirmed no
concurrency hazard, and confirmed the foundational/behavioral WI
tiering. It returned **6 findings** (4 High, 1 Medium, 1 Low) — one a
design blocker.

**Outcome (v2): BLOCKED.** Finding 2 could not be closed by revising the
plan — the then-committed design had no surface for standalone
`AnnotationRecord` notes. `needs-design` #860 was filed; the
`docs/features.md` #62 row went `BLOCKED: needs-design (#860)`.

| # | Sev | Finding | Resolution (applied in v3) |
|---|---|---|---|
| 1 | High | `.sheet(item:)` mis-specified — no "`Equatable`+`Hashable`" `item:` overload, and a kind-only `id` would not re-present "same kind, different initial tab". | **Applied** — `AnnotationsSheetRoute` is `Identifiable` with `id` = the full payload (`"toc:Contents"` ≠ `"toc:Bookmarks"`). §2 + §6 Risk 1 rewritten; `AnnotationsSheetRouteTests` pins the distinct ids. |
| 2 | High | **Design blocker** — `HighlightsSheet` had no surface for standalone `AnnotationRecord` notes. | **Resolved by the #860 design** (option 2 — extend the design). v3 §1 / §2 / §3 / §4 / §5 re-specify `HighlightsSheet` as `HighlightsSheetV3`'s unified card stream rendering both `HighlightRecord` and `AnnotationRecord`. |
| 3 | High | Risk 4 (v2) proposed a live bookmark count + `BookmarkListView` for the `HighlightsSheet` Bookmarks filter — self-designed UI. | **Applied** — v3 §6 Risk 3 + §2: the Bookmarks chip ships with a hard `0` count and renders the empty state only. The #860 design (`vreader-notes-unified.jsx`) confirms `counts.bookmarks: 0` + empty body. |
| 4 | High | TOC-loading race — deferred async `ensureTOCReady()` would flash the "No TOC" empty state. | **Applied** — v3 §2 + §6 Risk 4: WI-5 moves `ensureTOCReady()` to an eager preload on reader appearance; the deferred `.onChange` call is dropped. |
| 5 | Med | WI-2's TOC `Open Search` CTA not independently verifiable inside the still-live `AnnotationsPanelView`. | **Applied** — v3 §4 WI-2 + §6 Risk 7: WI-2 ships the empty-state art + the `onOpenSearch` param (visual verification only); the CTA *behavior* is verified in WI-5 when `TOCSheet` passes a real closure. |
| 6 | Low | `SheetSectionContract` path wrong — it is `vreader/Models/`, not `vreader/Views/Reader/`. | **Applied** — v3 §2 names `vreader/Models/SheetSectionContract.swift`. |

### Gate 2 — round 1 (v3) — independent plan audit

Audited by Codex MCP (thread
`019e402a-3ab2-7ae1-8f7f-96d2c21d021a`), 2026-05-19, read-only sandbox.
A **fresh** audit (not a continuation of the v2 thread — the v3
`HighlightsSheet` re-spec warranted a clean-context review). It
independently re-verified the model assumptions and returned **5
findings** (3 High, 2 Medium).

**Outcome (round 1): `CHANGES REQUIRED`.** All five were real and
repo-verified. Resolutions applied for round 2:

| # | Sev | Finding | Resolution (applied for round 2) |
|---|---|---|---|
| R2-1 | High | "Reuse `TOCListView` / `BookmarkListView` unchanged" is factually wrong — their row renderers do not match the committed `TOCSheetV2` design (`TOCListView` = indented titles only, no chapter ordinal / page; `BookmarkListView` = title/date `List` row, no italic preview / chapter / chevron). | **Applied** — new file `TOCSheetRows.swift` (`TOCContentsRow` + `TOCBookmarkRow`, design-faithful, drawn from `TOCSheetV2`). `TOCListView` / `BookmarkListView` are no longer reused — they join the deletion list (§2 "Files that become unused"; `TOCListView`'s `activeEntryIndex` current-chapter *logic* is lifted into `TOCSheet`). §3 precedent bullet rewritten. WI-3 + the §4 table updated. |
| R2-2 | High | Moving BOTH export AND import buttons into `HighlightsSheet`'s trailing slot is self-designed UI — `HighlightsSheetV3` shows a single Share/export affordance; the design has no import control anywhere (rule 51). | **Applied** — `HighlightsSheet` ships only the designed Share/export button. The import affordance is filed as `needs-design` [#963](https://github.com/lllyys/vreader/issues/963) — a **narrow** block that does not block the rest of #62. WI-4 retains the `AnnotationImporter` engine + `importAnnotationsFrom` method (compiled, tested, ready for #963) but ships no `.fileImporter` UI. §2 `HighlightsSheet` + OUT-of-scope, §4 WI-4 import-deferral note, §6 Risk 2, §7 import-flow bullet all rewritten. The plan header carries a "Partial design gap" note. |
| R2-3 | High | The WI-5 XCUITest migration inventory is incomplete — `SearchView.swift` is not a caller, and many more UITest files reference `annotationsPanelSheet` (`AnnotationsPanelPlaceholderTests`, `GlobalAccessibilityAuditTests`, `NavigationFlowTests`, `ReaderNavigationTests`, `ReaderAnnotationsPanelTests`, `TXTHighlightGestureVerificationTests`, `Feature55NotePreviewVerificationTests`) plus the shared `TestConstants.swift`. | **Applied** — §5 now carries a **complete repo-verified inventory** of all 12 XCUITest files + `TestConstants.swift`, file-by-file with the migration each needs. `SearchView.swift` removed from the caller list (it is comment-only). |
| R2-4 | Med | The model-assumption appendix is inaccurate — `HighlightRecord` also has `anchor` + `profileKey`; `AnnotationRecord` also has `profileKey`; `SearchView.swift` is not a live caller. | **Applied** — the §8 appendix now lists the full `HighlightRecord` / `AnnotationRecord` field sets and corrects the caller graph (only `ReaderContainerView` is a real caller; `SheetSectionContract.swift` + `SearchView.swift` are comment-only). |
| R2-5 | Med | WI-3 does not specify how the Bookmarks count badge loads when `TOCSheet` opens on the Contents tab — bookmark loading lives in `BookmarkListView.task`, which would not run until the Bookmarks tab body renders. | **Applied** — §2 `TOCSheet` + §4 WI-3: `TOCSheet` owns a `BookmarkListViewModel` constructed in its **own** `.task` (loads on appear, independent of tab selection); the badge reads that sheet-owned state. `TOCSheetTests` pins it. |

### Gate 2 — round 2 (v3) — independent plan audit

Re-audited by Codex MCP (same thread `019e402a-3ab2-7ae1-8f7f-96d2c21d021a`),
2026-05-19, read-only sandbox. The auditor re-read the revised plan and
re-verified each round-1 finding against the real codebase.

**Outcome (round 2): `VERDICT: PASS`** — zero open Critical/High/Medium.
All five round-1 (v3) findings confirmed genuinely resolved (not just
reworded): R2-1 (new design-faithful rows; four legacy views deleted),
R2-2 (export-only trailing slot; import → #963; the import-deferral
split judged "sound at plan level" and the retained importer code
"intentional dead code, not an untracked orphan"), R2-3 (the 12-file +
`TestConstants.swift` XCUITest inventory matches the repo), R2-4
(appendix matches the real record field sets + caller graph), R2-5
(`TOCSheet` owns its bookmark load). WI cohesion confirmed sound — WI-2
foundational, WI-3/WI-4 the two behavioral surfaces, WI-5 the right
home for the rewire + five-view deletion + UITest migration. #963
confirmed not to block the rest of #62.

**One Low finding — fixed:**

| # | Sev | Finding | Resolution |
|---|---|---|---|
| R3-1 | Low | §6 Risk 8 carried stale fallback wording — "leave the **two** `View` files unreferenced" — inconsistent with the revised plan (four views deleted; the round-1 "audit flag" already dropped in §2). | **Fixed** — Risk 8 rewritten: the deletion is stated as decided (not conditional), names all four views, and drops the stale fallback. The auditor flagged this as the only open item; it is now closed.

**Gate 2 result: PASS.** Two v3 audit rounds (Codex `019e402a`):
round 1 = 3 High + 2 Medium → `CHANGES REQUIRED`; round 2 = 1 Low
(fixed) → `PASS`. Zero open Critical/High/Medium. Within the rule-47
3-round cap. The plan is audited-clean and ready for Gate 3.

> **Note for Gate 3** — feature #62 has one narrow `BLOCKED: needs-design`
> sub-item: the `HighlightsSheet` annotation-**import** affordance
> (`needs-design` #963). It blocks ONLY the import-button slice; every
> other slice (`TOCSheet`, `HighlightsSheet` filters + card stream +
> export, empty states, the rewire) is fully designed and unblocked.
> WI-4 ships `HighlightsSheet` with the designed export button and
> retains the `AnnotationImporter` engine for #963's eventual follow-up.
> The `docs/features.md` #62 row should carry a `BLOCKED: needs-design
> (#963)` note scoped to the import affordance — NOT a feature-wide
> block (contrast the round-1 #860 block, which WAS feature-wide).

### Verification (model assumptions confirmed while drafting v3)

The following were verified by reading the current codebase while
revising to v3 (Gate-2 will independently re-verify):

- `ReaderSheetChrome` exists with
  `init(theme:title:onClose:leading:trailing:content:)`; `title` may be
  runtime-set and may be `nil`; the `trailing` slot accepts arbitrary
  views (used today by `AnnotationsPanelView`'s export/import buttons).
- `ReaderSheetKind` exists at `vreader/Models/SheetSectionContract.swift`
  with `.tableOfContents` (`designTitle == nil`, sections
  `["Contents","Bookmarks"]`) and `.annotations` (`designTitle ==
  "Annotations"`, sections `["All","Highlights","Notes","Bookmarks"]`).
- `AnnotationsPanelView` is at `vreader/Views/Reader/AnnotationsPanelView.swift`,
  declares `AnnotationsPanelTab` (4 cases `.toc/.bookmarks/.highlights/.annotations`),
  owns the export/import flow, and is presented by `ReaderContainerView`'s
  `.sheet(isPresented: $showAnnotationsPanel)` with
  `initialTab: annotationsPanelInitialTab`.
- `ReaderContainerView` declares `@State var showAnnotationsPanel`
  (line 59) and `@State var annotationsPanelInitialTab: AnnotationsPanelTab`
  (line 63); the `.readerToolbarActionObservers(onContents:onNotes:)`
  closures (lines 199-207) set them; `.onChange(of: showAnnotationsPanel)`
  (lines 437-439) defers `ensureTOCReady()`.
- `ReaderContainerView+Sheets.swift` `handleMoreMenuAction(_:)`
  `case .presentAnnotationsExport:` (lines 337-339) sets
  `annotationsPanelInitialTab = .highlights; showAnnotationsPanel = true`.
- `ReaderMoreMenuEffect` exists with a `.presentAnnotationsExport` case.
- `HighlightRecord` (`vreader/Services/HighlightRecord.swift`) carries
  the **full** field set (round-2 finding 4 — the v3 draft's appendix
  earlier omitted two): `highlightId: UUID`, `locator: Locator`,
  `anchor: AnnotationAnchor?`, `profileKey: String`, `selectedText:
  String`, `color: String`, `note: String?`, `createdAt: Date`,
  `updatedAt: Date`; it is `Sendable, Equatable, Identifiable` with
  `id == highlightId`. The card uses `selectedText`, `color`, `note`,
  `locator`, `createdAt`; `anchor` / `profileKey` are not card inputs
  but are part of the record (noted for completeness).
- `AnnotationRecord` (`vreader/Services/AnnotationRecord.swift`) carries
  the **full** field set (round-2 finding 4): `annotationId: UUID`,
  `locator: Locator`, `profileKey: String`, `content: String`,
  `createdAt: Date`, `updatedAt: Date`; `Sendable, Equatable,
  Identifiable` with `id == annotationId`. It has **no quoted-passage
  field** — confirming the #860 "standalone note" model (the note body
  is `content`; any source text comes from `locator.textQuote`).
  `StandaloneNoteCard` uses `content`, `locator`, `createdAt`;
  `profileKey` is not a card input.
- `HighlightListViewModel` (`@Observable @MainActor`) exposes
  `private(set) var highlights: [HighlightRecord]`, `isEmpty`,
  `loadHighlights()`; constructed with `(bookFingerprintKey:store:
  totalTextLengthUTF16:)`. `AnnotationListViewModel` exposes
  `private(set) var annotations: [AnnotationRecord]`, `isEmpty`,
  `loadAnnotations()`; constructed with `(bookFingerprintKey:store:)`.
  Both are KEPT (the new card stream consumes their record arrays).
- `HighlightListView` + `AnnotationListView` (`vreader/Views/Annotations/`)
  are `List`-based; their only caller is `AnnotationsPanelView`.
  `HighlightRowView` / `AnnotationRowView` are private sub-views. All
  deleted in WI-5.
- `TOCListView` (`vreader/Views/Bookmarks/TOCListView.swift`) is
  `struct TOCListView` with `entries: [TOCEntry]`, `currentLocator:
  Locator?`, `onNavigate: (Locator) -> Void`; `BookmarkListView`
  (`vreader/Views/Bookmarks/BookmarkListView.swift`) is
  `@Bindable var viewModel: BookmarkListViewModel` + `onNavigate`.
  Both render a `ContentUnavailableView` `emptyState` with identifiers
  `tocEmptyState` / `bookmarkEmptyState`. Their only caller is
  `AnnotationsPanelView` (confirmed by grep — `ReaderSheetChrome.swift`
  mentions `TOCListView` only in a header comment, not as a caller).
  Both `View` structs are deleted in WI-5; `TOCListView`'s
  `activeEntryIndex` current-chapter logic is lifted into `TOCSheet`;
  the `tocEmptyState`/`bookmarkEmptyState` identifiers are re-homed onto
  `TOCSheet`'s empty-state views. **Their row renderers do NOT match
  the committed `TOCSheetV2` design** — round-2 finding 1 — which is
  why `TOCSheet` ships new rows rather than reusing them.
- `PersistenceActor+Annotations.swift` exists
  (`vreader/Services/PersistenceActor+Annotations.swift`).
- `ReaderThemeV2` exposes `accentColor`, `inkColor`, `subColor`,
  `ruleColor`, `sheetSurfaceColor`, and the `isDark` predicate — the
  tokens the #860 JSX cards reference (`t.accent`, `t.ink`, `t.sub`,
  `t.rule`, `t.isDark`).
- `TOCEntry`, `BookmarkRecord`, `Locator`, `DocumentFingerprint` exist
  as named. **`AnnotationsPanelView` real caller graph** (round-2
  finding 4 — corrected): the only non-test, non-comment, non-self
  reference to `AnnotationsPanelView` in `vreader/` is
  `ReaderContainerView.swift` (the `.sheet` presenter, lines 63 + 379)
  — `ReaderContainerView+Sheets.swift` writes the `@State` vars (not
  the type name directly). `SheetSectionContract.swift` and
  `SearchView.swift` mention `AnnotationsPanelView` **only in code
  comments** — `SearchView.swift` is NOT a caller (the v3 draft earlier
  mislabelled it; corrected here and in §7). Test/UI-test references
  are the unit-test file + the 12 XCUITest files inventoried in §5 —
  all migrated in WI-5.
- No `TOCSheet`, `HighlightsSheet`, `HighlightCardV3`,
  `StandaloneNoteCard`, `AnnotationStreamItem`, `AnnotationStreamBuilder`,
  `EmptyTOCArt`, `EmptyBookmarkArt`, or `EmptyHighlightsArt` symbol
  exists yet (grep over `vreader/`, `vreaderTests/`, `vreaderUITests/`
  returned nothing) — the new files do not collide.
- The #860 design (`vreader-notes-unified.jsx`) is committed; its
  README is `design-notes/needs-design-issues.md` §#860; the
  cross-reference table names `HighlightsSheetV3` / `HighlightCardV3` /
  `StandaloneNoteCard` as canonical. `vreader-annotations.jsx`'s
  `HighlightsSheetV2` is superseded for the Highlights/Notes surface;
  its `TOCSheetV2` + the three `Empty*Art` shapes remain canonical for
  the TOC sheet + empty-state illustrations.
