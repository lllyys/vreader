Reading additional input from stdin...
OpenAI Codex v0.144.1
--------
workdir: /Users/ll/workspace/vreader
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: read-only
reasoning effort: high
reasoning summaries: none
session id: 019f5401-9765-72d1-89db-2c61228e7071
--------
user
You are an independent Gate-2 (round-2) plan auditor for feature #131 (Android bilingual interlinear reading) in this repo. The plan is at dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (Gate-1 v2 — the round-1 REDESIGN is already resolved; this is a confirmation pass). READ the plan fully.

This is a Kotlin/Android feature (under android/), the parity port of iOS features #56/#100 (interlinear bilingual: each source paragraph followed by an AI translation, cached to disk). The plan's KEY round-1 redesign: EPUB is the PRIMARY target via Readium's EpubNavigatorFragment.evaluateJavascript(script): String? (claimed PUBLIC in the shipped Readium 3.3.0 AAR), gated by a WI-0 throwaway spike that proves JS enumerate/inject/clear/re-apply-on-reflow works; TXT/MD are Compose (BilingualInterlinearBody); AZW3/PDF deferred.

Audit for (rule 47 Gate-2 bar = ZERO open Critical/High/Medium):
1. MODEL-ASSUMPTION VERIFICATION (the #1 bug class) — do the Android symbols/types/signatures the plan names ACTUALLY EXIST in the live code? Verify against android/ (grep/read): the #106 reader host (android/app/.../reader/ReaderActivity.kt + the Readium EpubNavigatorFragment usage), the #118 AI foundation (android/app/.../ai/), the #128 search/cache + ChapterSegmenter analog, Room DB for a translation cache, and whether EpubNavigatorFragment.evaluateJavascript is actually PUBLIC in the Readium 3.3.0 dependency (the plan says it verified via javap — sanity-check the claim's plausibility + where the AAR is). Flag any named file/type/method that does NOT exist or has a different signature.
2. The WI-0 EPUB JS-injection SPIKE — is its go/no-go contract concrete enough? Does it de-risk the real unknowns (fragment recreation wiping injected nodes, pagination shift, enumerate-vs-segmenter count divergence — iOS #268/#330/#344)? Is the fallback (EPUB drops to a tracked follow-up, box D ships TXT/MD-only) clean?
3. CONCURRENCY/LIFECYCLE hazards — the JS enumerate→prefetch(AI)→inject loop over a navigator the app does not own; re-apply on href-change/reflow; clear on teardown; coroutine scoping; the translation cache write/cancel.
4. COHESION — is the ~10-WI split (WI-0 spike, WI-1..4 foundational JVM-testable, WI-5..9 behavioral, WI-7a/7b EPUB split) right? Any WI too big/small? Is the box-F entry-wiring dependency (WI-9 waits on #132/#134, both now VERIFIED) correct?
5. Cross-platform parity — does it faithfully mirror iOS #56/#100 (segment-through-the-SAME-ChapterSegmenter on translate+render so 1:1 pairing holds; granularity in the cache key; source-always-kept offline fallback)?

Output: a findings list grouped by severity (Critical/High/Medium/Low), each with the exact plan section + the concrete fix. End with an explicit VERDICT line: 'GATE-2 ROUND-2 VERDICT: CLEAN' (zero C/H/M) or 'GATE-2 ROUND-2 VERDICT: FINDINGS (N Critical, M High, K Medium)'. Do NOT edit any file — audit only.
codex
I’ll perform a read-only confirmation audit. I’ll first inspect repository state and the full plan/architecture, then verify every named Android symbol and the Readium artifact/signature against the local checkout and caches.
exec
/bin/zsh -lc "git status -sb && wc -l docs/architecture.md dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md && sed -n '1,240p' docs/architecture.md && sed -n '1,260p' dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md" in /Users/ll/workspace/vreader
 succeeded in 949ms:
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-HnyTtuhr' (errno=Operation not permitted)
## main...origin/main
?? .claude/codex-audits/feat-131-bilingual-gate2-round2.md
?? android/2026-06-29-223908-this-session-is-being-continued-from-a-previous-c.txt
?? dev-docs/security/
     726 docs/architecture.md
     217 dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md
     943 total
# VReader Architecture

## Overview

VReader is an iOS e-book reader built with SwiftUI + SwiftData. It supports TXT, EPUB, AZW3/MOBI, PDF, and Markdown formats, each rendered by a format-specific native host (UIKit/WebView bridges) selected internally by `ReaderEngine` (feature #54). AZW3/MOBI is rendered via Foliate-js inside a WKWebView. **Feature #42 Phase 2 (`kindleConvertOnImport`, default ON since the G2 flip 2026-06-02):** NEW AZW3/MOBI/KF8/PRC imports are converted to a first-class EPUB at import time (via the vendored libmobi MOBI→EPUB converter) and render via the default Readium EPUB engine; already-imported native `.azw3` books are unchanged and keep rendering via Foliate, and a user can revert via the persisted `kindleConvertOnImport` override OFF. The `UnifiedTextRenderer` (TextKit 2 reflow) stack is retained in the codebase but no longer wired into the reader dispatch.

## System Diagram

```
┌──────────────────────────────────────────────────────┐
│                    VReaderApp                         │
│  SwiftData SchemaV10 · PersistenceActor · BookImporter│
└─────────────────────┬────────────────────────────────┘
                      │
          ┌───────────┴───────────┐
          │                       │
    ┌─────▼──────────┐    ┌──────▼──────────────────┐
    │  LibraryView    │    │  ReaderContainerView     │
    │  LibraryViewModel│   │  (format dispatcher)     │
    │  PreferenceStore │   │  ReaderTopChrome (overlay)│
    └─────────────────┘   └──────┬───────────────────┘
                                 │
        ┌────────┬───────────┬───┴────┬─────────┐
        │        │           │        │         │
    ┌───▼──┐ ┌──▼───┐  ┌───▼──┐ ┌──▼───┐ ┌────▼─────┐
    │ TXT  │ │ EPUB │  │ PDF  │ │  MD  │ │  AZW3 /  │
    │Bridge│ │Bridge│  │Bridge│ │Bridge│ │  MOBI    │
    └──────┘ └──────┘  └──────┘ └──────┘ └──────────┘
    UITextView WKWebView PDFKit  UITextView WKWebView
                                            (Foliate-js)
```

## Layers

### 1. App Layer (`vreader/App/`)

- `VReaderApp.swift` — SwiftData `ModelContainer` init (SchemaV10), migration plan (V1→…→V9→V10, all lightweight; V9→V10 adds the additive `Book.sourceCanonicalKey: String?` for feature #108's converted-Kindle cross-platform identity). Also runs the feature #109 one-shot `LocatorKeyBackfillMigration` synchronously at launch (flag-gated; recomputes derived locator keys under NFC canonicalization + repairs non-finite locators — a launch backfill, NOT a migration stage, since the transform changes no entity shape). Plus test seeding, error handling. Injects the live `PersistenceActor` into the SwiftUI environment via `\.persistenceActor` so settings sub-screens can construct backup providers without rewriting every parent's signature. Adopts `@UIApplicationDelegateAdaptor(VReaderAppDelegate.self)` for background-URLSession completion-handler delivery (feature #47).
- `VReaderAppDelegate.swift` — `UIApplicationDelegate` adapter that captures `application(_:handleEventsForBackgroundURLSession:completionHandler:)` into a MainActor-isolated static dictionary keyed by URLSession identifier. The lazy-download coordinator retrieves and invokes the handler from `LazyDownloadDelegate.urlSessionDidFinishEvents` so iOS releases the app's background-launch grace period.

### 2. Library Layer (`vreader/Views/LibraryView.swift`, `vreader/ViewModels/LibraryViewModel.swift`)

- Grid/list view with sort (persisted via `PreferenceStore`)
- Context menu: Info, Share, Set Cover, Add to Collection, Delete
- Collections sidebar, OPDS catalog, AI chat entry points
- Cover art (`BookCoverArtView`) renders a custom image when one exists, otherwise a generative typographic cover (Feature #60 WI-10 — `GenerativeCoverView`). The cover's style family + colour palette are deterministically derived from the book's `fingerprintKey` (FNV-1a hash → one of 5 style families × 12 design palettes in `GenerativeCoverStyle.swift`), so a given book always shows the same generated cover.

### 3. Reader Layer (`vreader/Views/Reader/`)

#### Dispatcher

`ReaderContainerView.swift` routes to format-specific readers via
`engineReaderView(fingerprint:)`, which switches on
`ReaderEngine.resolve(format: fingerprint.format)` — an internal per-format
engine selector (feature #54). Bug #246 / GH #1072 hardened the dispatch
to route off `fingerprint.format` (the typed `BookFormat` already parsed
from the canonical `book.fingerprintKey` by the body's
`DocumentFingerprint(canonicalKey:)` guard) instead of `book.format` (a
parallel String `@Model` column set once at `Book.init` and never re-synced).
Routing off the structural primary key makes the dispatch drift-proof against
any future writer that updates one without the other (SwiftData migration,
direct context write, restore-path edit, CloudKit sync). The dispatch no
longer consults a reading-mode preference, and the reader-settings Reading
Mode picker UI is gone. The `readerReadingMode` UserDefaults key and the
`ReadingMode` enum have been removed; `ReadingModeMigration` (run
synchronously at launch from `VReaderApp`) clears the retired key from
UserDefaults and strips the `readingMode` field from per-book override
JSON files.

- `.textNative` → `TXTReaderHost`, `.markdownNative` → `MDReaderHost`,
  `.epubWKWebView` → `EPUBReaderHost`, `.pdfKit` → `PDFReaderHost`,
  `.foliateWeb` → `FoliateBilingualContainerView` (AZW3/MOBI; the
  bilingual wrapper from feature #56 WI-11 sits between the dispatcher
  and `FoliateSpikeView`, adding the bilingual VM / orchestrator / setup-
  sheet wiring without modifying the spike itself).
- `resolve(format:)` maps `.epub` to `.epubWKWebView` unconditionally (it
  stays the pure format→default-engine map). Feature #42 routes EPUB to the
  Readium Swift Toolkit engine (`ReadiumEPUBHost`) via
  `FeatureFlags.readiumEPUBEngine`, which is **default ON since the WI-14
  human-gated G2 flip (2026-06-01)** — Readium is now the default reflowable EPUB
  engine; a persisted user/debug override OFF reverts to the legacy
  `EPUBReaderHost`. The flag read lives in the dispatcher
  (`ReaderContainerView.engineReaderView` → `ReaderEngine.routeEPUB`), not in
  `resolve`, so a flag-unaware caller still gets the legacy `EPUBReaderHost`. The
  `.epubReadium` engine case exists for switch totality; `resolve` never returns
  it. **Feature #85 (approach C) makes the routing layout-aware**:
  `routeEPUB(readiumFlagEnabled:layout:)` sends EPUB **scroll** mode to the
  legacy `EPUBReaderHost` (which activates the seamless feature-#71
  continuous-scroll stitch) even when the Readium flag is ON — Readium's
  per-resource paginator has an inherent chapter-boundary seam in scroll mode —
  while **paged** mode keeps Readium. Because the SAME book is then rendered by
  two engines depending on mode, a reading-mode toggle SWAPS hosts; an in-memory
  `ReaderPositionHandoff` (a `@MainActor` per-book cache both hosts write
  synchronously on every location change + read on open before persistence)
  carries the position across the swap without loss, and a Readium open with no
  `.readium` envelope (a scroll session cleared it) restores the legacy locator
  post-open via `publication.readingOrder` + a one-shot `navCommander.navigate`.
  `EPUBScrollAnchorResolver` tolerates the container- vs OPF-relative href forms
  the two engines persist.

#### Chrome

Reader chrome (Feature #60 WI-6b — visual-identity-v2) is two custom overlays, floating on top of content with no safe-area impact:

- `ReaderTopChrome.swift` — top bar: `← Library | Title | Search Bookmark More`. Composed once in `ReaderContainerView`, format-agnostic. The `⋯` More button toggles `ReaderMorePopover`.
- `ReaderBottomChrome.swift` — bottom bar: progress scrubber + position labels + a Contents/Notes/Display/AI toolbar. Composed per format inside each container, each passing its own seek closure; the toolbar posts `.readerOpen*` notifications that `ReaderContainerView` observes. The four native containers (TXT/MD/EPUB/PDF) mount it in their `bottomOverlay`; Bug #260 added the Foliate (AZW3/MOBI) mount via `FoliateBilingualContainerView+BottomChrome.swift` — scrubber fed by the relocate `fraction`, seek via `.foliateRequestSeekFraction` → `readerAPI.goToFraction`, position labels via pure `FoliateBottomChromeLabels`. (Each container owns its own `isChromeVisible`; chrome visibility is not yet hoisted to the shared level — see Bug #262 for the cross-format desync follow-up.)
- `ReaderMorePopover.swift` — anchored More-menu popover (Feature #60 WI-6c), composed in `ReaderContainerView`'s chrome overlay. Five rows (Read aloud / Auto-turn | Book details / Share / Export); each posts a `.readerMore*` notification that `ReaderContainerView` observes. The design's sixth row (Bilingual) is deferred — GH #790.

Slot/button identity lives in `ReaderChromeButton.swift` (`ReaderTopChromeSlot` / `ReaderBottomChromeButton`); More-menu row identity lives in `ReaderMoreMenuRow.swift`.

#### Sheets (Feature #60 WI-10 — visual-identity-v2)

The app sheets share `ReaderSheetChrome.swift` — a reusable wrapper matching the design's `Sheet` component: a theme-tinted surface (`ReaderThemeV2.sheetSurfaceColor`), an optional centred Source Serif 4 title bar with 50pt leading/trailing slots (a default circular close button fills the trailing slot when an `onClose` is given and no custom trailing view is), and a scrollable body. The slide-up animation + drag grabber come from SwiftUI's own `.sheet` + `.presentationDragIndicator(.visible)`; `ReaderSheetChrome` supplies only the title bar + surface tint. It wraps the Display sheet (`ReaderSettingsPanel`), the two annotations sheets (`TOCSheet` + `HighlightsSheet`, feature #62 — see below), the reader Book Details sheet (`BookDetailsSheet`, feature #61 — opened from More → Book details, with a trailing Share button in place of the default close), and the AI sheet (`AIReaderPanel`, `title: nil` + a custom sparkle header). `SettingsView` (App Settings) keeps an inner `NavigationStack` for its `NavigationLink` push destinations, with `ReaderSheetChrome` above it. The per-sheet section contract is pinned in `SheetSectionContract.swift` (`ReaderSheetKind`). Reader sheets pass the book's `ReaderThemeV2`; the App Settings sheet uses `.paper` (the Library is not theme-switchable).

**Annotations sheets (feature #62 — annotations-panel split).** The pre-#62 unified 4-tab `AnnotationsPanelView` (Contents / Bookmarks / Highlights / Notes) is split into two job-focused sheets, each with one honest title: `TOCSheet` (book-titled — Contents + Bookmarks navigation tabs) and `HighlightsSheet` (titled "Annotations" — All / Highlights / Notes / Bookmarks review filters + a Share/export button). `ReaderContainerView` presents them via a single `.sheet(item: $annotationsRoute)` over the `AnnotationsSheetRoute` enum (`.toc(initialTab:)` / `.highlights(initialFilter:)`) — the Contents bottom-chrome button and the Notes button each map to one route; the two sheets are mutually exclusive by that optional. `HighlightsSheet`'s unified card stream interleaves highlight + standalone-note cards via `AnnotationStreamBuilder`. Both sheets' designed empty states use the shared `AnnotationsEmptyStateView` (custom SVG art). The legacy `HighlightListView` / `AnnotationListView` / `TOCListView` / `BookmarkListView` list views were removed by feature #62. Each card carries a per-row **delete affordance** (Bug #249 — a trailing `⋯` `NotesActionMenu` of Edit · Copy · Delete + an inline `NotesDeleteConfirm` strip mirroring the in-reader `HighlightPopoverDeleteConfirm`, plus a left-swipe `NotesSwipeActions` drawer); the per-row interaction phase is held on the sheet by the SHEET-owned pure `NotesRowState` (at most one row non-default at a time), and Delete routes through `HighlightListViewModel.removeHighlight` / `AnnotationListViewModel.removeAnnotation`. The container stays `LazyVStack` (not a `List`), so the swipe is a custom `DragGesture` translate rather than `.swipeActions` (which requires a `List` host).

`ReaderContainerView` drives `preferredColorScheme(_:)` from `ReaderThemeV2.preferredColorScheme` (`ReaderThemeV2+ColorScheme.swift`) so the status bar tints to match the theme — `.dark` for the Dark / OLED / Photo families, `.light` for Paper / Sepia.

#### Format Hosts (`ReaderFormatHosts.swift`)

Each host owns its ViewModel lifecycle via `@State`:

- `TXTReaderHost` → `TXTReaderContainerView` → `TXTTextViewBridge` (small single-chapter / Paged) or `TXTChunkedReaderBridge` (>500K UTF-16, **and** chaptered TXT in Scroll layout — bug #180). Chaptered TXT in Scroll layout renders as one continuous `UITableView` surface fed the whole book: `TXTContinuousChunkBuilder` splits the decoded book into document-global-offset chunks, `TXTChapterOffsetIndex` layers chapter awareness so `currentChapterIdx` is *derived* from scroll offset (no per-chapter render unit, no chapter-swap).
- `EPUBReaderHost` → `EPUBReaderContainerView` → `EPUBWebViewBridge` (WKWebView + JS injection). **Paged** EPUB loads one spine item per `loadFileURL`. **Continuous scroll** (feature #71, the DEFAULT for EPUB scroll layout since the terminal-WI flag flip on 2026-05-28 — `FeatureFlags.epubContinuousScroll` defaults ON; a persisted user/debug override can still disable it) instead loads a single bootstrap document and stitches a lazy ±1-chapter window into it: `EPUBContinuousScrollCoordinator` owns an `EPUBSpineWindow` `[lo…hi]` anchored on the reading chapter and, on the section-aware scroll observer's boundary signals, materializes the adjacent chapter (`EPUBContinuousChapterProvider` → `EPUBChapterBodyRewriter` → `EPUBContinuousScrollJS.append/prependChapterSectionJS`) and evicts the far side (`maxSpan`) to bound memory. Per-section highlight restore hangs off a `sectionMaterialized` lifecycle message (appended sections never fire `didFinish`); saved-position restore + TOC/bookmark/search navigation drive the coordinator (`navigate(toSpineIndex:fraction:)` — scroll within the window, or rebuild around an out-of-window target). The evaluator reaches the live `WKWebView` through a late-binding `EPUBWebViewEvaluatorHandle` the bridge binds in `makeUIView`.
- `ReadiumEPUBHost` (feature #42 Phase 1, WI-5) → `ReadiumNavigatorRepresentable` → Readium Swift Toolkit `EPUBNavigatorViewController`. Selected by the dispatcher in place of `EPUBReaderHost` when `FeatureFlags.readiumEPUBEngine` is ON (**default ON since the WI-14 G2 flip 2026-06-01**; a persisted override OFF reverts to the legacy `EPUBReaderHost`). Opens the publication off-main via `ReadiumEPUBReaderViewModel` (`AssetRetriever` → `PublicationOpener`), then mounts the navigator; `EPUBPreferences(scroll:)` is mapped from `ReaderSettingsStore.epubLayout`. The `ReadiumReaderCoordinator` is the `EPUBNavigatorDelegate` + (DEBUG) `ReadiumNavigatorEvaluating` seam — it registers the active navigator with `DebugReaderRegistry.setActiveReadiumNavigator` and `markReaderSettled` on `locationDidChange`, and tears that registration down on `dismantleUIViewController` via `detach()` → `clearActiveReadiumNavigator` (the host registers no `DebugReaderProbe`, so it owns its own registry teardown). Reading-position save/restore landed in WI-6: the coordinator forwards `locationDidChange` to the VM's debounced save, which maps the Readium `Locator` → a `VReaderLocator` envelope (engine `.readium`, authoritative `readiumLocatorJSON` + a lossy legacy `Locator` leg) and dual-writes it through `PersistenceActor`'s `VReaderLocatorPersisting` conformance — `saveVReaderLocator` writes both the envelope blob into the SchemaV8 `ReadingPosition.vreaderLocatorData` column AND the legacy `locator`; legacy `savePosition` clears the envelope so a flag-OFF write can't be shadowed by a stale Readium position. On open, the host loads the saved envelope (`restoredReadiumLocator()`) before the navigator mounts and passes it as `initialLocation`. Theme/font landed in WI-7: the host body reads `ReaderSettingsStore.theme` + `.typography` + `.epubLayout` (tracked `@Observable` deps) and recomputes a full `EPUBPreferences` on any Display-settings change, which `updateUIViewController` re-submits live (`submitPreferences`). `ReadiumEPUBReaderViewModel+Mapping` translates the 5 `ReaderThemeV2` themes → Readium's 3 base `Theme`s + explicit `backgroundColor`/`textColor` (which win via `effectiveBackgroundColor`); font size from the per-format-calibrated `.epub` size (`FontSizeCalibrator`) → Readium's multiplier; `lineHeight` from `lineSpacing`; `fontFamily` (system→sansSerif, serif/sourceSerif4→serif, monospace→monospace, inter→sansSerif — custom-font registration deferred); `publisherStyles=false`. The WI-7 photo/custom-background refinement composites the decorative image behind the navigator: `ReadiumEPUBHost+Background.swift` layers the existing `ThemeBackgroundView` under the navigator in a `ZStack` (only when `useCustomBackground` + an image exists for the theme), and `ReadiumReaderCoordinator+Transparency` makes the navigator render through — `epubPreferences(..., transparentBackground:)` emits `backgroundColor: nil` (so ReadiumCSS injects no body bg rule), the representable forces `navigator.view`/spine `WKWebView`s `.clear`/`isOpaque=false`, and a read-only self-gating user script clears the opaque `html:root` ReadiumCSS paints (transparency state is authored into `localStorage` by Swift on each `locationDidChange`/toggle). Normal opaque themes are unchanged. Highlights landed in WI-8: `ReadiumDecorationHighlightAdapter` (a `HighlightRenderer`, the Readium counterpart of `EPUBHighlightRenderer`) renders stored highlights as Readium **Decorations** via `EPUBNavigatorViewController.apply(decorations:in:"highlights")` (declarative — the adapter holds the active set and re-submits the whole group on each apply/remove/restore). Re-anchoring is **text-quote** based (WI-8a migration spike): each `HighlightRecord` → `Decoration(locator: Locator(href:, text: .Text(highlight: selectedText, before/after: context)), style: .highlight(tint:))` — Readium re-finds the quote, so the legacy XPath `serializedRange` is never consulted or mutated (flag-OFF returns to legacy XPath rendering losslessly). The host owns the adapter + a `HighlightCoordinator(renderer: adapter)`, calls `restoreAll()` on open, and observes `.readerHighlightRemoved`/`.readerHighlightsDidImport`. The WI-8 new-highlight refinement adds CREATE from a live Readium selection: `ReadiumReaderCoordinator` conforms to `SelectableNavigatorDelegate` and `navigator(_:shouldShowMenuForSelection:)` forwards the finalized `Selection` to the host then returns `false` (suppressing Readium's native menu so the designed `SelectionPopoverView` is the sole selection surface — rule 51). `ReadiumEPUBHost+Highlights` stashes the `Selection` in a generic `ReadiumSelectionTokenCache<Selection>` under a token, presents the popover; on a color tap (`.readerHighlightRequested`) it resolves the token and `ReadiumSelectionHighlightBuilder` maps the `Selection`'s text-quote (highlight/before/after) + container-relative href → `HighlightRecord` inputs → `HighlightCoordinator.create` → the same `ReadiumDecorationHighlightAdapter` renders it immediately; `navCommander.clearSelection()` dismisses the selection. Navigation landed in WI-9a: the host observes the shared reader nav bus — `.readerNextPage`/`.readerPreviousPage` → the coordinator's `goForward`/`goBackward`, and `.readerNavigateToLocator` (TOC/bookmark/search-result tap, object = a vreader `Locator`) → `go(to:)` after mapping the vreader Locator → Readium Locator (`readiumLocator(fromVReader:spineHrefs:)`, reusing the WI-8 legacy→spine href resolution). Host→coordinator dispatch goes through a host-owned `ReadiumNavCommander` (`@State`, bound on `attach`/cleared on `detach`, mirrors the WI-8 adapter ownership). WI-9a also split the host into `ReadiumEPUBHost.swift` (View) + `ReadiumNavigatorRepresentable.swift` + `ReadiumReaderCoordinator.swift`. Footnotes (#138, WI-9b) remain. Search result-list extraction still uses the existing FTS/`SearchViewModel` stack — WI-9a maps only result *navigation*. **Bilingual landed in WI-11 (paged) and WI-12 (scroll parity): interlinear bilingual works under the flag by driving the enumerate→prefetch→inject loop through Readium's one-way `evaluateJavaScript(_:) async -> Result<Any,Error>` channel — NOT a script-message handler (the navigator owns its content controller, exposing no app-side message channel; this is why the WI-11a `ReadiumBilingualEvalAdapter` RETURNS the `[{bid,text}]` array rather than posting it). A host-owned `ReadiumBilingualCommander` (`@State`, the bilingual counterpart of `ReadiumNavCommander`) holds an evaluator closure the coordinator binds on `attach` (the production non-DEBUG `ReadiumReaderCoordinator.evaluateForBilingual`, returning Readium's raw `Result<Any,Error>?`) and clears on `detach`; `enumerate()` runs `ReadiumBilingualEvalAdapter.enumerateJS()` and parses the return value via `EPUBBilingualPipeline.parseEnumerateMessage`, `inject(_:)`/`clear()` run the engine-agnostic inject/clear builders. The host reuses the feature-#56 `EPUBBilingualOrchestrator` (paged `-1` bucket via `updateBlocks(_:)`) + `BilingualReadingViewModel` + the designed `BilingualSetupSheet` (rule 51 — no new UI). Source text comes from vreader's own `EPUBParser` (opened alongside the Readium open — Readium does not expose raw spine HTML), so the `EPUBChapterTextProvider` is keyed on OPF-relative spine hrefs; the Readium-produced vreader `Locator` carries Readium's CONTAINER-relative href, so `ReadiumBilingualCommander.normalizedLocator(_:toSpineHrefs:)` rewrites it onto the OPF spine via the shared `ReadiumDecorationHighlightAdapter.resolveHref` tolerance before `vm.handlePositionChange(...)` (the WI-8 href-consistency finding class — without it `unit(containing:)` returns nil and nothing translates). Chapter-change detection composes onto the existing `onLocationChange` (WI-6 position save still runs): a fresh enumerate runs only when the spine href changes, deduped intra-chapter by a reference-type `ReadiumBilingualChapterTracker`. WI-12 lifted the WI-11 paged-only gate (`isBilingualSupported` is true for both layouts) so bilingual works in scroll too — but PER-SPINE only: Readium scroll mode is per-resource (it emits `locationDidChange` at spine boundaries, driving the same per-spine enumerate the paged path uses), and Readium has no multi-spine-stitch API, so off-screen chapters enumerate when scrolled into view rather than eagerly. This is a documented behavior delta vs legacy #71 — the flag-OFF `EPUBWebViewBridge` engine keeps its full stitched cross-chapter continuous bilingual; the Readium engine does not reproduce it. A paged↔scroll layout change re-renders the spine (discarding the `data-vreader-bid` stamps + decorations), so the layout-change handler re-enumerates the current spine in both directions.** TTS (WI-10): read-aloud already works under the Readium engine with NO Readium-specific code — `ReaderContainerView.startTTS()` → `ReaderAICoordinator.loadBookTextContent(format: "epub")` extracts spine text from the **file** via `EPUBParser` (renderer-agnostic, independent of which engine renders), then feeds the shared `TTSService` pipeline. Device-verified under `readiumEPUBEngine` ON (speaking, `ttsOffsetUTF16` advancing 42→115, stop→idle). The speaking-position **follow** landed in WI-10b: as TTS speaks, the navigator auto-advances so the spoken text stays on screen. `ReadiumEPUBHost` observes the shared `TTSService.currentOffsetUTF16` (threaded in like `EPUBReaderHost`); a pure value-type `ReadiumTTSFollowMapper` maps the flat UTF-16 offset → (spine href, intra-spine fraction). CRITICAL alignment: the per-spine offset table is built from the SAME spine text the TTS engine reads — `EPUBTextExtractor.stripHTML` + trim, skip empties, join `"\n\n"` (the `ReaderAICoordinator.loadBookTextContent` recipe) — extracted off-main from the host's already-open `bilingualParser` (so the index matches the engine's offsets; the block-preserving bilingual stripper is deliberately NOT used here). `ReadiumEPUBHost+TTSFollow` throttles: it navigates on any spine-href change or an intra-spine fraction drift > 0.08 (so the navigator tracks ~chapter-eighth granularity, not every `willSpeakRange` word), maps the target → a vreader `Locator` → Readium `Locator` via the WI-9a `readiumLocator(fromVReader:spineHrefs:)` resolution, and drives the existing `navCommander.navigate(to:)` → `navigator.go(to:)`. Follow runs only while TTS state == `.speaking`; the cursor resets on each play start and on pause/stop. This unblocks the WI-14 default-ON flip.
- `PDFReaderHost` → `PDFReaderContainerView` → `PDFViewBridge` (PDFKit)
- `MDReaderHost` → `MDReaderContainerView` → reuses `TXTTextViewBridge` with NSAttributedString
- AZW3/MOBI is dispatched directly to `FoliateSpikeView` (the AZW3 spike landed before the host abstraction; convergence is deferred). `FoliateReaderHost` / `FoliateReaderContainerView` exist but are not currently wired into `ReaderContainerView`. **Feature #73 added a windowed multi-section continuous-scroll surface inside the vendored Foliate-js `paginator.js`** (default ON for horizontal-writing scroll mode, gated behind the renderer's `#windowedScroll`). Instead of the per-section view-swap — whose `scrollToAnchor(0)` offset reset + blank-flash on `#createView` destroy/async-load + post-swap reflow were the three stacked discontinuities of the Bug #283 chapter-boundary jump — a K=3 window of adjacent sections is mounted into the single scrolling `#container` and recycled on scroll: `#ensureWindow` mounts neighbours (firing the same `load`/`create-overlayer` lifecycle so each neighbour doc is wired for selection/overlays), `#evictOutsideWindow` unmounts + unloads the far side with `scrollTop` compensation, `#promoteCurrentView` tracks the current section by scroll position (a pointer swap, no DOM move), and `#windowedResolve` emits the intra-section relocate fraction (`progress.js`/`SectionProgress` still owns whole-book conversion, preserving Bug #265 position restore). A `#windowGeneration` token aborts stale async mounts across navigation. Vertical writing + paged mode keep the single-`#view` swap path. The pure windowing math (window clamp, offset↔section mapping, intra-section fraction, evict adjustment, anchor translation) is mirrored + unit-tested in `FoliateScrolledWindowMath.swift`; flag-on behavior was device-verified and the JS diff passed a 2-round independent Codex audit.

#### Foliate-js Bridge (`vreader/Views/Reader/`, `vreader/Services/Foliate/`)

`FoliateViewBridge` (UIViewRepresentable) hosts a WKWebView and uses `loadHTMLString` with the IIFE-bundled `foliate-bundle.js` inlined; books are handed to JS as base64 (no scheme handler in the live load path — `FoliateURLSchemeHandler` exists in the codebase but isn't wired into the active bridge today). `FoliateViewCoordinator` (WKScriptMessageHandler + WKNavigationDelegate) receives JS messages, parses via `FoliateMessageParser`, and routes to typed callbacks. `FoliateHighlightRenderer` generates JS strings for SVG overlay annotations — but it is **not** plugged in as a `HighlightRenderer` adapter today; AZW3 highlight create has a TODO for persistence/JS injection and overlay restore is a no-op placeholder (`FoliateReaderContainerView+Highlights.swift`). `FoliateJSEscaper` provides shared sanitization for all JS/CSS string interpolation across the bridge. `FoliateReaderViewModel` maps bridge events to `Locator` for position persistence.

The Foliate JS bundle is built from sources under `vreader/Services/Foliate/JS/` via `build-bundle.sh`, which calls a locally-pinned esbuild (`package.json` + `package-lock.json`, currently `esbuild@0.28.0`; bootstrapped via `npm ci` — node ≥18). `paginator.js` is the source of truth; `foliate-bundle.js` is checked in and must be rebuilt whenever the source changes (a parity check in `FoliatePaginatorScrollBoundaryTests` enforces this for the scroll-mode boundary-detect helper that resolved Bug #235).

#### Unified Engine (retained, not dispatched)

`ReaderUnifiedCoordinator` loads text + applies transforms (replacement rules, simp/trad); `UnifiedTextRenderer` displays with TextKit 2 pagination or scroll. Feature #54 removed the unified path from the reader dispatch and the reader-settings Reading Mode picker, so this stack is **no longer reachable from reader dispatch** — it is retained (a follow-up may consume it for bilingual reading, or delete it once provably orphaned). Content replacement rules and Chinese conversion that previously required Unified mode now run in the native readers directly: `MDFileLoader.load` composes `ReplacementTransform` + `SimpTradTransform` over the decoded source text before parsing (feature #54 WI-7); **native EPUB applies replacement rules via `EPUBReplacementJS` (feature #54 Phase D-1)** — a CFI-safe per-text-node JS injection that runs on both EPUB engines (Readium per-spine via `ReadiumReaderCoordinator+Replacement`; the legacy #71 WKWebView stitch on `didFinish` via `EPUBWebViewBridgeCoordinator`, plus a scroll-root `MutationObserver` for appended chapters), keyed by `MDReplacementRuleFetcher`; native TXT has Chinese conversion only — TXT replacement rules are deferred (they need a source↔display offset map). Replacement rules apply at chapter/document open; a mid-read rules edit takes effect on next open (v1 scope).

### 4. Coordinator Layer (`vreader/Views/Reader/`)

Cross-format coordinators that compose with multiple readers:

| Coordinator                | Responsibility                                                      | Setup Timing                                                          |
| -------------------------- | ------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `ReaderAICoordinator`      | AI ViewModels, text loading, context extraction                     | On AI/TTS invoke                                                      |
| `ReaderSearchCoordinator`  | Search service, indexing, FTS5                                      | Service+VM eagerly via `prepareEagerly()` on reader open (bug #79; cold SQLite open is `nonisolated`, off-MainActor); indexing still deferred to `setup()` on first sheet open |
| `ReaderUnifiedCoordinator` | Unified renderer state, text transforms — retained but no longer dispatched (feature #54) | n/a (no dispatch path)                                     |
| `HighlightCoordinator`     | Persists via `HighlightPersisting`, dispatches to `HighlightRenderer` adapters | On reader open per format (TXT/MD/PDF/EPUB)                          |

Bridge-internal coordinators (`EPUBWebViewBridgeCoordinator`, `FoliateViewCoordinator`, `TXTTextViewBridgeCoordinator`) handle delegate / WKScriptMessageHandler plumbing for one bridge each; they're not cross-cutting and aren't enumerated here.

### 5. Services Layer (`vreader/Services/`)

| Service                              | Backing                    | Purpose                                                                   |
| ------------------------------------ | -------------------------- | ------------------------------------------------------------------------- |
| `PersistenceActor`                   | SwiftData (actor-isolated) | All DB writes serialized                                                  |
| `SearchService` + `SearchIndexStore` | SQLite FTS5                | Full-text search with persistent index                                    |
| `AIService`                          | OpenAI-compatible REST API | Summarize, translate, chat. Feature #56 added a resolved-provider seam — `ResolvedAIProviderConfig` (an immutable `{kind, baseURL, apiKey, model, maxTokens}` snapshot) plus `resolveActiveProviderConfig()` / `resolveProviderConfig(profileID:modelOverride:)` / `sendRequest(_:using:)`. A *multi-request* operation (chapter translation = one request per chunk) resolves the config ONCE and pins the credential + model for every chunk; `sendRequest(_:using:)` deliberately bypasses `AIResponseCache` (its key is not provider-aware). The original `resolveProvider()` / `sendRequest(_:)` / `streamRequest(_:)` are unchanged. **Feature #91 (agentic tool-calling)** added `supportsToolUse` + `sendToolRequest(_:)` on `AIProvider` (Anthropic `tool_use` / OpenAI `tool_calls`; default-off so non-tool providers compile unchanged), and on `AIService`: `resolveToolProvider()` (resolve the config ONCE + report tool-use capability), `sendToolTurn(_:using:)` + `streamRequest(_:using:)` (one turn/stream through the pinned config, RE-checking the live flag + consent each turn so a mid-loop revoke fails closed) |
| `AgenticChatDriver` + `AIToolRegistry` (`Services/AI/`) | `AIService` + the tool executors | **Feature #91 — agentic AI chat.** `AgenticChatDriver` is the bounded send→tool→result→re-send loop (one pre-resolved provider via `AIServiceToolUseAdapter`, `maxIterations` cap, returns `{finalText, usedTools}`); `AIToolRegistry` dispatches a model `ToolCall` to its `AITool` (unknown tool → `isError` result, never throws). Four read-only executors wrap existing capabilities: `search_current_book` (the open book's FTS), `search_other_books` (the whole library, gated by the pure `LibraryBookSearchGate` over the persistent index), `get_book_content` (a book's text by title, locality/format-gated), and `list_library` (feature #97 — enumerate the bookshelf: title/author/format, over the same `LibrarySearchBackend.libraryBooks()`; dedupe, open-book exclude, total deterministic sort, cap+announce, canonical-format display, restore-placeholder friendliness). `AgenticToolRegistryBuilder.buildLive` assembles them over the production `LibrarySearchBackendAdapter` + `BookContentProviderAdapter` (+ `ClosedBookTextExtractor`) and the shared `PersistentSearchIndex` store. `AIChatViewModel.sendMessage` routes through the driver when `agenticTools` is on + the resolved provider supports tool-use (silent loop, single final answer, citations suppressed on a tool reply); otherwise the existing streaming path. Default OFF |
| `PersistentSearchIndex` (`Services/Search/`) | `SearchIndexCore` + `SearchIndexStore` | The single Services-layer source of truth for the on-disk FTS index location (`Application Support/SearchIndex/search.sqlite3`) + persistent-store construction (`makeStore()`, in-memory fallback). `ReaderSearchCoordinator` delegates to it; Feature #91's agentic search tools open the SAME persisted index through it |
| `TTSService`                         | `SpeechSynthesizing` seam | `@MainActor @Observable` read-aloud state machine (idle/speaking/paused + UTF-16 progress offset). Speaks through an injected `SpeechSynthesizing` and wires its `AVSpeechSynthesizerDelegate` callbacks generically via the protocol's `delegateTarget` (feature #72 WI-0), so any backend — on-device, XCUITest mock, or the cloud adapter — drives progress without type-casing. `defaultSynthesizer(configStore:)` picks the backend: XCUITest mock (DEBUG override) > `HTTPSpeechSynthesizer` when a valid `HTTPTTSConfig` is persisted (feature #72 WI-3) > `SystemSpeechSynthesizer` (on-device) |
| `HTTPSpeechSynthesizer`              | `HTTPTTSProvider` + `HTTPTTSChunkPlayer` | Feature #72 WI-3 cloud-TTS adapter: the `SpeechSynthesizing` impl that finally wires the orphaned `HTTPTTSProvider` (bug #270) into live read-aloud. Per `speak`, chunks the utterance (`HTTPTTSProvider.chunkText`), synthesizes each chunk over HTTP, streams the audio blobs into `HTTPTTSChunkPlayer`, and emulates the `AVSpeechSynthesizerDelegate` callbacks `TTSService` consumes (chunk-range `willSpeakRange`, `didFinish`, `didCancel`). Conforms to the non-isolated protocol via `@unchecked Sendable` + `MainActor.assumeIsolated` wrappers over `@MainActor` impls; `TTSService` (its only caller) is `@MainActor`. Audio session stays owned by `TTSService` |
| `HTTPTTSChunkPlayer`                 | `AVAudioPlayer` (behind `SpeechAudioPlaying` seam) | Feature #72 WI-2 sequential audio-chunk playback queue for the cloud path. Plays streamed `Data` chunks back-to-back, fires `onChunkStarted(index)` as each begins and `onFinished` once the LAST chunk of a COMPLETE input drains (drain ≠ complete — `markInputComplete()` gates the finish). Generation token ignores late finishes from stopped/replaced players. Does NOT manage `AVAudioSession` |
| `HTTPTTSConfigStore`                 | `UserDefaults` + `KeychainService` | Feature #72 WI-1 loader: decodes the persisted `HTTPTTSConfig` from UserDefaults and splices the API key from Keychain; `loadValidConfig()` returns the config only when it passes `validate()`. Consumed by `TTSService.defaultSynthesizer` to decide whether the cloud path is active |
| `BookContentCache`                   | In-memory                  | Text cache for AI context loading (TXT/MD only)                           |
| `PreferenceStore`                    | UserDefaults               | Sort order, view mode persistence                                         |
| `ReadingStatsAggregator`             | SwiftData (actor-isolated) | Reading-stats dashboard aggregator (feature #58). Sweeps `ReadingSession` + `Book` rows in one `ModelContext` pass and returns a `ReadingDashboardSnapshot` — per-window totals (today / 7d / 30d / 90d / 180d / 365d / all) + per-book breakdown. Derives every number from session rows, never from `ReadingStats`, so a stale stats cache cannot desync the dashboard. Holds a `@Sendable () -> Calendar` provider so window boundaries follow timezone/DST changes. **WI-6b**: `snapshot(window:sort:now:customRange:)` accepts an optional user-picked `ReadingStatsCustomRange` (calendar-day-inclusive `[start, end]`); when non-nil, the snapshot's `perBook` + `customRangeBreakdown` reflect that range while the seven enum totals stay populated for the pill bar |
| `CustomCoverStore`                   | JPEG files                 | Custom book cover images                                                  |
| `WebDAVClient`                       | HTTP                       | Low-level WebDAV transport (PROPFIND/PUT/GET/DELETE/MKCOL/MOVE)           |
| `WebDAVProvider`                     | `WebDAVClient`             | `BackupProvider` impl — backup/restore/list/delete over a WebDAV server   |
| `WebDAVProviderFactory`              | `WebDAVServerProfileStore`  | Assembles a `WebDAVProvider` from the active WebDAV profile (feature #52 WI-3 + WI-5). `make(persistence:profileStore:)` is the sole production path — the pre-#52 `make(keychain:)` flat-keychain variants were removed in WI-5 |
| `WebDAVServerProfileStore`           | `UserDefaults` / `KeychainService` | Actor-isolated list of saved WebDAV server profiles with one active selection (feature #52 WI-1). Profiles + active-id persist as `UserDefaults` JSON; per-profile passwords persist in Keychain. Atomic `loadSnapshot`, `upsert` / `remove` / `setActiveProfileID`, single-hop `updateIfExists`. Mirrors `ProviderProfileStore` (feature #50) for the AI multi-profile precedent |
| `WebDAVProfileMigrator`              | `KeychainService` / `WebDAVServerProfileStore` | One-shot migrator that lifts pre-#52 flat-keychain credentials (`com.vreader.webdav.{serverURL,username,password}`) into a `"Default"` profile and sets it active. Idempotent on both axes (marker key + non-empty store). Feature #52 WI-2 |
| `ReadingModeMigration`               | `UserDefaults` / per-book JSON files | One-shot **synchronous** launch migration retiring the Native/Unified reading mode (feature #54). Removes the `readerReadingMode` UserDefaults key and strips the `readingMode` field from per-book override JSON files (edited as raw `JSONSerialization` objects so other keys are semantically preserved). Synchronous-before-setup — the per-book JSON store has no actor, so a detached migration could race a panel save/restore. Idempotent |
| `BackupDataCollector`                | `PersistenceActor`         | Serializes 8 versioned JSON sections (annotations, positions, settings, library-manifest, …) |
| `BackupDataRestorer`                 | `PersistenceActor`         | Decodes + dedupes by UUID/profileKey; rejects future schema versions      |
| `BlobPath`                           | —                          | Pure utility: `(format, sha256, byteCount)` ↔ `VReader/books/<format>/<sha>_<bytes>.<ext>` (feature #46) |
| `BackupBlobStore` (protocol pair)    | —                          | Transport-neutral read (`BackupBlobReading`) + write (`BackupBlobWriting`) blob API |
| `WebDAVBlobStore`                    | `WebDAVTransport`          | Adapter that owns the temp+MOVE atomic-publication algorithm (feature #46) |
| `BookFileMaterializer`               | `BackupBlobReading` + `BookImporting` | Restore-side: download + size/SHA-256 verify + import via `BookImporter`. Preflight-rehashes existing local files to catch corrupt content (feature #46). Refactored in feature #47 WI-4a to delegate verify + import + fingerprint match to `BookFileImportFinalizer`. |
| `BookFileImportFinalizer`            | `BookImporting`            | Shared verify + import + fingerprint pipeline used by both `BookFileMaterializer` (restore-all path) and the lazy-download coordinator (feature #47 WI-4b). Streaming SHA-256 so very-large blobs don't spike memory. Caller owns temp-file lifetime. |
| `RemoteBookCatalog`                  | —                          | Pure decoder: extracts `library-manifest.json` from a backup ZIP via `ZIPWriter.extractEntry(named:from:)` and returns `[BackupLibraryEntry]`. Surfaces `manifestMissing` (older backups) / `manifestUndecodable` / `manifestSchemaVersionTooNew` as typed errors. Feature #47 WI-4a. |
| `SelectiveRestoreCoordinator`        | `BookFileMaterializer` + `PersistenceActor` + `BackupDataRestoring` | 3-phase orchestrator for the picker-driven restore: (1) preplant unselected entries as `.remoteOnly` rows, (2) materialize selected entries via `BookFileMaterializer`, (3) apply metadata sections so positions/annotations reattach to BOTH `.local` and `.remoteOnly` rows by fingerprintKey. Phase-weighted progress 0.10/0.75/0.15. Feature #47 WI-4b. |
| `LazyDownloadCoordinator`            | `BackgroundDownloadSessioning` + `PersistenceActor` | `@MainActor @Observable`. Receives forwarded events from a non-isolated `LazyDownloadDelegate` and exposes per-fingerprintKey progress + outcome state to library rows. Reattaches in-flight tasks at init via `URLSession.getAllTasks(...)` and reconciles orphaned `.downloading` rows (no live task) to `.failed`. Race-safe sticky `terminalKeys` guard outlives `clearOutcome(for:)`. Feature #47 WI-3. |
| `LazyDownloadDelegate`               | URLSessionDownloadDelegate | Nonisolated delegate that hops to MainActor via `Task` to forward `didWriteData` / `didFinishDownloadingTo` / `didCompleteWithError` / `urlSessionDidFinishEvents` events to the coordinator. Cancels orphaned tasks (missing/invalid `taskDescription`) and validates SHA/extension shape before staging. Feature #47 WI-3. |
| `LazyDownloadTaskMeta`               | —                          | `Codable Sendable` payload encoded into `URLSessionDownloadTask.taskDescription` so identity (`fingerprintKey`, `blobPath`, `expectedSHA256`, `expectedByteCount`, `originalExtension`) survives crash + relaunch. `schemaVersion` gate (`1...currentSchemaVersion`) rejects future formats. Feature #47 WI-3. |
| `BackgroundDownloadSessioning`       | `URLSession.background(...)` (production) / mock (tests) | Test seam for the background URLSession's `getAllTasks` enumeration. Production wrapper (`URLSessionBackgroundSession`) holds the live session; tests synthesize `LazyDownloadTaskDescriptor` values. Feature #47 WI-3b. |
| `WebDAVNetworkPolicy`                | `NWPathMonitor`            | `@MainActor @Observable` Wi-Fi-only gate. UserDefault `com.vreader.webdav.wifiOnly` (default true) + `currentInterface: .unknown / .none / .cellular / .wifi`. `shouldStart() -> Bool` consulted by the lazy-download enqueue path (#47 WI-4 follow-up) and "Restore all" guards. URLSession's `allowsCellularAccess = false` cancels rather than pauses, so we keep cellular allowed and gate at enqueue. Feature #47 WI-3c. |
| `FoliateURLSchemeHandler`            | WKURLSchemeHandler         | Scheme-handler implementation (not on the live load path; see Foliate-js Bridge note) |
| `FoliateMessageParser`               | Pure functions             | Parses raw JS message bodies into typed Swift events                      |
| `FoliateJSEscaper`                   | Pure functions             | Escapes/sanitizes strings for safe JS/CSS interpolation in Foliate bridge |
| `ReaderSettingsStore`                | UserDefaults               | Global reader UI prefs: theme, typography, EPUB layout, auto-page-turn, page-turn animation, Chinese conversion, custom background |
| `PerBookSettingsStore`               | Per-book JSON files        | Per-book overrides on top of `ReaderSettingsStore` (font/theme/spacing) |
| `FontSizeCalibrator`                 | Pure value type            | Maps the stored unified font-size value to a per-renderer concrete value via `FontSizeCalibrationProfile` multipliers (`txt`/`md`/`epub`/`foliate`), so the same slider number renders at a consistent perceived size across reflow formats. TXT is the `1.0` anchor; result re-clamped to each renderer's legal band (`12...64` text, `8...72` Foliate). PDF is intentionally not a target. Feature #70 |
| `KeychainService`                    | Keychain                   | Secure credential storage (used by `WebDAVProviderFactory`)               |
| `BookSourcePipeline`                 | Actor + HTTP / rule engine | Search → BookInfo → TOC → Content scraping for Legado-style web novels    |
| `SyncService`                        | CloudKit (feature-flagged) | Coordinates sync with `SyncConflictResolver`, tombstones, change tokens   |
| `DebugBridge`                        | URL handler (DEBUG-only)   | `vreader-debug://` reset/seed/open/settle/snapshot/eval/tts/search/highlight/provider/present/ai/seed-sessions/seek/scroll-sheet/navigate/scroll-boundary/locate?highlight=N; feature #49 added position-aware open + DebugSnapshot schema v2 (TTS state, render phase, settings provenance); feature #74 added `locate?highlight=<N>` to drive `.readerNavigateToLocator` for the active TXT/MD reader CU-free so the locate "bloom" (highlight/note landing) fires on the real render path, plus DebugSnapshot schema v3 (`landingBloomCount` / `landingBloomPeakIntensity`) read back from `HighlightableTextView`'s persisted bloom counters — the ~1.5s sub-second bloom visual can't be screenshot/video-captured on the virtual display, so the snapshot proves it fired; feature #45 WI-4c-b added `tts?action=start\|stop` to bypass XCUITest's audio-session block; bug #238 added `search?query=...[&index=N]` to drive search-result-tap repros (Bug #182 / GH #621) CU-free; bug #237 added `highlight?start=...&end=...[&color=...]` for TXT/MD highlight creation CU-free; bug #243 added `provider?action=add\|remove\|clear` for AI provider configuration without driving Settings → AI through CU (unlocks Feature #56 b/d / Feature #65 / Feature #69 / Bug #93 autonomous AI verification); bug #253 added `present?sheet=...[&tab=...]` + bug #255 added `ai?action=summarize\|chat\|translate` for CU-free reader-sheet + AI-response-card verification; bug #263 added `seed-sessions?book=<key>[&seconds=<n>]` to seed a deterministic `ReadingSession` spread (one per dashboard window band) so the reading-stats dashboard (Feature #58) renders non-zero per-window totals CU-free; bug #267 added `seek?fraction=<0...1>` to drive the active Foliate (AZW3/MOBI) reader to a fractional position CU-free; bug #271 added `scroll-sheet?to=top\|bottom` to scroll the active presented sheet's content (today `TranslationResultCard`) so the accent translation card below the tall ORIGINAL card — beyond even the `detent=large` fold (Bug #256) — becomes screenshot-capturable, unblocking Feature #65 row 11; bug #273 added `navigate?spine=<N>[&fraction=<F>]` to drive `.readerNavigateToLocator` for the active EPUB reader CU-free (the `search` driver doesn't navigate in continuous mode), posting DEBUG-only `.debugBridgeNavigateCommand` → `EPUBReaderContainerView` resolves spine → href → `Locator` → re-posts `.readerNavigateToLocator` — unblocking feature #71 WI-8 continuous-mode navigation verification (paired with the `multi-chapter-epub` 4-tall-chapter fixture for the out-of-window rebuild branch); a follow-up added `scroll-boundary?spine=<N>&near=top\|bottom` to post a DEBUG-only `.debugBridgeScrollBoundaryCommand` → `EPUBReaderContainerView` builds an `EPUBScrollBoundarySignal` and calls `EPUBContinuousScrollCoordinator.handleBoundarySignal` directly — bypassing the rAF-throttled `continuousScrollObserverJS` (unverifiable CU-free on a virtual display) so feature #71's scroll-driven extend/evict RESPONSE can be device-verified. **Host-vs-runner driving constraint (bug #242 / GH #1054)**: bridge URLs MUST be invoked from the host (`xcrun simctl openurl` outside any iOS sandbox) — invoking them from inside an XCUITest binary fails with NSPOSIX 61 because the runner sandbox blocks the CoreSimulatorService XPC endpoint. In-runner verification flows use `XCTSkipUnless(bridgeReachable())` (PR #1053) when they cannot move the bridge-dependent assertion to a host-side driver. See `docs/subsystems/debug-bridge.md` § "Driving the bridge from a verification flow". |
| `DebugPositionResolver`              | —                          | Pure parser: `?position=<value>` string → typed `DebugPosition` per BookFormat (TXT/MD UTF-16 offset, EPUB CFI, AZW3 Foliate-CFI, PDF page). Every format takes its native seek path (feature #54 retired the Native/Unified mode + its position-unsupported guard). Feature #49 WI-7a. |
| `DebugReaderRegistry.awaitReader`    | DebugReaderRegistry singleton | Token-based keyed waiter that resumes when a reader matching `fingerprintKey` registers. Concurrent waiters with different timeouts each get their own continuation (UUID-token ownership). Feature #49 WI-7a. |
| `DebugReaderRegistry.awaitReaderSettled` | DebugReaderRegistry singleton (`+Settle` extension) | Bug #141: render-settled signal keyed by `(fingerprintKey, token)`. Hosts call `markReaderSettled` on real render-complete — EPUB from `webView(_:didFinish:)`, AZW3/MOBI from the Foliate `relocate` message. `ReaderContainerView` wires `probe.settleStrategy` so `vreader-debug://settle` blocks until that signal (or `settleTimeout`) instead of the 100ms placeholder. TXT/MD/PDF keep the placeholder. Same UUID-token waiter machinery + stale-write guard as `awaitReader`. |
| `ImportJobQueue`                     | Actor                      | Serializes book imports (avoids parallel `BookImporter` writes)           |
| `FileURLImportRouter`                | `BookImporting` (protocol) | `@MainActor` dispatcher for incoming `file://` URLs from iOS Share Sheet / "Open in vreader" (Feature #59 WI-2). Wired by `VReaderApp`'s production `.onOpenURL`. Returns `false` for non-file URLs (Debug-bridge handler intercepts those upstream). Unsupported extensions reported via injected closure (App layer wires the user-facing alert; current production wiring is a no-op). Supported extensions kick off `bookImporter.importFile(at:source:.shareSheet)` in a fire-and-forget Task. Security-scope handling owned by `BookImporter`, not the router. |
| `LibraryRefreshService`              | NotificationCenter         | Coalesces library refresh requests across views                           |
| `FeatureFlags`                       | Static                     | Compile/runtime flag resolution (`SyncService` and others gate on it). Feature #91 added `agenticTools` (default OFF, persisted) — gates the AI chat's agentic tool-calling loop |
| `DictionaryLookup`                   | UIKit                      | System dictionary + AI-translate hooks for selected text                  |
| `DiagnosticsLogStore` + `OSLogDiagnosticsSource` + `DiagnosticsRedactor` (`Services/Diagnostics/`) | `OSLogStore` (current-process) | **Feature #96 — in-app runtime diagnostics.** `DiagnosticsLogStore` (`@MainActor @Observable`) reads the current session's `com.vreader.app` `Logger` entries back via the `DiagnosticsLogSource` seam (`OSLogDiagnosticsSource` runs the blocking `OSLogStore` enumeration off-main), holds them bounded, filters by level/category, and produces a `DiagnosticsRedactor`-scrubbed export string. `DiagnosticsRedactor` is a pure, context-driven secret/path scrubber (Authorization, keyed secrets, `sk-`/JWT keys, URL creds, container paths) — the defense-in-depth second line over OSLog's `.private` barrier for anything leaving the app (export file + Copy-entry). WI-2 added the Settings → Support → Diagnostics viewer (`Views/Settings/Diagnostics/`) binding to the store |
| `ChapterTranslationStore`            | SwiftData (actor-isolated) | Persistent disk cache for feature #56 bilingual reading. Wraps its own `ModelContext` over the `ChapterTranslation` `@Model` (SchemaV7) — a separate actor from `PersistenceActor` so bulk translation writes during a global-translate run never block library reads. App-scoped `.shared` single instance (the `ProviderProfileStore.shared` precedent); idempotent `upsert` fetches by `lookupKey` and updates in place, never relying on the unique constraint to throw. Returns the value-type `ChapterTranslationRecord` DTO, never the `@Model`. Bug #342: lazily migrates pre-#342 5-field keys (profile UUID baked in) to the canonical 4-field key on first access, deduping to the newest row. The cache is derived, re-fetchable data — excluded from WebDAV backup |
| `ChapterTranslationService`          | `ChapterTranslationStore` + `AIService` | Translates one chapter unit for feature #56 bilingual reading. Pipeline: cache lookup → (on miss) `ChapterSegmenter` → `ChapterTranslationChunker` → one `AIService.sendRequest(_:using:)` per chunk → strict `TranslationChunkContract` JSON-array decode → per-segment fallback on any decode/count/element mismatch → recombine → cache-write. Reaches the AI side through the `TranslationRequestSending` boundary protocol (tests inject a mock). `Task.checkCancellation()` between chunks so a cancelled prefetch stops promptly |
| `ChapterTextProviding` (`Services/Reader/`) | per-format reader services | Feature #56 WI-2.5 boundary protocol — supplies a book's translation units (`translationUnits()`), per-unit plain source text (`sourceText(for:)`), and the `Locator → unit` resolution (`unit(containing:)` / `unit(after:)`) the bilingual prefetch trigger needs. The translation *unit* is the format's natural rendering segment, not the logical TOC chapter (plan Decision 2.7). Four concrete `Sendable` `struct` adapters: `EPUBChapterTextProvider` (spine documents, HTML-stripped via `EPUBTextExtractor`), `TXTChapterTextProvider` (`TXTChapterIndex` chapters, UTF-16 slicing), `MDChapterTextProvider` (`MDHeading`-bounded chapters), `PDFChapterTextProvider` (page ranges via PDFKit). The AZW3/MOBI `FoliateChapterTextProvider` (an `actor`, bridges the `@MainActor` Foliate coordinator via the `FoliateSectionExtracting` facade) lands in WI-11. `ChapterTranslationService` / `BookTranslationCoordinator` consume this boundary, never a format-specific extractor |
| `FoliateChapterTextProvider` (`Services/Reader/`) | `FoliateSectionExtracting` | Feature #56 WI-11 — AZW3/MOBI `ChapterTextProviding` adapter. The odd one out: an `actor` (not a `struct`) because the live Foliate seam (`FoliateSpikeView.Coordinator` + `WKWebView`) is `@MainActor`. Stores an `any FoliateSectionExtracting` and reaches it via `await`; an `actor` is `Sendable` by construction so it satisfies `ChapterTextProviding: Sendable` without `nonisolated(unsafe)`. Caches the ordered section-id list on the first `translationUnits()` call; a book reopen rebuilds the provider from scratch so the cache never goes stale within one open book |
| `FoliateSectionExtracting` (`Services/Reader/`) | `FoliateSpikeView.Coordinator` (extension) | Feature #56 WI-11 — `@MainActor protocol` bridging the live Foliate per-section text extraction seam (the `readerAPI.bilingualSectionIDs` / `readerAPI.bilingualSectionText` JS calls) into the `Sendable` `ChapterTextProviding` boundary. Class-bound + `Sendable` + `@MainActor` means a `@MainActor`-isolated `AnyObject` existential is safely `Sendable` (members are main-actor-isolated), so the `FoliateChapterTextProvider` actor can hold a single live reference without an unsafe escape hatch |
| `ChapterPrefetching` (`Services/AI/`) | `BilingualReadingViewModel` | Feature #56 WI-7b seam — `translatedSegments(for:targetLanguage:granularity:)`, the single-method translation-prefetch boundary `BilingualReadingViewModel`'s unit-aware prefetch trigger depends on. Decouples the view model from provider resolution / the disk cache / chunking; production wires a thin adapter over `ChapterTranslationService` + `AIService`, tests inject a deterministic mock |
| `ChapterTranslationPrefetcher` (`Services/AI/`) | `ChapterTranslationService` + `AIService` + `ChapterTextProviding` | Feature #56 WI-10 production `ChapterPrefetching` adapter. `Sendable` `struct` per open book. Each `translatedSegments(...)` call consults the disk cache FIRST (profile-free — Bugs #306/#342: a cached chapter renders with no/any provider), then resolves the active provider config once — a profile flip during a chapter prefetch does not split chunks across providers. Pulls per-unit source text from the injected `ChapterTextProviding` and routes the request through `ChapterTranslationService.translate(...)`. Default style is `.natural`; the re-translate picker (WI-15) is the only path that overrides it |
| `BackgroundExecutionToken` (`Services/`) | `UIApplication` (via `BackgroundTaskRequesting`) | Feature #98 grace-window handle over `beginBackgroundTask`/`endBackgroundTask` behind the `BackgroundTaskRequesting` protocol seam (production = `UIApplication`, tests = recorder). `@MainActor` class; explicit `end()` is the contract (idempotent; `deinit` only DEBUG-logs leaks); the expiration handler strongly captures a shared end-state so even a leaked token self-ends at expiry; `.invalid` (iOS denied time) degrades to a no-op. Ships with `BackgroundExpiryLatch` — a lock-backed one-way latch the `@MainActor` expiry handler sets synchronously and the whole-book job loop reads between units. Consumers: `ChapterReTranslateViewModel.submit()` (one token per re-translate) and `BookTranslationCoordinator` (token renewed per translated unit; expiry → clean between-units stop with the `.failed` phase, completed units cached as the resume checkpoint) |
| `BookTranslationCoordinator` (`Services/AI/`) | `ChapterTranslationService` + `ChapterTranslationStore` + `ChapterTextProviding` | Feature #56 WI-14 actor driving the "translate entire book" flow. App-scoped `.shared` instance (configured at `VReaderApp.init`). `start(...)` spawns a background task that iterates `ChapterTextProviding.translationUnits()`, skips units already covered in `ChapterTranslationStore.cachedUnits(...)`, hands each remaining unit to `ChapterTranslationService.translate(...)`, and emits monotonic `BookTranslationProgress` snapshots through an `AsyncStream` (`progressUpdates(forBookWithKey:)`). At most one running job per book — a second `start` for the same book is a silent no-op. `cancel(_:)` stops between units; `cancelAndPurge(_:)` additionally wipes the book's cache rows for the user-delete-book path (plan edge case (g)). Posts `.readerBookTranslationProgressDidChange` on every snapshot so a reader open on the book drives its `ReaderTranslateBanner`. Feature #98: renews a `BackgroundExecutionToken` per translated unit; on OS expiry stops cleanly BETWEEN units (`.failed` phase = the designed PAUSED rendering) and persists an `InterruptedTranslationJob` descriptor (`{v, bookKey, targetLanguage, style, providerProfileID}` in UserDefaults via `InterruptedTranslationJobStore`); `resumeInterruptedJob(bookFingerprintKey:textProvider:)` — triggered by the reader container's provider-arrival handler — re-resolves the PERSISTED profile through the `ProviderConfigResolving` seam (`AIService` conforms) and re-enters `start` (cached units skip = resume); descriptor cleared on completion / user cancel / book delete, retained on provider failure |
| `BookTranslationViewModel` (`ViewModels/`) | `BookTranslationCoordinator` | Feature #56 WI-14 `@MainActor @Observable` UI-facing state for the translate-entire-book flow. Drives the confirm alert (`presentConfirm` loads `estimate` + shows alert), the status sheet (`startObserving` subscribes to the coordinator's progress stream and mirrors snapshots into `progress`), and the cancel alert (`requestCancel` opens the confirmation, `confirmCancel` propagates to the coordinator). One per surface (Book Details, library card, reader chrome); multiple VMs for the same book observe the same coordinator job |
| `ChapterReTranslateViewModel` (`ViewModels/`) | `AIService` + `ChapterTranslationService` + `ChapterTranslationStore` | Feature #56 WI-15 `@MainActor @Observable` UI-facing state for the per-chapter re-translation flow. `presentPicker(...)` opens `ReTranslatePickerSheet` with the chosen unit + title + target language; `updateSelection(_:)` mutates the picker's `(providerProfileID, model, style, keepGlossary)` selection; `submit()` resolves the picker's `ResolvedAIProviderConfig` through the `RetranslateProviderResolving` boundary (`AIService` conforms), runs the translation through `ChapterReTranslating` (`ChapterTranslationService` conforms, with the cache READ bypassed so a fresh row can't no-op the re-translate — Bug #341 atomic swap + Bug #342 canonical key: the cache-write replaces the ONE `book|unit|lang|prompt` row in place, the original translation survives every failure/cancel path, and an override re-translation is readable by bilingual mode on reopen), and fires `onTranslationApplied` so the host posts `.readerBilingualReTranslateApplied`. Picker override never mutates `ProviderProfileStore` (acceptance criterion (f)) |
| `EPUBBilingualPipeline` (`Views/Reader/Bilingual/`) | `EPUBBilingualJS` + `EPUBBilingualOrchestrator` | Feature #56 WI-10 pure glue between the EPUB WKWebView's `bilingualEnumerate` message payload and the `BilingualReadingViewModel`'s `translationsByUnit` cache. `parseEnumeratePayload(_:)` decodes the raw `Any` body into an `EPUBBilingualEnumeratePayload` (`{requestedSectionIndex, blocks}`) — accepting BOTH the paged bare-array shape (`[{bid,text}]`, no section identity) and the continuous-scroll envelope (`{sectionIndex, blocks}`); the envelope preserves the section identity on an EMPTY result so the container clears ONLY that section's bucket instead of every bucket (Feature #71 WI-7 Gate-4 round-3 MEDIUM 1). `parseEnumerateMessage(_:)` is the flat-`[BilingualBlock]` convenience over it; `translationsByBid(blocks:translatedSegments:)` maps the VM's ordered segment array onto a `[bid: text]` lookup by position. No `@MainActor` — pure value transforms |
| `EPUBBilingualOrchestrator` (`Views/Reader/Bilingual/`) | `EPUBBilingualJS` + `EPUBBilingualPipeline` | Feature #56 WI-10 host-side `@MainActor @Observable` controller, one per open EPUB. Holds the current chapter's `[BilingualBlock]` list; emits enumerate / inject / clear JS for the bridge to evaluate. Stateless beyond the block list — the container drives transitions via `enumerateJS()` on `didFinish`, `updateBlocks(_:)` on the enumerate callback, `buildInjectJS(translatedSegments:)` when the VM's prefetch lands, and `clearJS()` on disable / chapter swap |
| `FoliateBilingualPipeline` (`Views/Reader/Bilingual/`) | `FoliateBilingualJS` + `FoliateBilingualOrchestrator` | Feature #56 WI-11 — AZW3/MOBI sibling of `EPUBBilingualPipeline`. Same two static functions (`parseEnumerateMessage(_:)`, `translationsByBid(blocks:translatedSegments:)`) with the same shapes; reuses the `BilingualBlock` value type so the enumerate → translate → inject contract is byte-identical across formats. Independent file so format-specific test invariants don't cross-contaminate |
| `FoliateBilingualOrchestrator` (`Views/Reader/Bilingual/`) | `FoliateBilingualJS` + `FoliateBilingualPipeline` | Feature #56 WI-11 — AZW3/MOBI sibling of `EPUBBilingualOrchestrator`. `@MainActor @Observable` controller, one per open AZW3/MOBI book. Owned by `FoliateBilingualContainerView`; emits enumerate / inject / clear JS that the container posts through `.foliateRequestBilingualEvalJS` for the live `FoliateSpikeView.Coordinator` to evaluate against its `WKWebView` |
| `FoliateBilingualContainerView` (`Views/Reader/`) | `FoliateSpikeView` + `FoliateBilingualOrchestrator` + `BilingualReadingViewModel` + `FoliateChapterTextProvider` | Feature #56 WI-11 — AZW3/MOBI host wrapper that adds the bilingual VM / orchestrator / setup-sheet wiring around the unchanged `FoliateSpikeView`. Owns the bilingual `@State`, the first-enable `BilingualSetupSheet`, and the notification plumbing (`.readerMoreBilingual` → toggle, `.foliateSectionLoaded` → enumerate, `.foliateBilingualBlocksEnumerated` → cache + prefetch, `.readerBilingualDidChange` → inject) that mirrors `EPUBReaderContainerView+Bilingual` for the live Foliate path |
| `BilingualDisplaySegmentMap` (`Services/Reader/`) | `BilingualTextRenderer`, `TXTReaderContainerView`, `MDReaderContainerView` | Feature #56 WI-12a pure `Sendable` value type — the TXT/MD source↔display UTF-16 offset map. Records ordered display segments tagged `.source(sourceRange:displayRange:)` or `.synthetic(displayRange:)`. `sourceOffset(forDisplayOffset:)` returns `nil` for synthetic ranges or out-of-bounds offsets; `displayOffset(forSourceOffset:)` clamps a past-end source position to display end. `identity(sourceLength:)` builds the 1:1 pass-through used when bilingual is off. WI-12b consumes the map in TXT/MD container offset-routing |
| `BilingualTextRenderer` (`Views/Reader/Bilingual/`) | `BilingualDisplaySegmentMap` | Feature #56 WI-12a pure interlinear builder for TXT/MD. `render(sourceText:sourceParagraphRanges:translatedSegments:)` returns the rendered `NSAttributedString` (source paragraphs interleaved with synthetic translation runs, each carrying the `decorationAttributeKey` attribute) plus the matching `BilingualDisplaySegmentMap`. Nil or empty translations fall back to source + identity map. Partial translations inject the prefix and leave the tail source-only (plan Decision 2's silent-source-fallback). WI-12b wires the renderer's output into the live TXT/MD UITextView |
| `BilingualParagraphRanges` (`Services/Reader/`) | `BilingualTextRenderer`, `BilingualDisplayPipeline` | Feature #56 WI-12b — pure paragraph-range scanner that splits a TXT/MD chapter's source text into UTF-16 paragraph ranges. Blank-line-separated content lines fuse into one paragraph (matches reflow conventions); blank lines + leading/trailing whitespace are excluded from ranges. Feeds the interlinear renderer's `sourceParagraphRanges` argument. Pure O(N) UTF-16 single-pass — covers CRLF / CJK / interspersed-blank-line edge cases |
| `BilingualAttributedStringComposer` (`Views/Reader/Bilingual/`) | `BilingualDisplaySegmentMap`, `BilingualTextRenderer` | Feature #56 WI-12b — typography-preserving interlinear composer. `compose(sourceAttributed:sourceParagraphRanges:translatedSegments:)` takes an already-typographed source `NSAttributedString` (font, line spacing, drop-cap, heading restyle) and interleaves synthetic translation runs at paragraph boundaries. Synthetic runs inherit the prior source paragraph's attrs + carry the `decorationAttributeKey`. Used by TXT's chapter-paged path so the chapter-start drop-cap + heading restyle survive the bilingual interleave |
| `BilingualDisplayPipeline` (`Views/Reader/Bilingual/`) | `BilingualTextRenderer`, `BilingualAttributedStringComposer`, `BilingualReadingViewModel` | Feature #56 WI-12b — `@MainActor` bridge between the bilingual VM state and the renderer/composer. `makeDisplay(...)` builds a fresh attrString from a plain `String` source; `compose(sourceAttributed:...)` preserves an upstream typographed attrString. Both off-path (no VM / disabled / no unit / no cached translation) returns the source + identity map — the byte-identical pass-through that gates the R-TXT-offsets risk |
| `BilingualOffsetRouter` (`Views/Reader/Bilingual/`) | `BilingualDisplaySegmentMap` | Feature #56 WI-12b — pure source↔display offset router for the TXT/MD container's bilingual surfaces. Helpers: `displayOffset(forSourceOffset:map:)`, `sourceOffset(forDisplayOffset:map:)`, `displayRange(forSourceRange:map:)` (segment-union projection — a source range that crosses an intervening synthetic block produces a spanning display range), `displayNSRange(forSourceNSRange:map:)`, `isSynthetic(displayOffset:map:)`. Identity-map mode is byte-identical to today's offset code |
| `BilingualTXTBridgeDelegateAdapter` (`Views/Reader/Bilingual/`) | `BilingualDisplaySegmentMap`, `TXTTextViewBridge` | Feature #56 WI-12b — `@MainActor` delegate wrapper that maps display-domain offsets the bridge reports (selection range, top-visible-char scroll offset) back to source-domain offsets via `BilingualOffsetRouter`, so the TXT VM keeps persisting positions in document source coordinates with bilingual on. A selection that starts inside a synthetic translation run is dropped; a scroll-into-synthetic projects to the end of the preceding source segment. Identity map (bilingual off) is a transparent pass-through |
| `TXTLoaderBackedChapterTextProvider` (`Services/Reader/`) | `ChapterTextProviding`, `TXTChapterContentLoader` | Feature #56 WI-12b — chapter-paged-mode `ChapterTextProviding` adapter that reads each chapter on demand via the live reader's `TXTChapterContentLoader` actor. Sibling to `TXTChapterTextProvider` (full-book-slicing). Re-enables bilingual mode for chapter-paged TXT, the mode WI-12a's `makeTextProvider` explicitly disabled because the VM's `textContent` is chapter-local in that mode |
| `PDFBilingualPanel` (`Views/Reader/Bilingual/`) | `PDFBilingualPanelState`, `BilingualLanguage`, `ReaderThemeV2` | Feature #56 WI-13 — PDF below-page bilingual translation panel. Stateless SwiftUI sub-view rendering the design's split-layout A1..A8: header (lang-glyph chip + page label + status suffix + chevron) + body switched on `PDFBilingualPanelState` (5 states: `.off` / `.loading` / `.translated([String])` / `.offline` / `.empty`). PDF is fixed-layout so the paragraph-interlinear renderer used by EPUB/Foliate/TXT/MD doesn't apply; the panel below the page is the entire user-visible bilingual surface for PDF. 260pt expanded / 38pt collapsed; attached to `PDFViewBridge` via SwiftUI's `.safeAreaInset(edge: .bottom)` so PDFKit's `autoScales` reflows the page rendering automatically |
| `PDFBilingualPanelState` (`Views/Reader/Bilingual/`) | `BilingualReadingViewModel`, `PDFChapterTextProvider` | Feature #56 WI-13 — pure synchronous derivation of the panel's 5-state matrix from the bilingual VM + the PDF's `(currentPage, pagesPerUnit, totalPages)` triple. Computes the current `TranslationUnitID` synchronously (mirrors `PDFChapterTextProvider.pageRanges` arithmetic) instead of reading the VM's async-updated `lastTriggerUnit`, so page-turn-in-flight doesn't flash stale translations (Gate-2 v5 round-1 H1). `.empty` keyed on "translated segments empty after fetch" OR "totalPages <= 0", NOT `unit == nil` (which would never fire for a real PDF — Gate-2 v5 round-1 M1) |
| `PDFReaderContainerView+Bilingual` (`Views/Reader/`) | `BilingualReadingViewModel`, `PDFChapterTextProvider`, `PDFBilingualPanel`, `PDFBilingualPanelState` | Feature #56 WI-13 — PDF host extension owning the bilingual VM lifecycle (lazy construction gated on `viewModel.isDocumentLoaded` + `totalPages > 0`), the `PDFChapterTextProvider` build, the prefetcher build (mirrors TXT/EPUB `makePrefetcher`), the first-enable setup sheet, the More-menu toggle observer, the retry observer (`.readerBilingualRetry`), and the `.safeAreaInset`-attached panel. On reopen of an already-enabled book, `ensureBilingualViewModel` kicks the initial `handlePositionChange` so the panel doesn't stick in `.loading` for the open page (Gate-4 round-1 H1). Mirrors `TXTReaderContainerView+Bilingual` / `MDReaderContainerView+Bilingual` / `EPUBReaderContainerView+Bilingual` structurally |

### 6. Data Layer (`vreader/Models/`)

SwiftData SchemaV10 entities (V9→V10 adds the additive optional `Book.sourceCanonicalKey: String?` — feature #108's converted-Kindle cross-platform identity, carried in the backup manifest; feature #109's NFC locator-key recompute runs as the launch-time `LocatorKeyBackfillMigration`, not a schema migration — see the App Layer note above):

- `Book` (fingerprintKey unique; gains `originalExtension: String?` in SchemaV5 for backup blob extension preservation; gains `fileState: String` and `blobPath: String?` in SchemaV6 for feature #47's lazy-load row state; gains `sourceCanonicalKey: String?` in SchemaV10 — feature #108's converted-Kindle source-bytes cross-platform identity, while the converted-EPUB `fingerprintKey` stays the local primary) → `ReadingPosition` (gains `vreaderLocatorData: Data?` in SchemaV8 — feature #42's engine-agnostic `VReaderLocator` envelope, stored as raw JSON `Data?` mirroring `Highlight.anchorData`; additive/optional → lightweight migration, no stage), `Highlight`, `Bookmark`, `AnnotationNote`, `BookCollection`, `ChatSession` (SchemaV9 cascade child)
# Feature #131 — Android Bilingual Interlinear Reading (parity-checklist box D)

**Feature number assumption:** highest active row in `docs/features.md` is `#130`; `#131` is the next free number. The orchestrator adjusts if a row is claimed first.

**Design authority (rule 51):** the **authoritative** bilingual surfaces are in `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx` (`BilingualSetupSheet` / `BilingualPageContent` / `BilingualPill` / `BILINGUAL_LANGS`) and `.../vreader-reader.jsx` (`ReaderTopChrome` renders `BilingualPill`; the bilingual toggle is a More-menu row via `onMoreAction`) and `.../vreader-more.jsx` (the "Bilingual mode" More-menu Row toggle). `.../vreader-ai-android.jsx` contains a SECOND, differently-shaped `BilingualSetupSheet` — see §3's setup-sheet resolution for why this plan reproduces the `vreader-bilingual.jsx` sheet and design-gates the divergence. Where a surface is NOT depicted it is scoped out and flagged.

**Status:** Gate-1 draft v2 (2026-07-11) — Gate-2 round-1 REDESIGN resolved. Awaiting Gate-2 round-2 audit.

## 1. Problem

iOS ships bilingual interlinear reading (#56/#100): a per-book toggle renders each source paragraph followed by its translation in a muted style, backed by an AI provider, cached to disk. Android shipped the #118 AI provider foundation (provider store, OpenAI-compat + Anthropic SSE clients, chat/summary) but has **no bilingual capability**. Box D of the parity checklist requires the interlinear renderer + the bilingual setup sheet, building on #118.

The engineering questions are (a) **which render host(s)** get true interlinear, and (b) **where the entry point lives**. Both were mis-analysed in v1 and are corrected here:

- **Host** — v1 claimed EPUB interlinear is "infeasible inside Readium's navigator." **That is FALSE** (§3): `EpubNavigatorFragment.evaluateJavascript(script): String?` is a public suspend method in the shipped Readium 3.3.0 AAR (verified via `javap` — see §3), so the app CAN inject and clear translation DOM nodes in Readium's WebView. EPUB is therefore the **primary** target (it is the app's main reading format). TXT/MD are still built but as a phased choice, not because EPUB requires a fork.
- **Entry point** — v1 put the toggle in the bottom chrome. **The design puts it in the More-menu + a top-chrome pill** (`vreader-more.jsx`, `vreader-reader.jsx`), which are box-F surfaces — so #131's UI *entry wiring* depends on box F (§2, §4).

## 2. Surface area

### Render-host decision (corrected — see §3 for the full analysis)

**v1 targets TWO hosts, in dependency order:**

1. **EPUB (Readium `EpubNavigatorFragment`) — PRIMARY.** Interlinear IS feasible via `evaluateJavascript` (enumerate leaf blocks → inject translation nodes → clear on teardown/reflow), exactly mirroring iOS `EPUBBilingualOrchestrator`. This is validated first by **WI-0 (a Readium bilingual spike)** before the render WI is planned in detail, because JS injection into a navigator the app does not own has real unknowns (reflow, href changes, fragment recreation, pagination interaction).
2. **TXT/MD (Compose `TxtReaderActivity`) — INCLUDED.** Trivially injectable (a translation `Text` after each source chunk in the confirmed `items(count = document.chunkCount)` loop, which already interleaves highlight + TTS spans). No WebView; deterministically Compose-testable.

**AZW3 (foliate WebView)** and **PDF** remain follow-ups / out (§"Files OUT of scope").

**Why both, not TXT/MD-only:** the honest thesis is that the *pipeline* (segment → chunk → translate → cache → interleave) is host-agnostic and fully built in v1; only the *render injection* is host-specific. EPUB is the format most users read, so shipping box D without it would under-deliver on the visible capability. TXT/MD are included because the Compose host is the cheapest, most testable place to prove the pipeline end-to-end (no WebView, deterministic tree assertions) — it de-risks the EPUB render adapter. This is not the box-B/E "one host and check the box" split; box D ships EPUB + TXT/MD together, with AZW3/PDF as tracked follow-ups. **Box D cannot be checked on the false "EPUB requires a fork" rationale** — that rationale is discarded.

### New files

**Pipeline / domain (host-agnostic, pure or coroutine — JVM-testable):**

- `bilingual/TranslationUnitId.kt` — `data class TranslationUnitId(kind, value)` with `enum Kind { epubHref, foliateHref, txtChapterIndex, mdChapterIndex, pdfPageRange }`; `storageKey = "${kind.name}:$value"`. Mirrors iOS `TranslationUnitID.Kind` (verified: same five cases). v1 uses `epubHref` + `txtChapterIndex`/`mdChapterIndex`; others reserved so the cache-key format never breaks.
- `bilingual/TranslationGranularity.kt` — `enum { paragraph, sentence }`. (Design's Granularity segment.)
- `bilingual/BilingualLanguages.kt` — `BilingualLanguage(key, glyph, script)`; `BILINGUAL_LANGS` = the set from `vreader-bilingual.jsx` (`BILINGUAL_LANGS`) + `findOrDefault(key)`. Default `Chinese`.
- `bilingual/ChapterSegmenter.kt` — `paragraphs(text)` / `sentences(text)`. Port of iOS `ChapterSegmenter.paragraphs(in:)`/`sentences(in:)` (verified exists, CJK-aware via sentence enumeration).
- `bilingual/TranslationChunker.kt` — `chunk(segments, maxCharsPerChunk)` + `subSplit(text, maxChars)`. Port of iOS `ChapterTranslationChunker.chunk(...)` + `subSplit(...)` (verified: `chunk` returns `[[Int]]` index groups, oversize segment gets its own chunk; `subSplit` is the Bug #330 grapheme-safe over-budget splitter).
- `bilingual/TranslationChunkContract.kt` — `userPrompt(segments, targetLanguage, style)`; `decode(raw, expectedCount)` (strict JSON-array + code-fence strip); `sealed class DecodeError { NotAStringArray; CountMismatch(expected, actual) }`. Port of iOS `TranslationChunkContract` (verified: same `userPrompt`/`decode` shape, same two DecodeError cases).
- `bilingual/ChapterTextProvider.kt` — `interface { units(); sourceText(unit); unitContaining(locator); unitAfter(unit) }`. Resolution key is host-specific: TXT/MD key on `charOffsetUtf16` (Android `Locator` is offset-based there); EPUB keys on the current-resource `href` from `EpubNavigatorFragment.currentLocator`. Honest divergence from iOS's uniform Readium `Locator`, documented.
- `bilingual/TxtChapterTextProvider.kt` — provider over `TxtDocument` + chapter model. MD source = raw markdown chapter (translation renders as plain muted text, not re-markdown-rendered — matches the muted-secondary design line).
- `bilingual/EpubChapterTextProvider.kt` (WI-0-gated shape) — provider over the Readium `Publication` reading order; `units()` = spine hrefs, `unitContaining(locator)` = the locator's href. Its render-side collaborator (the JS enumerate/inject adapter) is defined by WI-0's findings, not pre-committed here.
- `bilingual/ChapterTranslationError.kt` — `sealed { Offline; TimedOut; ProviderFailed(msg); Cancelled }`. Maps from `AiError` (verified cases: `Auth401`, `RateLimited429`, `Offline`, `Timeout`, `Http(code)`, `Decode`, `Stream`, `InsecureUrl`, `Config`).
- `bilingual/ChapterTranslationService.kt` — `cachedTranslation(...)` (cache-only, no provider — #306 parity: a cached chapter renders even when AI is later unconfigured); `translate(...)` (segment → chunk → per-chunk `AiClient.chat` one-shot → `decode` → per-segment fallback → graceful per-chunk degrade (Bug #330 parity: a single failed chunk renders source-only and is NOT cached; all-chunks-fail throws) → cache-write only on full success). Uses `AiClient.chat(AiRequest)` (one-shot, NOT `streamChat`). Cancellation: `ensureActive()` between chunks AND immediately before the Room write (§6).
- `bilingual/ChapterTranslationPrefetcher.kt` — resolves the active profile from one `AiProviderStore.snapshot()` (`snapshot.active`), decrypts via `store.apiKey(profile)` (snapshot-consistent), builds an `AiClient` via an **injected factory param** (see the DI correction below), cache-first then translate. Throws `ChapterTranslationError`. Mirrors iOS `ChapterTranslationPrefetcher` (verified: iOS snapshots the active profile after a cache miss and is a Sendable struct capturing its collaborators).
- `bilingual/BilingualAiReadiness.kt` — `resolve(snapshot): Boolean` (active profile exists AND its decrypted key is non-empty). A cipher/decryption failure maps to **not-ready** (never crashes — §6), not to a thrown error. Drives the setup-sheet engine-strip configured/unconfigured state. Keep the gate to exactly what #118 enforces (no separate consent manager on Android — #118 has none; confirm during build).

**State / persistence:**

- `bilingual/PerBookBilingualStore.kt` — DataStore-Preferences, keyed by `bookFingerprintKey`, holding `{ enabled, targetLanguage, granularity }`. This is the Android `PerBookSettingsOverride` bilingual slice — the backup contract declares exactly `bilingualEnabled` / `bilingualTargetLanguage` / `bilingualGranularity` (verified in `PerBookSettings.swift` and the Android `BackupSectionsExtended.kt`), and **NO `bilingualStyle`** (verified — style is not a persisted per-book field on iOS either). So this store writes exactly those three fields. Wiring into backup collect/restore is scoped OUT (§7) — additive later, fields already in the contract; until then bilingual config is device-local.
- `bilingual/BilingualViewModel.kt` — `StateFlow<BilingualUiState>` with `enabled`, `targetLanguage`, `granularity`, `needsSetupSheet`, `aiConfigured`, `translationsByUnit`, `inFlightUnits`, `unavailableUnits`, `errorUnit`. Setters + `dismissSetupSheet`, `onPositionChanged(locator)`, `retryUnit(unit)`. Generation/epoch-guarded prefetch (current + next unit), cancellation on disable / language / granularity change — port of iOS `BilingualReadingViewModel` + `+Prefetch` (verified both exist). Split to `BilingualPrefetchController.kt` if it nears ~300 lines. (No `style` field — the authoritative sheet has no Style control; see §3.)

**Room (translation cache):**

- `data/ChapterTranslationEntity.kt` — `@Entity(tableName="chapter_translations", indices=[Index("bookKey")], foreignKeys=[FK→books.fingerprintKey ON DELETE CASCADE])`. **`@PrimaryKey val lookupKey: String`** (Room REQUIRES a primary key; a "unique index without a PK" does not compile — verified against `HighlightEntity`, which pairs a `@PrimaryKey` with a separate unique index). `lookupKey` = `bookKey|unitStorageKey|targetLanguage|promptVersion` (see the cache-identity correction below). Other columns: `bookKey`, `unitStorageKey`, `targetLanguage`, `promptVersion`, `translatedJson`, `sourceParagraphCount`, `createdAt`. Mirrors iOS `ChapterTranslationRecord.lookupKey` (verified: iOS key is `book|unit|lang|prompt`, profile-agnostic — Bug #342).
- `data/ChapterTranslationDao.kt` — `getByLookupKey(key)`, `@Upsert suspend fun upsert(row)` (Upsert identifies by PK = `lookupKey`, so it is a correct insert-or-replace by the cache identity), `deleteByLookupKey(key)`. The project's Room pattern is `@PrimaryKey` + `@Upsert` (verified: `BookDao.upsert`); making `lookupKey` the PK is exactly that pattern.
- `bilingual/ChapterTranslationStore.kt` — coroutine wrapper returning a Sendable `CachedTranslation` (segments decoded from JSON), keeping Room entities off the boundary (the `AnnotationsRepository`/`HighlightRecord`/iOS `ChapterTranslationStore` precedent).

**Cache-identity correction (audit HIGH — reconciled with iOS parity):** the audit asked to add granularity + style as key columns. iOS deliberately does the opposite — `ChapterTranslationRecord.lookupKey` is `book|unit|lang|promptVersion` and is profile-AGNOSTIC / granularity-AGNOSTIC / style-agnostic (Bug #342's fix was to *remove* dimensions from the key). Style is folded into the prompt content; granularity is a read-time count-check. **Resolution honoring both the audit's concern and iOS parity:** keep the 4-part key, but make `promptVersion` an **effective composite** that encodes the result-shaping inputs, e.g. `promptVersion = "bilingual-v1|g=${granularity}|s=${style}"` (iOS uses the literal `"bilingual-v1"` today because iOS forces `.paragraph` for bilingual and pins one style; Android carries granularity/style in the promptVersion string so a change re-keys correctly). Style is not a v1 user control (the authoritative sheet has none — §3), so `s=` is a constant this version; granularity IS user-selectable, so `g=` is load-bearing (a paragraph vs sentence translation is a different cache row — this also closes the iOS #344 "sentence silently ignored" class by construction). **Additionally** (audit's cancellation half): a granularity change must cancel in-flight jobs, bump the VM generation, clear shaped in-memory `translationsByUnit`, and force a correctly-keyed re-fetch — specified in WI-6.

**DI / factory correction (audit HIGH):** the audit is right that `AiProviderFactory` is NOT a lambda — verified it is an `object` with `create(profile: AiProviderProfile, apiKey: String, dispatcher: CoroutineDispatcher = Dispatchers.IO): AiClient`. So `ChapterTranslationPrefetcher` takes its OWN injected `clientFactory: (AiProviderProfile, String) -> AiClient` param **defaulting to `AiProviderFactory::create`** (production) and overridden with a fake in tests. The prefetcher builds the exact `AiRequest(model = profile.model, messages = …, temperature = profile.temperature, maxTokens = profile.maxTokens, system = …)` from the resolved profile (verified `AiRequest` fields).

**AppContainer / navigation correction (audit HIGH — genuine gap, NOT stale state):** verified against the real code — `AppContainer` does **NOT** provide `AiProviderStore` today, and there is **NO live navigation route to `AiProviderListScreen`** (MainActivity has no NavHost; the screen + store + `AiSettingsViewModel` exist from #118 but are only exercised by instrumented/round-trip tests — #118 was VERIFIED via component tests + a live SSE socket round-trip, not an in-app nav route). There is no `#119` row. Consequences for #131:
- #131 **adds `AiProviderStore` to `AppContainer`** (lazy singleton: DataStore + `KeystoreSecretCipher`, the #116/#118 pattern) — the prefetcher + readiness need it and nothing provides it yet.
- The setup-sheet unconfigured engine strip's **"Set up" CTA target does not exist in the running app.** #131 does NOT invent an AI-provider settings screen or its navigation (that is box-F chrome / a #118 follow-on, and inventing it violates rule 51). Until a live route to `AiProviderListScreen` ships, the "Set up" affordance is **design-gated** — see §3's design-gate list. #131 can ship the bilingual sheet's *configured* path (a provider already set via the tested path) end-to-end; the *unconfigured → Set up* nav is a stated dependency, not #131 scope.

**UI (Compose — every state depicted, reproducing `vreader-bilingual.jsx`):**

- `bilingual/BilingualSetupSheet.kt` — reproduces `vreader-bilingual.jsx`'s `BilingualSetupSheet` EXACTLY: header Cancel / Translate; a **preview strip**; a **language grid** over `BILINGUAL_LANGS` (glyph tiles, selected accent); a **Granularity** segmented control (Paragraph "Translate after each ¶" / Sentence "Translate after each sentence"); a **Translation engine** strip (configured: "Claude · with this book's context" + "Change…"; unconfigured: "No AI provider configured" + "Set up"). **No Style control, no provider/model card, no term-overrides toggle, no cost footer** — those belong to the *other* (`vreader-ai-android.jsx`) sheet, which this plan does not reproduce (§3).
- `bilingual/BilingualInterlinearBody.kt` — per source chunk/paragraph: source `Text` then translation `Text` muted with accent left-border, `fontSize*0.88`, CJK font for cjk scripts, RTL handling for Arabic script. Consumes `translationsByUnit`. Loading state ("Translating chapter… N%" + per-paragraph dim — matches the design's chapter-level "38%"). Error state ("Couldn't translate" + Retry). Partial/offline (`unavailableUnits`): source-only silent fallback (design's original-always-kept guarantee — iOS Decision 2). This is the render surface for BOTH the TXT/MD Compose loop and (via the WI-0 adapter) the EPUB injection payload's Kotlin-side state.
- `bilingual/BilingualPill.kt` — the `EN ↔ 中` reader-**top-chrome** pill (per `vreader-reader.jsx` `ReaderTopChrome` + `vreader-bilingual.jsx` `BilingualPill`). Rendered by box F's top chrome; #131 provides the composable, box F wires it in (§4).

### Modified files

- `data/VReaderDatabase.kt` — add `ChapterTranslationEntity`, bump `version` (allocated version-at-slot; **v5 today** — verified, so v5→v6, but the number is set at the merge slot, not pre-assigned), add `MIGRATION_5_6` (CREATE TABLE + `bookKey` index + FK CASCADE, DDL exactly matching Room's generated schema), append `ALL_MIGRATIONS`, add `abstract fun chapterTranslationDao()`.
- `reader/TxtReaderActivity.kt` — own a `BilingualViewModel`; collect state; pass into `TxtBody`; on position change call `vm.onPositionChanged(...)`; render `BilingualInterlinearBody` output in the `items(count = document.chunkCount)` loop when bilingual is on and a translation exists (the confirmed injection point — verified it already interleaves highlight washes + TTS spans per chunk). Strictly gated to `originalFormat ∈ {txt, md}`; disabled = body byte-unchanged. **This file overlaps #129's TXT/MD WIs → gated on #129's FINAL merge (§4).**
- `reader/ReaderActivity.kt` (Readium EPUB) — WI-0-gated: attach the JS enumerate/inject adapter to `navigator.evaluateJavascript`, re-apply on href change / reflow, clear on teardown. Concrete surface defined by WI-0's spike output.
- `VReaderApp.kt` / `AppContainer` — **provide `AiProviderStore`** (new — see the AppContainer correction), `ChapterTranslationStore`, `PerBookBilingualStore`, and a `BilingualViewModel` factory. Mirrors #116/#118/#122 DI.

**NOT modified (audit HIGH — Translate slot removed):** `reader/chrome/ReaderBottomChrome.kt` gets **no** bilingual/Translate slot. v1 wrongly added `onOpenBilingual` there; the design's entry is the More-menu toggle + the top-chrome pill (box F), NOT a bottom-chrome slot. `ReaderBottomChrome`'s existing `extraSlot` (the #129/#121 read-aloud entry) is untouched.

### Files OUT of scope for v1

- **`Azw3ReaderActivity.kt` / `reader/foliate/`** — foliate WebView interlinear IS feasible (JS enumerate+inject in the pinned bundle, mirroring iOS `FoliateBilingualOrchestrator`) but deferred to a follow-up (bundle-patch JS + secure-bridge additions touching the security-sensitive #126 surface). Once WI-0 proves the EPUB JS pipeline, the foliate host reuses it with a bundle adapter.
- **`PdfReaderActivity.kt`** — no reflowable text layer. Out (the `pdfPageRange` Kind is reserved only).
- **Live AI-provider settings navigation / the "Set up" destination screen** — box-F chrome / #118 follow-on; #131 does not invent it (rule 51). Design-gated dependency (§3).
- **Backup collect/restore of `PerBookSettingsOverride` bilingual fields** — contract fields exist; wiring is a small additive follow-up (§7). Bilingual config is device-local until then.
- **"Translate entire book…" batch, re-translate/style-swap picker, cost/token estimation, term-overrides** — iOS/`vreader-ai-android.jsx` extras not in the authoritative `vreader-bilingual.jsx` sheet. Out.
- **Streaming translation progress** — the design's "38%" is chapter-level N-of-M chunk progress (from the chunker count), not token streaming. v1 shows N-of-M.

## 3. Prior art / project precedent / rejected alternatives

### The render-host decision (analysis — CORRECTED from v1)

**How iOS does interlinear:** iOS renders EPUB/AZW3 in a WKWebView it fully controls. `EPUBBilingualOrchestrator` injects JS that (1) enumerates leaf blocks (`<p>/<li>/<blockquote>`) posting `[{bid,text}]` to Swift, (2) after translation injects a translation node after each block. TXT/MD render in a `UITextView`/attributed-string path where the renderer interleaves translation runs. The mechanism = **the app inserts translation nodes between source nodes.**

**Android host-by-host injectability — the v1 verdict was WRONG for EPUB:**

| Host | Layout tree owner | Content-insertion API | Interlinear feasible? |
|---|---|---|---|
| **Readium EPUB** (`EpubNavigatorFragment`) | Readium (internal WebView) | **`evaluateJavascript(script): String?`** is PUBLIC on the fragment (shipped 3.3.0 AAR) → arbitrary DOM read/write. Plus `currentLocator` (href), `firstVisibleElementLocator`, decorations (Highlight/Underline over existing text). | **YES — via JS injection** (not just decorations) |
| **TXT/MD Compose** (`TxtReaderActivity`) | The app (`LazyColumn` over chunks) | Trivial — a translation `Text` after each source `Text` in the confirmed `items{}` loop | **YES** |
| **AZW3 foliate** (`FoliateBridge` WebView) | The app (pinned foliate-js bundle) | Full DOM control via the bridge (same as iOS) | YES, but needs bundle-JS → follow-up |

**Verification of the CRITICAL correction:** `javap -public org.readium.r2.navigator.epub.EpubNavigatorFragment` against the resolved AAR (`~/.gradle/caches/.../readium-navigator/3.3.0/.../readium-navigator-3.3.0.aar`) prints:
```
public final java.lang.Object evaluateJavascript(java.lang.String, kotlin.coroutines.Continuation<? super java.lang.String>);
public kotlinx.coroutines.flow.StateFlow<org.readium.r2.shared.publication.Locator> getCurrentLocator();
public java.lang.Object firstVisibleElementLocator(kotlin.coroutines.Continuation<...>);
```
i.e. `suspend fun evaluateJavascript(String): String?` exists. The app already holds the concrete fragment as `ReaderActivity.navigator` (it uses it for decorations/selection in #123). So EPUB interlinear via JS injection is feasible with the public API — **no Readium fork.** The v1 "infeasible inside Readium's navigator" rationale is discarded.

**Chosen: EPUB (Readium JS-injection) as the PRIMARY host + TXT/MD (Compose) included.** WI-0 spikes the EPUB path first (it has the real unknowns); the Compose host is built alongside as the deterministic pipeline proof. AZW3/PDF deferred.

**WI-0 — Readium bilingual spike (new, gates the EPUB render WI):** a throwaway harness that, against a real EPUB on the emulator, proves:
- (a) **enumerate** current-resource leaf blocks via `navigator.evaluateJavascript(enumScript)` returning a JSON `[{id,text}]` array (parse the `String?` result);
- (b) **inject** translation DOM nodes after each block, and **clear** them, via `evaluateJavascript`;
- (c) **re-apply** after `currentLocator` href changes / reflow / page-fragment recreation (the WebView pager recreates fragments — injection must survive or re-fire);
- (d) measure effects on **pagination/scroll** (does injecting content re-paginate? does it shift the reader's position?) and whether the **enumerated block count** diverges from `ChapterSegmenter` (the iOS #268 divergence class — if it diverges, adopt iOS's `translatePreSegmented` direct-block path).

If WI-0 shows injection is stable → the EPUB render WI proceeds. If WI-0 surfaces a blocker (e.g. fragment recreation wipes injected nodes with no re-fire hook) → EPUB drops to a tracked follow-up and box D ships on TXT/MD (the phasing fallback), with the honest reason (a specific spike finding), never the false "requires a fork" claim.

**Rejected alternatives:**
1. **Readium interlinear via decorations only** — REJECTED (insufficient). Decorations style existing text; they cannot insert translation paragraphs. But `evaluateJavascript` (above) makes injection possible without decorations, so EPUB is feasible — it just uses the JS seam, not the decoration seam.
2. **Forking Readium** — REJECTED + unnecessary (the public `evaluateJavascript` seam exists).
3. **AZW3 foliate host first** — REJECTED for v1 (deferred, not dead). Feasible + design-aligned, but touches the security-sensitive #126 bridge; EPUB via the same JS-injection mechanism is the higher-value primary.
4. **Eager whole-book pre-translation** — REJECTED (cost/latency). iOS lazily prefetches current+next + caches — port that.

### The setup-sheet resolution (audit HIGH — rule 51)

There are **two committed, differently-shaped** `BilingualSetupSheet`s:
- `vreader-bilingual.jsx` → **language grid + Granularity (Paragraph/Sentence) + preview strip + Translation-engine strip (Set up/Change) + Cancel/Translate** header. **No Style, no provider/model card, no term-overrides, no cost.**
- `vreader-ai-android.jsx` → **Languages (From/To) + Provider (provider/model card) + Style (Literal/Natural/Literary) + Keep-term-overrides toggle + cost footer.** **No language grid, no Granularity, no preview.**

v1 merged both into a **third layout** — a rule-51 violation (self-designed UI). **Resolution:** this plan reproduces the **`vreader-bilingual.jsx` sheet EXACTLY** as the authoritative Android-native bilingual sheet (its language grid + granularity + preview + engine strip + CTA is the coherent bilingual-config surface, and its `BilingualPill`/`BilingualPageContent` are the matching reader surfaces). **Style is dropped from v1** (it is not in the authoritative sheet, and — verified — `bilingualStyle` is not a persisted contract field on either platform). Consequently the store/VM carry no `style`, and `promptVersion`'s `s=` component is a constant (§2 cache-identity correction).

**Remaining design gate (rule 51):** a single Android sheet that offers **BOTH Style AND Granularity** (the union the `vreader-ai-android.jsx` "Style" and `vreader-bilingual.jsx` "Granularity" controls imply) is **not depicted anywhere** — no committed bundle shows both in one sheet. If style is wanted on Android as a user control, that needs an **updated committed design**. This plan does NOT invent it; it files a `needs-design` gate (see the §"Design gates" list) and ships the authoritative granularity-only sheet meanwhile.

### Other precedents applied

- **#118 provider seam**: reuse `AiProviderStore.snapshot()` (`snapshot.active`) + `store.apiKey(profile)` + `AiProviderFactory.create` (as the default of an injected factory param) + `AiClient.chat`. Prefetcher + readiness are the only new consumers; #118's AI files are unchanged; #131 additionally *wires* `AiProviderStore` into `AppContainer` (which #118 never did).
- **Room additive-migration pattern** (#122/#123/#127): version bump + `MIGRATION_n_(n+1)` + exact-DDL + `VReaderDatabaseMigrationTest` PRAGMA guard. `@PrimaryKey` + `@Upsert` is the project's DAO pattern (`BookDao`).
- **DataStore JSON-in-Preferences** for `PerBookBilingualStore` (the `ReaderSettingsStore`/`AiProviderStore` pattern).
- **Pure-logic port**: iOS `ChapterSegmenter`/`ChapterTranslationChunker`/`TranslationChunkContract` are pure + heavily unit-tested — direct Kotlin ports with the same test vectors (all verified to exist).
- **Entry point via box F**: the More-menu bilingual toggle + top-chrome pill are box-F surfaces; #131 depends on them (§4), mirroring how box B's annotations-review-sheet + bookmark "ride with item F."

## 4. Work-item sequencing

Foundational WI-1..4 (no UI, JVM-testable); a spike WI-0 (EPUB); behavioral WI-5..9. Each WI = one PR.

**Dependency notes (audit HIGH — v1's graph was wrong):**
- WI-3 depends on WI-1 (+2). WI-4 depends on WI-1+WI-3. WI-6 depends on WI-5. So WI-1..4 are NOT all independent — the graph below states the real edges.
- **`Deps: [feat:#134, feat:#132]`** (transitively #129, #118) — box F is not yet decomposed (per `docs/parity/android-checklist.md`, box F "likely splits into ≥2 features: TOC/bookmarks; find-in-book; more-menu/details/share"); **#132 = the top-chrome sub-feature, #134 = the More-menu sub-feature** are the prospective box-F IDs this plan reserves. **#131's UI entry-point WIs (the pill mount + the More-menu toggle wiring) cannot ship until box F provides those surfaces.** The pipeline + setup sheet + interlinear render (WI-0..7) are built ahead; only the entry wiring (part of WI-9) waits on box F.
- **Host-integration WIs are gated on #129's FINAL merge** — #129 owns `TxtReaderActivity`/`ReaderBottomChrome`; #131's `TxtReaderActivity` edit must land on top of #129's TXT/MD typography WIs (rule 48 one-writer-per-file).

**WI-0 (spike): Readium EPUB bilingual injection.** The harness in §3 (enumerate / inject+clear / re-apply on reflow / pagination + count-divergence measurement). Output: a go/no-go on EPUB-in-v1 + the concrete `EpubChapterTextProvider` + injection-adapter surface. Deps: none (uses the existing #106 Readium host). Not TDD-gated (throwaway spike); its findings feed WI-7b's plan.

**WI-1 (foundational): value types + pure segmentation/chunk/contract.** `TranslationUnitId`, `TranslationGranularity`, `BilingualLanguages`, `ChapterSegmenter`, `TranslationChunker`, `TranslationChunkContract`, `ChapterTranslationError`. Pure; ported iOS vectors. No Android deps. Deps: none.

**WI-2 (foundational): Room translation cache.** `ChapterTranslationEntity` (PK = `lookupKey`) + `Dao` (`@Upsert`) + `ChapterTranslationStore`; `VReaderDatabase` migration (number at slot). Robolectric migration round-trip + upsert/get/delete-by-lookupKey + FK-CASCADE + exact-DDL guard. Deps: none.

**WI-3 (foundational): `ChapterTranslationService`** against a fake `AiClient`. `cachedTranslation` (cache-only) + `translate` (per-chunk `chat`, per-segment decode-fail fallback, per-chunk graceful degrade, cancellation between chunks + before write, cache-write only on full success). Deps: **WI-1, WI-2**. Tests: cache hit → zero client calls; miss → translate + write; decode fail → per-segment fallback; one-chunk fail → source-only that chunk (others translated, NOT cached); all-chunks fail → throw; cancellation → `Cancelled` (no write); `AiError` mapping incl. `Config`/`InsecureUrl` → `ProviderFailed`.

**WI-4 (foundational): `ChapterTextProvider` (TXT/MD) + `ChapterTranslationPrefetcher` + `BilingualAiReadiness`.** Provider slices per chapter from `TxtDocument`; `unitContaining`/`unitAfter`. Prefetcher resolves active profile from `snapshot()`, decrypts snapshot-consistent, builds client via the **injected factory param** (default `AiProviderFactory::create`), constructs `AiRequest` from the profile, cache-first then translate. Readiness = active profile with non-empty decrypted key; **cipher failure → not-ready, never a crash.** Fake store + fake factory. Deps: **WI-1, WI-3**. Tests: unit resolution + clamp + empty; cache-hit-no-profile still returns (#306); no-profile miss → `ProviderFailed`; readiness true/false; cipher-throw → readiness false (no crash).

**WI-5 (behavioral): `PerBookBilingualStore` + `BilingualViewModel` state core.** Store per book (enabled/targetLanguage/granularity — no style); VM setters (persist + first-enable `needsSetupSheet`), language/granularity change clears cache-shaped state + bumps generation, the state fields. Turbine tests: first-enable raises sheet; re-enable persisted does not; disable clears; language change resets; granularity change resets + re-keys; round-trip through store. Deps: **WI-1** (+ store).

**WI-6 (behavioral): VM prefetch trigger + generation/cancellation.** `onPositionChanged` derives current unit, dedupes, prefetches current+next; a **monotonic position-request sequence** checked after every suspension; **per-unit generation tokens**; a **captured language/granularity/provider snapshot per launch**; generation bumps on disable/language/granularity/unit-change discard stale; `CancellationException` handled BEFORE generic error mapping; `Offline`→`unavailableUnits`; transient failure leaves unit unfetched + clears anchor to retry; `retryUnit`. Fake prefetcher. Deps: **WI-4, WI-5**. Tests: current+next on unit change; same-unit no-op; cancel-mid discards stale; offline→unavailable; failure→retry-able; `retryUnit` re-fetches; granularity change cancels + re-fetches under the new key.

**WI-7a (behavioral): Compose UI — setup sheet + interlinear body + pill.** Reproduce `vreader-bilingual.jsx` (setup sheet: language grid / granularity / preview / engine strip configured+unconfigured; body: translated / loading N%+dimmed / error+Retry / offline source-only; pill). Light+dark. Compose UI tests each state. Deps: **WI-5** (state shape). NO Style control; the unconfigured "Set up" CTA renders but its nav target is design-gated (§3).

**WI-7b (behavioral): EPUB render adapter** (only if WI-0 = go). The JS enumerate/inject adapter + `EpubChapterTextProvider`, wired into `ReaderActivity`, driving `BilingualInterlinearBody` state from injected content. Deps: **WI-0, WI-3, WI-4, WI-7a**. Connected test on a real EPUB (seeded cache): enable → interlinear injects; disable → nodes cleared; reflow/href-change re-applies. (If WI-0 = no-go, this WI is dropped and box D ships TXT/MD-only, tracked.)

**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into `TxtBody` loop + position-change + setup-sheet + DI (incl. adding `AiProviderStore` to `AppContainer`). `originalFormat`-gated (TXT/MD). **Gated on #129's final merge.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; disable → source-only byte-parity; reopen persists enabled + renders from cache with zero client calls. Deps: **WI-6, WI-7a, #129 final**.

**WI-9 (behavioral): entry wiring + acceptance.** Mount `BilingualPill` in box F's top chrome; wire the More-menu bilingual toggle (box F) to the VM. **Gated on `feat:#132` (top chrome) + `feat:#134` (More menu).** Full acceptance pass across EPUB (if WI-7b landed) + TXT/MD. Flip box D note; update `docs/architecture.md` (bilingual pipeline + the new `chapter_translations` schema + `AiProviderStore` now in `AppContainer`). → DONE. Deps: **WI-8, WI-7b (if go), feat:#132, feat:#134**.

## 5. Test catalogue

JVM/Robolectric (`android/app/src/test/...bilingual/`): `ChapterSegmenterTest` (paragraph blank-line; sentence CJK 。！？ vs Latin; empty→[]; single); `TranslationChunkerTest` (packs to budget; oversize→own chunk+subSplit; empty→[]); `TranslationChunkContractTest` (prompt per style-constant; strict JSON decode; code-fence strip; count mismatch→`CountMismatch`; non-array→`NotAStringArray`); `ChapterTranslationServiceTest` (cache hit 0 calls; miss→translate→write; decode-fail per-segment fallback; one-chunk-fail partial-not-cached; all-fail→throw; cancellation→Cancelled no write; ensureActive-before-write; offline/timeout/429/http/config/insecure→error mapping; very long chapter N-of-M; stale-cache count-mismatch re-translates); `ChapterTranslationErrorMappingTest`; `TxtChapterTextProviderTest` (resolution; clamp-past-end; empty; unitAfter end→null); `ChapterTranslationPrefetcherTest` (snapshot-consistent profile+key; injected-factory used; `AiRequest` built from profile; cache-hit-no-profile #306; no-profile miss→ProviderFailed; CJK↔English + Latin round-trip via fake; cipher-throw→ProviderFailed not crash); `BilingualAiReadinessTest` (active+key→true; no active→false; empty key→false; **cipher-throw→false, no crash**); `PerBookBilingualStoreTest` (enabled/lang/granularity round-trip; no style field); `BilingualViewModelTest` (Turbine: first-enable sheet; re-enable no-sheet; disable clears; language reset; **granularity reset + re-key**; prefetch current+next; same-unit no-op; cancel-mid discards; offline→unavailable; error→errorUnit+retry; `retryUnit`; generation bump on style-N/A—granularity change).

Room migration: `VReaderDatabaseMigrationTest` (extend) vPrev→vNext + full-chain + FK-CASCADE + `lookupKey`-as-PK; `ChapterTranslationDaoTest` (upsert-by-PK replaces; get/delete-by-lookupKey).

Compose UI (`androidTest/...bilingual/`): `BilingualSetupSheetUiTest` (language grid, granularity, preview, engine configured vs unconfigured; **no Style control present**; light+dark); `BilingualInterlinearBodyUiTest` (translated incl. CJK font + RTL Arabic; loading N%+dimmed; error+Retry; offline source-only; empty translation→source-only no crash); `BilingualPillUiTest`.

Connected (`androidTest/...reader/`): `TxtReaderBilingualConnectedTest` (API 35, fake `AiClient` via injected factory): enable→setup→confirm→interlinear from seeded Room cache; disable→source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; TXT/MD gated (PDF inert); very long chapter scroll responsive; cancellation leaves no partial cache row. `EpubReaderBilingualConnectedTest` (only if WI-0=go): enable→inject on a real EPUB; disable→clear; href-change→re-apply; count-divergence handled.

Edge cases: empty translation, failed, partial per-chunk, CJK↔English + Latin + RTL, provider error/timeout/429/config/insecure, cancellation mid-translation + before-write, very long chapters, offline (cache-first + silent source-only), cipher-decrypt failure → not-ready (no crash).

## 6. Risks + mitigations

- **Live-translation verification is AI-credential-gated (the box-D caveat).** The whole pipeline is verified without live creds via a deterministic **fake `AiClient`** injected through the prefetcher's `clientFactory` param (default `AiProviderFactory::create`; tests override). WI-3/4/8 prove segment→chunk→decode→cache→interleave end-to-end incl. every error/edge path. The connected test seeds the Room cache directly and asserts render-from-cache with zero client calls (render path proven offline). **This mock/integration path is the box-D-required verification path** (the checklist states live translation is credential-gated); an optional live smoke confirms wire format but is NOT a gate.
- **Acceptance proves BOTH cache-render AND the live pipeline path (via the fake).** WI-8's connected test drives the full enable→translate(fake)→cache→render→reopen cycle, not just cache rendering — the fake stands in only for the network leaf.
- **EPUB JS-injection unknowns.** WI-0 de-risks before the render WI: pagination shift, fragment recreation wiping nodes, enumerate-vs-`ChapterSegmenter` count divergence (iOS #268). If a hard blocker appears, EPUB drops to a tracked follow-up (phasing fallback) with the specific spike reason — never the false "requires a fork."
- **Concurrency (audit HIGH — was under-specified).** WI-6 adds: a monotonic position-request sequence checked after every suspension; per-unit generation tokens; a captured language/granularity/provider snapshot per launch; cancellation on granularity change; `CancellationException` handled BEFORE generic error mapping; `ensureActive()` immediately before the Room write; cipher/decrypt failures mapped to unconfigured/provider-failure (never a crash). Snapshot-consistent profile+key pairing (from one `snapshot()`) is preserved.
- **Segment↔render count divergence** (iOS Bugs #268/#330/#344). TXT/MD segment through the SAME `ChapterSegmenter` on translate + render sides, so 1:1 pairing holds by construction; granularity is in the cache key so a paragraph row is never read as sentences. EPUB uses WI-0's finding (direct-block path if enumerate diverges — iOS `translatePreSegmented` parity).
- **Cost/latency of translating on scroll.** Lazy current+next prefetch + disk cache; N-of-M progress; cancellation on navigate-away/generation-bump.
- **Provider JSON non-compliance.** `TranslationChunkContract.decode` + per-segment fallback (iOS parity) — never drops a paragraph.
- **DataStore per-book key growth.** One Preferences entry per book keyed by fingerprint; scales like `ReaderSettingsStore`/`AiProviderStore`.

## 7. Backward compat

- **Room migration additive** (new `chapter_translations`, FK CASCADE, `lookupKey` PK). Existing rows untouched; migration + structural test guard it. Version number allocated at the merge slot (v5 today → v6).
- **Reader unchanged when bilingual off** — `TxtBody` render loop byte-identical unless `enabled && format∈{txt,md} && translation present`. `ReaderBottomChrome` is **not modified** (v1's Translate slot removed), so #129's chrome is unaffected. EPUB render adapter is inert unless bilingual is on.
- **#118 AI provider files unchanged** — the prefetcher/readiness are new consumers; the only #118-adjacent change is *wiring* `AiProviderStore` into `AppContainer` (which #118 left unwired — it was component/round-trip-verified, not nav-integrated).
- **Backup contract already compatible** — `PerBookSettingsOverride.bilingualEnabled/TargetLanguage/Granularity` exist (verified; **no `bilingualStyle`**), and there is **no translation-cache section** in `contracts/vectors/backup-sections.json` (verified — the cache is device-local, re-derivable). v1 introduces the store that writes the three fields locally; backup collect/restore of them is a small additive follow-up (no contract change), out of v1 scope; until then bilingual config is device-local (safe default). The `PerBookBilingualStore` is confirmed device-local; backup-collect/restore is the scoped-out follow-up.

## Design gates (rule 51 — for `needs-design` filing)

1. **"Bilingual mode" setup sheet with BOTH Style AND Granularity in one Android sheet** — `vreader-bilingual.jsx` depicts Granularity (no Style); `vreader-ai-android.jsx` depicts Style (no Granularity); no committed bundle shows both together. v1 reproduces the granularity-only `vreader-bilingual.jsx` sheet and DROPS Style. If Style is wanted as an Android user control, file `Design needed: bilingual setup sheet (Style + Granularity) for feature #131`. **This is the one open design gate for #131.**
2. **Dependency gate (not a #131 design gate, but blocks the "Set up" affordance)** — the setup sheet's unconfigured "Set up" CTA has no live nav destination (`AiProviderListScreen` is unreachable in-app today; no `#119`). #131 does not invent it (box-F chrome / #118 follow-on); the CTA renders but is wired only once that route ships.

## Revision history

- v1 (2026-07-10): Gate-1 draft (Plan agent). Gate-2 Codex audit pending.
- v2 (2026-07-11): Gate-2 round-1 REDESIGN resolved — Readium-feasibility corrected, entry-point rebased on box F, setup-sheet design-gated, DI/cache/concurrency fixed.

codex
The worktree is clean for tracked files, with unrelated untracked files already present; I will not touch them. The combined read was truncated, so I’m rereading the 217-line plan in bounded chunks and then mapping its claims to the live Android implementation.
exec
/bin/zsh -lc "sed -n '1,120p' dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md && sed -n '121,240p' dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md && rg -n \"Android|EpubNavigatorFragment|ReaderActivity|AiProviderStore|ChapterSegmenter|chapter_translations|VReaderDatabase\" docs/architecture.md" in /Users/ll/workspace/vreader
 succeeded in 0ms:
# Feature #131 — Android Bilingual Interlinear Reading (parity-checklist box D)

**Feature number assumption:** highest active row in `docs/features.md` is `#130`; `#131` is the next free number. The orchestrator adjusts if a row is claimed first.

**Design authority (rule 51):** the **authoritative** bilingual surfaces are in `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx` (`BilingualSetupSheet` / `BilingualPageContent` / `BilingualPill` / `BILINGUAL_LANGS`) and `.../vreader-reader.jsx` (`ReaderTopChrome` renders `BilingualPill`; the bilingual toggle is a More-menu row via `onMoreAction`) and `.../vreader-more.jsx` (the "Bilingual mode" More-menu Row toggle). `.../vreader-ai-android.jsx` contains a SECOND, differently-shaped `BilingualSetupSheet` — see §3's setup-sheet resolution for why this plan reproduces the `vreader-bilingual.jsx` sheet and design-gates the divergence. Where a surface is NOT depicted it is scoped out and flagged.

**Status:** Gate-1 draft v2 (2026-07-11) — Gate-2 round-1 REDESIGN resolved. Awaiting Gate-2 round-2 audit.

## 1. Problem

iOS ships bilingual interlinear reading (#56/#100): a per-book toggle renders each source paragraph followed by its translation in a muted style, backed by an AI provider, cached to disk. Android shipped the #118 AI provider foundation (provider store, OpenAI-compat + Anthropic SSE clients, chat/summary) but has **no bilingual capability**. Box D of the parity checklist requires the interlinear renderer + the bilingual setup sheet, building on #118.

The engineering questions are (a) **which render host(s)** get true interlinear, and (b) **where the entry point lives**. Both were mis-analysed in v1 and are corrected here:

- **Host** — v1 claimed EPUB interlinear is "infeasible inside Readium's navigator." **That is FALSE** (§3): `EpubNavigatorFragment.evaluateJavascript(script): String?` is a public suspend method in the shipped Readium 3.3.0 AAR (verified via `javap` — see §3), so the app CAN inject and clear translation DOM nodes in Readium's WebView. EPUB is therefore the **primary** target (it is the app's main reading format). TXT/MD are still built but as a phased choice, not because EPUB requires a fork.
- **Entry point** — v1 put the toggle in the bottom chrome. **The design puts it in the More-menu + a top-chrome pill** (`vreader-more.jsx`, `vreader-reader.jsx`), which are box-F surfaces — so #131's UI *entry wiring* depends on box F (§2, §4).

## 2. Surface area

### Render-host decision (corrected — see §3 for the full analysis)

**v1 targets TWO hosts, in dependency order:**

1. **EPUB (Readium `EpubNavigatorFragment`) — PRIMARY.** Interlinear IS feasible via `evaluateJavascript` (enumerate leaf blocks → inject translation nodes → clear on teardown/reflow), exactly mirroring iOS `EPUBBilingualOrchestrator`. This is validated first by **WI-0 (a Readium bilingual spike)** before the render WI is planned in detail, because JS injection into a navigator the app does not own has real unknowns (reflow, href changes, fragment recreation, pagination interaction).
2. **TXT/MD (Compose `TxtReaderActivity`) — INCLUDED.** Trivially injectable (a translation `Text` after each source chunk in the confirmed `items(count = document.chunkCount)` loop, which already interleaves highlight + TTS spans). No WebView; deterministically Compose-testable.

**AZW3 (foliate WebView)** and **PDF** remain follow-ups / out (§"Files OUT of scope").

**Why both, not TXT/MD-only:** the honest thesis is that the *pipeline* (segment → chunk → translate → cache → interleave) is host-agnostic and fully built in v1; only the *render injection* is host-specific. EPUB is the format most users read, so shipping box D without it would under-deliver on the visible capability. TXT/MD are included because the Compose host is the cheapest, most testable place to prove the pipeline end-to-end (no WebView, deterministic tree assertions) — it de-risks the EPUB render adapter. This is not the box-B/E "one host and check the box" split; box D ships EPUB + TXT/MD together, with AZW3/PDF as tracked follow-ups. **Box D cannot be checked on the false "EPUB requires a fork" rationale** — that rationale is discarded.

### New files

**Pipeline / domain (host-agnostic, pure or coroutine — JVM-testable):**

- `bilingual/TranslationUnitId.kt` — `data class TranslationUnitId(kind, value)` with `enum Kind { epubHref, foliateHref, txtChapterIndex, mdChapterIndex, pdfPageRange }`; `storageKey = "${kind.name}:$value"`. Mirrors iOS `TranslationUnitID.Kind` (verified: same five cases). v1 uses `epubHref` + `txtChapterIndex`/`mdChapterIndex`; others reserved so the cache-key format never breaks.
- `bilingual/TranslationGranularity.kt` — `enum { paragraph, sentence }`. (Design's Granularity segment.)
- `bilingual/BilingualLanguages.kt` — `BilingualLanguage(key, glyph, script)`; `BILINGUAL_LANGS` = the set from `vreader-bilingual.jsx` (`BILINGUAL_LANGS`) + `findOrDefault(key)`. Default `Chinese`.
- `bilingual/ChapterSegmenter.kt` — `paragraphs(text)` / `sentences(text)`. Port of iOS `ChapterSegmenter.paragraphs(in:)`/`sentences(in:)` (verified exists, CJK-aware via sentence enumeration).
- `bilingual/TranslationChunker.kt` — `chunk(segments, maxCharsPerChunk)` + `subSplit(text, maxChars)`. Port of iOS `ChapterTranslationChunker.chunk(...)` + `subSplit(...)` (verified: `chunk` returns `[[Int]]` index groups, oversize segment gets its own chunk; `subSplit` is the Bug #330 grapheme-safe over-budget splitter).
- `bilingual/TranslationChunkContract.kt` — `userPrompt(segments, targetLanguage, style)`; `decode(raw, expectedCount)` (strict JSON-array + code-fence strip); `sealed class DecodeError { NotAStringArray; CountMismatch(expected, actual) }`. Port of iOS `TranslationChunkContract` (verified: same `userPrompt`/`decode` shape, same two DecodeError cases).
- `bilingual/ChapterTextProvider.kt` — `interface { units(); sourceText(unit); unitContaining(locator); unitAfter(unit) }`. Resolution key is host-specific: TXT/MD key on `charOffsetUtf16` (Android `Locator` is offset-based there); EPUB keys on the current-resource `href` from `EpubNavigatorFragment.currentLocator`. Honest divergence from iOS's uniform Readium `Locator`, documented.
- `bilingual/TxtChapterTextProvider.kt` — provider over `TxtDocument` + chapter model. MD source = raw markdown chapter (translation renders as plain muted text, not re-markdown-rendered — matches the muted-secondary design line).
- `bilingual/EpubChapterTextProvider.kt` (WI-0-gated shape) — provider over the Readium `Publication` reading order; `units()` = spine hrefs, `unitContaining(locator)` = the locator's href. Its render-side collaborator (the JS enumerate/inject adapter) is defined by WI-0's findings, not pre-committed here.
- `bilingual/ChapterTranslationError.kt` — `sealed { Offline; TimedOut; ProviderFailed(msg); Cancelled }`. Maps from `AiError` (verified cases: `Auth401`, `RateLimited429`, `Offline`, `Timeout`, `Http(code)`, `Decode`, `Stream`, `InsecureUrl`, `Config`).
- `bilingual/ChapterTranslationService.kt` — `cachedTranslation(...)` (cache-only, no provider — #306 parity: a cached chapter renders even when AI is later unconfigured); `translate(...)` (segment → chunk → per-chunk `AiClient.chat` one-shot → `decode` → per-segment fallback → graceful per-chunk degrade (Bug #330 parity: a single failed chunk renders source-only and is NOT cached; all-chunks-fail throws) → cache-write only on full success). Uses `AiClient.chat(AiRequest)` (one-shot, NOT `streamChat`). Cancellation: `ensureActive()` between chunks AND immediately before the Room write (§6).
- `bilingual/ChapterTranslationPrefetcher.kt` — resolves the active profile from one `AiProviderStore.snapshot()` (`snapshot.active`), decrypts via `store.apiKey(profile)` (snapshot-consistent), builds an `AiClient` via an **injected factory param** (see the DI correction below), cache-first then translate. Throws `ChapterTranslationError`. Mirrors iOS `ChapterTranslationPrefetcher` (verified: iOS snapshots the active profile after a cache miss and is a Sendable struct capturing its collaborators).
- `bilingual/BilingualAiReadiness.kt` — `resolve(snapshot): Boolean` (active profile exists AND its decrypted key is non-empty). A cipher/decryption failure maps to **not-ready** (never crashes — §6), not to a thrown error. Drives the setup-sheet engine-strip configured/unconfigured state. Keep the gate to exactly what #118 enforces (no separate consent manager on Android — #118 has none; confirm during build).

**State / persistence:**

- `bilingual/PerBookBilingualStore.kt` — DataStore-Preferences, keyed by `bookFingerprintKey`, holding `{ enabled, targetLanguage, granularity }`. This is the Android `PerBookSettingsOverride` bilingual slice — the backup contract declares exactly `bilingualEnabled` / `bilingualTargetLanguage` / `bilingualGranularity` (verified in `PerBookSettings.swift` and the Android `BackupSectionsExtended.kt`), and **NO `bilingualStyle`** (verified — style is not a persisted per-book field on iOS either). So this store writes exactly those three fields. Wiring into backup collect/restore is scoped OUT (§7) — additive later, fields already in the contract; until then bilingual config is device-local.
- `bilingual/BilingualViewModel.kt` — `StateFlow<BilingualUiState>` with `enabled`, `targetLanguage`, `granularity`, `needsSetupSheet`, `aiConfigured`, `translationsByUnit`, `inFlightUnits`, `unavailableUnits`, `errorUnit`. Setters + `dismissSetupSheet`, `onPositionChanged(locator)`, `retryUnit(unit)`. Generation/epoch-guarded prefetch (current + next unit), cancellation on disable / language / granularity change — port of iOS `BilingualReadingViewModel` + `+Prefetch` (verified both exist). Split to `BilingualPrefetchController.kt` if it nears ~300 lines. (No `style` field — the authoritative sheet has no Style control; see §3.)

**Room (translation cache):**

- `data/ChapterTranslationEntity.kt` — `@Entity(tableName="chapter_translations", indices=[Index("bookKey")], foreignKeys=[FK→books.fingerprintKey ON DELETE CASCADE])`. **`@PrimaryKey val lookupKey: String`** (Room REQUIRES a primary key; a "unique index without a PK" does not compile — verified against `HighlightEntity`, which pairs a `@PrimaryKey` with a separate unique index). `lookupKey` = `bookKey|unitStorageKey|targetLanguage|promptVersion` (see the cache-identity correction below). Other columns: `bookKey`, `unitStorageKey`, `targetLanguage`, `promptVersion`, `translatedJson`, `sourceParagraphCount`, `createdAt`. Mirrors iOS `ChapterTranslationRecord.lookupKey` (verified: iOS key is `book|unit|lang|prompt`, profile-agnostic — Bug #342).
- `data/ChapterTranslationDao.kt` — `getByLookupKey(key)`, `@Upsert suspend fun upsert(row)` (Upsert identifies by PK = `lookupKey`, so it is a correct insert-or-replace by the cache identity), `deleteByLookupKey(key)`. The project's Room pattern is `@PrimaryKey` + `@Upsert` (verified: `BookDao.upsert`); making `lookupKey` the PK is exactly that pattern.
- `bilingual/ChapterTranslationStore.kt` — coroutine wrapper returning a Sendable `CachedTranslation` (segments decoded from JSON), keeping Room entities off the boundary (the `AnnotationsRepository`/`HighlightRecord`/iOS `ChapterTranslationStore` precedent).

**Cache-identity correction (audit HIGH — reconciled with iOS parity):** the audit asked to add granularity + style as key columns. iOS deliberately does the opposite — `ChapterTranslationRecord.lookupKey` is `book|unit|lang|promptVersion` and is profile-AGNOSTIC / granularity-AGNOSTIC / style-agnostic (Bug #342's fix was to *remove* dimensions from the key). Style is folded into the prompt content; granularity is a read-time count-check. **Resolution honoring both the audit's concern and iOS parity:** keep the 4-part key, but make `promptVersion` an **effective composite** that encodes the result-shaping inputs, e.g. `promptVersion = "bilingual-v1|g=${granularity}|s=${style}"` (iOS uses the literal `"bilingual-v1"` today because iOS forces `.paragraph` for bilingual and pins one style; Android carries granularity/style in the promptVersion string so a change re-keys correctly). Style is not a v1 user control (the authoritative sheet has none — §3), so `s=` is a constant this version; granularity IS user-selectable, so `g=` is load-bearing (a paragraph vs sentence translation is a different cache row — this also closes the iOS #344 "sentence silently ignored" class by construction). **Additionally** (audit's cancellation half): a granularity change must cancel in-flight jobs, bump the VM generation, clear shaped in-memory `translationsByUnit`, and force a correctly-keyed re-fetch — specified in WI-6.

**DI / factory correction (audit HIGH):** the audit is right that `AiProviderFactory` is NOT a lambda — verified it is an `object` with `create(profile: AiProviderProfile, apiKey: String, dispatcher: CoroutineDispatcher = Dispatchers.IO): AiClient`. So `ChapterTranslationPrefetcher` takes its OWN injected `clientFactory: (AiProviderProfile, String) -> AiClient` param **defaulting to `AiProviderFactory::create`** (production) and overridden with a fake in tests. The prefetcher builds the exact `AiRequest(model = profile.model, messages = …, temperature = profile.temperature, maxTokens = profile.maxTokens, system = …)` from the resolved profile (verified `AiRequest` fields).

**AppContainer / navigation correction (audit HIGH — genuine gap, NOT stale state):** verified against the real code — `AppContainer` does **NOT** provide `AiProviderStore` today, and there is **NO live navigation route to `AiProviderListScreen`** (MainActivity has no NavHost; the screen + store + `AiSettingsViewModel` exist from #118 but are only exercised by instrumented/round-trip tests — #118 was VERIFIED via component tests + a live SSE socket round-trip, not an in-app nav route). There is no `#119` row. Consequences for #131:
- #131 **adds `AiProviderStore` to `AppContainer`** (lazy singleton: DataStore + `KeystoreSecretCipher`, the #116/#118 pattern) — the prefetcher + readiness need it and nothing provides it yet.
- The setup-sheet unconfigured engine strip's **"Set up" CTA target does not exist in the running app.** #131 does NOT invent an AI-provider settings screen or its navigation (that is box-F chrome / a #118 follow-on, and inventing it violates rule 51). Until a live route to `AiProviderListScreen` ships, the "Set up" affordance is **design-gated** — see §3's design-gate list. #131 can ship the bilingual sheet's *configured* path (a provider already set via the tested path) end-to-end; the *unconfigured → Set up* nav is a stated dependency, not #131 scope.

**UI (Compose — every state depicted, reproducing `vreader-bilingual.jsx`):**

- `bilingual/BilingualSetupSheet.kt` — reproduces `vreader-bilingual.jsx`'s `BilingualSetupSheet` EXACTLY: header Cancel / Translate; a **preview strip**; a **language grid** over `BILINGUAL_LANGS` (glyph tiles, selected accent); a **Granularity** segmented control (Paragraph "Translate after each ¶" / Sentence "Translate after each sentence"); a **Translation engine** strip (configured: "Claude · with this book's context" + "Change…"; unconfigured: "No AI provider configured" + "Set up"). **No Style control, no provider/model card, no term-overrides toggle, no cost footer** — those belong to the *other* (`vreader-ai-android.jsx`) sheet, which this plan does not reproduce (§3).
- `bilingual/BilingualInterlinearBody.kt` — per source chunk/paragraph: source `Text` then translation `Text` muted with accent left-border, `fontSize*0.88`, CJK font for cjk scripts, RTL handling for Arabic script. Consumes `translationsByUnit`. Loading state ("Translating chapter… N%" + per-paragraph dim — matches the design's chapter-level "38%"). Error state ("Couldn't translate" + Retry). Partial/offline (`unavailableUnits`): source-only silent fallback (design's original-always-kept guarantee — iOS Decision 2). This is the render surface for BOTH the TXT/MD Compose loop and (via the WI-0 adapter) the EPUB injection payload's Kotlin-side state.
- `bilingual/BilingualPill.kt` — the `EN ↔ 中` reader-**top-chrome** pill (per `vreader-reader.jsx` `ReaderTopChrome` + `vreader-bilingual.jsx` `BilingualPill`). Rendered by box F's top chrome; #131 provides the composable, box F wires it in (§4).

### Modified files

- `data/VReaderDatabase.kt` — add `ChapterTranslationEntity`, bump `version` (allocated version-at-slot; **v5 today** — verified, so v5→v6, but the number is set at the merge slot, not pre-assigned), add `MIGRATION_5_6` (CREATE TABLE + `bookKey` index + FK CASCADE, DDL exactly matching Room's generated schema), append `ALL_MIGRATIONS`, add `abstract fun chapterTranslationDao()`.
- `reader/TxtReaderActivity.kt` — own a `BilingualViewModel`; collect state; pass into `TxtBody`; on position change call `vm.onPositionChanged(...)`; render `BilingualInterlinearBody` output in the `items(count = document.chunkCount)` loop when bilingual is on and a translation exists (the confirmed injection point — verified it already interleaves highlight washes + TTS spans per chunk). Strictly gated to `originalFormat ∈ {txt, md}`; disabled = body byte-unchanged. **This file overlaps #129's TXT/MD WIs → gated on #129's FINAL merge (§4).**
- `reader/ReaderActivity.kt` (Readium EPUB) — WI-0-gated: attach the JS enumerate/inject adapter to `navigator.evaluateJavascript`, re-apply on href change / reflow, clear on teardown. Concrete surface defined by WI-0's spike output.
- `VReaderApp.kt` / `AppContainer` — **provide `AiProviderStore`** (new — see the AppContainer correction), `ChapterTranslationStore`, `PerBookBilingualStore`, and a `BilingualViewModel` factory. Mirrors #116/#118/#122 DI.

**NOT modified (audit HIGH — Translate slot removed):** `reader/chrome/ReaderBottomChrome.kt` gets **no** bilingual/Translate slot. v1 wrongly added `onOpenBilingual` there; the design's entry is the More-menu toggle + the top-chrome pill (box F), NOT a bottom-chrome slot. `ReaderBottomChrome`'s existing `extraSlot` (the #129/#121 read-aloud entry) is untouched.

### Files OUT of scope for v1

- **`Azw3ReaderActivity.kt` / `reader/foliate/`** — foliate WebView interlinear IS feasible (JS enumerate+inject in the pinned bundle, mirroring iOS `FoliateBilingualOrchestrator`) but deferred to a follow-up (bundle-patch JS + secure-bridge additions touching the security-sensitive #126 surface). Once WI-0 proves the EPUB JS pipeline, the foliate host reuses it with a bundle adapter.
- **`PdfReaderActivity.kt`** — no reflowable text layer. Out (the `pdfPageRange` Kind is reserved only).
- **Live AI-provider settings navigation / the "Set up" destination screen** — box-F chrome / #118 follow-on; #131 does not invent it (rule 51). Design-gated dependency (§3).
- **Backup collect/restore of `PerBookSettingsOverride` bilingual fields** — contract fields exist; wiring is a small additive follow-up (§7). Bilingual config is device-local until then.
- **"Translate entire book…" batch, re-translate/style-swap picker, cost/token estimation, term-overrides** — iOS/`vreader-ai-android.jsx` extras not in the authoritative `vreader-bilingual.jsx` sheet. Out.
- **Streaming translation progress** — the design's "38%" is chapter-level N-of-M chunk progress (from the chunker count), not token streaming. v1 shows N-of-M.

## 3. Prior art / project precedent / rejected alternatives

### The render-host decision (analysis — CORRECTED from v1)

**How iOS does interlinear:** iOS renders EPUB/AZW3 in a WKWebView it fully controls. `EPUBBilingualOrchestrator` injects JS that (1) enumerates leaf blocks (`<p>/<li>/<blockquote>`) posting `[{bid,text}]` to Swift, (2) after translation injects a translation node after each block. TXT/MD render in a `UITextView`/attributed-string path where the renderer interleaves translation runs. The mechanism = **the app inserts translation nodes between source nodes.**

**Android host-by-host injectability — the v1 verdict was WRONG for EPUB:**

| Host | Layout tree owner | Content-insertion API | Interlinear feasible? |
|---|---|---|---|
| **Readium EPUB** (`EpubNavigatorFragment`) | Readium (internal WebView) | **`evaluateJavascript(script): String?`** is PUBLIC on the fragment (shipped 3.3.0 AAR) → arbitrary DOM read/write. Plus `currentLocator` (href), `firstVisibleElementLocator`, decorations (Highlight/Underline over existing text). | **YES — via JS injection** (not just decorations) |
| **TXT/MD Compose** (`TxtReaderActivity`) | The app (`LazyColumn` over chunks) | Trivial — a translation `Text` after each source `Text` in the confirmed `items{}` loop | **YES** |
| **AZW3 foliate** (`FoliateBridge` WebView) | The app (pinned foliate-js bundle) | Full DOM control via the bridge (same as iOS) | YES, but needs bundle-JS → follow-up |

**Verification of the CRITICAL correction:** `javap -public org.readium.r2.navigator.epub.EpubNavigatorFragment` against the resolved AAR (`~/.gradle/caches/.../readium-navigator/3.3.0/.../readium-navigator-3.3.0.aar`) prints:
```
public final java.lang.Object evaluateJavascript(java.lang.String, kotlin.coroutines.Continuation<? super java.lang.String>);
public kotlinx.coroutines.flow.StateFlow<org.readium.r2.shared.publication.Locator> getCurrentLocator();
public java.lang.Object firstVisibleElementLocator(kotlin.coroutines.Continuation<...>);
```
i.e. `suspend fun evaluateJavascript(String): String?` exists. The app already holds the concrete fragment as `ReaderActivity.navigator` (it uses it for decorations/selection in #123). So EPUB interlinear via JS injection is feasible with the public API — **no Readium fork.** The v1 "infeasible inside Readium's navigator" rationale is discarded.

**Chosen: EPUB (Readium JS-injection) as the PRIMARY host + TXT/MD (Compose) included.** WI-0 spikes the EPUB path first (it has the real unknowns); the Compose host is built alongside as the deterministic pipeline proof. AZW3/PDF deferred.

**WI-0 — Readium bilingual spike (new, gates the EPUB render WI):** a throwaway harness that, against a real EPUB on the emulator, proves:
- (a) **enumerate** current-resource leaf blocks via `navigator.evaluateJavascript(enumScript)` returning a JSON `[{id,text}]` array (parse the `String?` result);
- (b) **inject** translation DOM nodes after each block, and **clear** them, via `evaluateJavascript`;
- (c) **re-apply** after `currentLocator` href changes / reflow / page-fragment recreation (the WebView pager recreates fragments — injection must survive or re-fire);
- (d) measure effects on **pagination/scroll** (does injecting content re-paginate? does it shift the reader's position?) and whether the **enumerated block count** diverges from `ChapterSegmenter` (the iOS #268 divergence class — if it diverges, adopt iOS's `translatePreSegmented` direct-block path).

If WI-0 shows injection is stable → the EPUB render WI proceeds. If WI-0 surfaces a blocker (e.g. fragment recreation wipes injected nodes with no re-fire hook) → EPUB drops to a tracked follow-up and box D ships on TXT/MD (the phasing fallback), with the honest reason (a specific spike finding), never the false "requires a fork" claim.

**Rejected alternatives:**
1. **Readium interlinear via decorations only** — REJECTED (insufficient). Decorations style existing text; they cannot insert translation paragraphs. But `evaluateJavascript` (above) makes injection possible without decorations, so EPUB is feasible — it just uses the JS seam, not the decoration seam.
2. **Forking Readium** — REJECTED + unnecessary (the public `evaluateJavascript` seam exists).
3. **AZW3 foliate host first** — REJECTED for v1 (deferred, not dead). Feasible + design-aligned, but touches the security-sensitive #126 bridge; EPUB via the same JS-injection mechanism is the higher-value primary.
4. **Eager whole-book pre-translation** — REJECTED (cost/latency). iOS lazily prefetches current+next + caches — port that.

### The setup-sheet resolution (audit HIGH — rule 51)

There are **two committed, differently-shaped** `BilingualSetupSheet`s:
- `vreader-bilingual.jsx` → **language grid + Granularity (Paragraph/Sentence) + preview strip + Translation-engine strip (Set up/Change) + Cancel/Translate** header. **No Style, no provider/model card, no term-overrides, no cost.**
- `vreader-ai-android.jsx` → **Languages (From/To) + Provider (provider/model card) + Style (Literal/Natural/Literary) + Keep-term-overrides toggle + cost footer.** **No language grid, no Granularity, no preview.**

v1 merged both into a **third layout** — a rule-51 violation (self-designed UI). **Resolution:** this plan reproduces the **`vreader-bilingual.jsx` sheet EXACTLY** as the authoritative Android-native bilingual sheet (its language grid + granularity + preview + engine strip + CTA is the coherent bilingual-config surface, and its `BilingualPill`/`BilingualPageContent` are the matching reader surfaces). **Style is dropped from v1** (it is not in the authoritative sheet, and — verified — `bilingualStyle` is not a persisted contract field on either platform). Consequently the store/VM carry no `style`, and `promptVersion`'s `s=` component is a constant (§2 cache-identity correction).

**Remaining design gate (rule 51):** a single Android sheet that offers **BOTH Style AND Granularity** (the union the `vreader-ai-android.jsx` "Style" and `vreader-bilingual.jsx` "Granularity" controls imply) is **not depicted anywhere** — no committed bundle shows both in one sheet. If style is wanted on Android as a user control, that needs an **updated committed design**. This plan does NOT invent it; it files a `needs-design` gate (see the §"Design gates" list) and ships the authoritative granularity-only sheet meanwhile.

### Other precedents applied

- **#118 provider seam**: reuse `AiProviderStore.snapshot()` (`snapshot.active`) + `store.apiKey(profile)` + `AiProviderFactory.create` (as the default of an injected factory param) + `AiClient.chat`. Prefetcher + readiness are the only new consumers; #118's AI files are unchanged; #131 additionally *wires* `AiProviderStore` into `AppContainer` (which #118 never did).
- **Room additive-migration pattern** (#122/#123/#127): version bump + `MIGRATION_n_(n+1)` + exact-DDL + `VReaderDatabaseMigrationTest` PRAGMA guard. `@PrimaryKey` + `@Upsert` is the project's DAO pattern (`BookDao`).
- **DataStore JSON-in-Preferences** for `PerBookBilingualStore` (the `ReaderSettingsStore`/`AiProviderStore` pattern).
- **Pure-logic port**: iOS `ChapterSegmenter`/`ChapterTranslationChunker`/`TranslationChunkContract` are pure + heavily unit-tested — direct Kotlin ports with the same test vectors (all verified to exist).
- **Entry point via box F**: the More-menu bilingual toggle + top-chrome pill are box-F surfaces; #131 depends on them (§4), mirroring how box B's annotations-review-sheet + bookmark "ride with item F."

## 4. Work-item sequencing

Foundational WI-1..4 (no UI, JVM-testable); a spike WI-0 (EPUB); behavioral WI-5..9. Each WI = one PR.

**Dependency notes (audit HIGH — v1's graph was wrong):**
- WI-3 depends on WI-1 (+2). WI-4 depends on WI-1+WI-3. WI-6 depends on WI-5. So WI-1..4 are NOT all independent — the graph below states the real edges.
- **`Deps: [feat:#134, feat:#132]`** (transitively #129, #118) — box F is not yet decomposed (per `docs/parity/android-checklist.md`, box F "likely splits into ≥2 features: TOC/bookmarks; find-in-book; more-menu/details/share"); **#132 = the top-chrome sub-feature, #134 = the More-menu sub-feature** are the prospective box-F IDs this plan reserves. **#131's UI entry-point WIs (the pill mount + the More-menu toggle wiring) cannot ship until box F provides those surfaces.** The pipeline + setup sheet + interlinear render (WI-0..7) are built ahead; only the entry wiring (part of WI-9) waits on box F.
- **Host-integration WIs are gated on #129's FINAL merge** — #129 owns `TxtReaderActivity`/`ReaderBottomChrome`; #131's `TxtReaderActivity` edit must land on top of #129's TXT/MD typography WIs (rule 48 one-writer-per-file).

**WI-0 (spike): Readium EPUB bilingual injection.** The harness in §3 (enumerate / inject+clear / re-apply on reflow / pagination + count-divergence measurement). Output: a go/no-go on EPUB-in-v1 + the concrete `EpubChapterTextProvider` + injection-adapter surface. Deps: none (uses the existing #106 Readium host). Not TDD-gated (throwaway spike); its findings feed WI-7b's plan.

**WI-1 (foundational): value types + pure segmentation/chunk/contract.** `TranslationUnitId`, `TranslationGranularity`, `BilingualLanguages`, `ChapterSegmenter`, `TranslationChunker`, `TranslationChunkContract`, `ChapterTranslationError`. Pure; ported iOS vectors. No Android deps. Deps: none.

**WI-2 (foundational): Room translation cache.** `ChapterTranslationEntity` (PK = `lookupKey`) + `Dao` (`@Upsert`) + `ChapterTranslationStore`; `VReaderDatabase` migration (number at slot). Robolectric migration round-trip + upsert/get/delete-by-lookupKey + FK-CASCADE + exact-DDL guard. Deps: none.

**WI-3 (foundational): `ChapterTranslationService`** against a fake `AiClient`. `cachedTranslation` (cache-only) + `translate` (per-chunk `chat`, per-segment decode-fail fallback, per-chunk graceful degrade, cancellation between chunks + before write, cache-write only on full success). Deps: **WI-1, WI-2**. Tests: cache hit → zero client calls; miss → translate + write; decode fail → per-segment fallback; one-chunk fail → source-only that chunk (others translated, NOT cached); all-chunks fail → throw; cancellation → `Cancelled` (no write); `AiError` mapping incl. `Config`/`InsecureUrl` → `ProviderFailed`.

**WI-4 (foundational): `ChapterTextProvider` (TXT/MD) + `ChapterTranslationPrefetcher` + `BilingualAiReadiness`.** Provider slices per chapter from `TxtDocument`; `unitContaining`/`unitAfter`. Prefetcher resolves active profile from `snapshot()`, decrypts snapshot-consistent, builds client via the **injected factory param** (default `AiProviderFactory::create`), constructs `AiRequest` from the profile, cache-first then translate. Readiness = active profile with non-empty decrypted key; **cipher failure → not-ready, never a crash.** Fake store + fake factory. Deps: **WI-1, WI-3**. Tests: unit resolution + clamp + empty; cache-hit-no-profile still returns (#306); no-profile miss → `ProviderFailed`; readiness true/false; cipher-throw → readiness false (no crash).

**WI-5 (behavioral): `PerBookBilingualStore` + `BilingualViewModel` state core.** Store per book (enabled/targetLanguage/granularity — no style); VM setters (persist + first-enable `needsSetupSheet`), language/granularity change clears cache-shaped state + bumps generation, the state fields. Turbine tests: first-enable raises sheet; re-enable persisted does not; disable clears; language change resets; granularity change resets + re-keys; round-trip through store. Deps: **WI-1** (+ store).

**WI-6 (behavioral): VM prefetch trigger + generation/cancellation.** `onPositionChanged` derives current unit, dedupes, prefetches current+next; a **monotonic position-request sequence** checked after every suspension; **per-unit generation tokens**; a **captured language/granularity/provider snapshot per launch**; generation bumps on disable/language/granularity/unit-change discard stale; `CancellationException` handled BEFORE generic error mapping; `Offline`→`unavailableUnits`; transient failure leaves unit unfetched + clears anchor to retry; `retryUnit`. Fake prefetcher. Deps: **WI-4, WI-5**. Tests: current+next on unit change; same-unit no-op; cancel-mid discards stale; offline→unavailable; failure→retry-able; `retryUnit` re-fetches; granularity change cancels + re-fetches under the new key.

**WI-7a (behavioral): Compose UI — setup sheet + interlinear body + pill.** Reproduce `vreader-bilingual.jsx` (setup sheet: language grid / granularity / preview / engine strip configured+unconfigured; body: translated / loading N%+dimmed / error+Retry / offline source-only; pill). Light+dark. Compose UI tests each state. Deps: **WI-5** (state shape). NO Style control; the unconfigured "Set up" CTA renders but its nav target is design-gated (§3).

**WI-7b (behavioral): EPUB render adapter** (only if WI-0 = go). The JS enumerate/inject adapter + `EpubChapterTextProvider`, wired into `ReaderActivity`, driving `BilingualInterlinearBody` state from injected content. Deps: **WI-0, WI-3, WI-4, WI-7a**. Connected test on a real EPUB (seeded cache): enable → interlinear injects; disable → nodes cleared; reflow/href-change re-applies. (If WI-0 = no-go, this WI is dropped and box D ships TXT/MD-only, tracked.)

**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into `TxtBody` loop + position-change + setup-sheet + DI (incl. adding `AiProviderStore` to `AppContainer`). `originalFormat`-gated (TXT/MD). **Gated on #129's final merge.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; disable → source-only byte-parity; reopen persists enabled + renders from cache with zero client calls. Deps: **WI-6, WI-7a, #129 final**.

**WI-9 (behavioral): entry wiring + acceptance.** Mount `BilingualPill` in box F's top chrome; wire the More-menu bilingual toggle (box F) to the VM. **Gated on `feat:#132` (top chrome) + `feat:#134` (More menu).** Full acceptance pass across EPUB (if WI-7b landed) + TXT/MD. Flip box D note; update `docs/architecture.md` (bilingual pipeline + the new `chapter_translations` schema + `AiProviderStore` now in `AppContainer`). → DONE. Deps: **WI-8, WI-7b (if go), feat:#132, feat:#134**.

## 5. Test catalogue

JVM/Robolectric (`android/app/src/test/...bilingual/`): `ChapterSegmenterTest` (paragraph blank-line; sentence CJK 。！？ vs Latin; empty→[]; single); `TranslationChunkerTest` (packs to budget; oversize→own chunk+subSplit; empty→[]); `TranslationChunkContractTest` (prompt per style-constant; strict JSON decode; code-fence strip; count mismatch→`CountMismatch`; non-array→`NotAStringArray`); `ChapterTranslationServiceTest` (cache hit 0 calls; miss→translate→write; decode-fail per-segment fallback; one-chunk-fail partial-not-cached; all-fail→throw; cancellation→Cancelled no write; ensureActive-before-write; offline/timeout/429/http/config/insecure→error mapping; very long chapter N-of-M; stale-cache count-mismatch re-translates); `ChapterTranslationErrorMappingTest`; `TxtChapterTextProviderTest` (resolution; clamp-past-end; empty; unitAfter end→null); `ChapterTranslationPrefetcherTest` (snapshot-consistent profile+key; injected-factory used; `AiRequest` built from profile; cache-hit-no-profile #306; no-profile miss→ProviderFailed; CJK↔English + Latin round-trip via fake; cipher-throw→ProviderFailed not crash); `BilingualAiReadinessTest` (active+key→true; no active→false; empty key→false; **cipher-throw→false, no crash**); `PerBookBilingualStoreTest` (enabled/lang/granularity round-trip; no style field); `BilingualViewModelTest` (Turbine: first-enable sheet; re-enable no-sheet; disable clears; language reset; **granularity reset + re-key**; prefetch current+next; same-unit no-op; cancel-mid discards; offline→unavailable; error→errorUnit+retry; `retryUnit`; generation bump on style-N/A—granularity change).

Room migration: `VReaderDatabaseMigrationTest` (extend) vPrev→vNext + full-chain + FK-CASCADE + `lookupKey`-as-PK; `ChapterTranslationDaoTest` (upsert-by-PK replaces; get/delete-by-lookupKey).

Compose UI (`androidTest/...bilingual/`): `BilingualSetupSheetUiTest` (language grid, granularity, preview, engine configured vs unconfigured; **no Style control present**; light+dark); `BilingualInterlinearBodyUiTest` (translated incl. CJK font + RTL Arabic; loading N%+dimmed; error+Retry; offline source-only; empty translation→source-only no crash); `BilingualPillUiTest`.

Connected (`androidTest/...reader/`): `TxtReaderBilingualConnectedTest` (API 35, fake `AiClient` via injected factory): enable→setup→confirm→interlinear from seeded Room cache; disable→source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; TXT/MD gated (PDF inert); very long chapter scroll responsive; cancellation leaves no partial cache row. `EpubReaderBilingualConnectedTest` (only if WI-0=go): enable→inject on a real EPUB; disable→clear; href-change→re-apply; count-divergence handled.

Edge cases: empty translation, failed, partial per-chunk, CJK↔English + Latin + RTL, provider error/timeout/429/config/insecure, cancellation mid-translation + before-write, very long chapters, offline (cache-first + silent source-only), cipher-decrypt failure → not-ready (no crash).

## 6. Risks + mitigations

- **Live-translation verification is AI-credential-gated (the box-D caveat).** The whole pipeline is verified without live creds via a deterministic **fake `AiClient`** injected through the prefetcher's `clientFactory` param (default `AiProviderFactory::create`; tests override). WI-3/4/8 prove segment→chunk→decode→cache→interleave end-to-end incl. every error/edge path. The connected test seeds the Room cache directly and asserts render-from-cache with zero client calls (render path proven offline). **This mock/integration path is the box-D-required verification path** (the checklist states live translation is credential-gated); an optional live smoke confirms wire format but is NOT a gate.
- **Acceptance proves BOTH cache-render AND the live pipeline path (via the fake).** WI-8's connected test drives the full enable→translate(fake)→cache→render→reopen cycle, not just cache rendering — the fake stands in only for the network leaf.
- **EPUB JS-injection unknowns.** WI-0 de-risks before the render WI: pagination shift, fragment recreation wiping nodes, enumerate-vs-`ChapterSegmenter` count divergence (iOS #268). If a hard blocker appears, EPUB drops to a tracked follow-up (phasing fallback) with the specific spike reason — never the false "requires a fork."
- **Concurrency (audit HIGH — was under-specified).** WI-6 adds: a monotonic position-request sequence checked after every suspension; per-unit generation tokens; a captured language/granularity/provider snapshot per launch; cancellation on granularity change; `CancellationException` handled BEFORE generic error mapping; `ensureActive()` immediately before the Room write; cipher/decrypt failures mapped to unconfigured/provider-failure (never a crash). Snapshot-consistent profile+key pairing (from one `snapshot()`) is preserved.
- **Segment↔render count divergence** (iOS Bugs #268/#330/#344). TXT/MD segment through the SAME `ChapterSegmenter` on translate + render sides, so 1:1 pairing holds by construction; granularity is in the cache key so a paragraph row is never read as sentences. EPUB uses WI-0's finding (direct-block path if enumerate diverges — iOS `translatePreSegmented` parity).
- **Cost/latency of translating on scroll.** Lazy current+next prefetch + disk cache; N-of-M progress; cancellation on navigate-away/generation-bump.
- **Provider JSON non-compliance.** `TranslationChunkContract.decode` + per-segment fallback (iOS parity) — never drops a paragraph.
- **DataStore per-book key growth.** One Preferences entry per book keyed by fingerprint; scales like `ReaderSettingsStore`/`AiProviderStore`.

## 7. Backward compat

- **Room migration additive** (new `chapter_translations`, FK CASCADE, `lookupKey` PK). Existing rows untouched; migration + structural test guard it. Version number allocated at the merge slot (v5 today → v6).
- **Reader unchanged when bilingual off** — `TxtBody` render loop byte-identical unless `enabled && format∈{txt,md} && translation present`. `ReaderBottomChrome` is **not modified** (v1's Translate slot removed), so #129's chrome is unaffected. EPUB render adapter is inert unless bilingual is on.
- **#118 AI provider files unchanged** — the prefetcher/readiness are new consumers; the only #118-adjacent change is *wiring* `AiProviderStore` into `AppContainer` (which #118 left unwired — it was component/round-trip-verified, not nav-integrated).
- **Backup contract already compatible** — `PerBookSettingsOverride.bilingualEnabled/TargetLanguage/Granularity` exist (verified; **no `bilingualStyle`**), and there is **no translation-cache section** in `contracts/vectors/backup-sections.json` (verified — the cache is device-local, re-derivable). v1 introduces the store that writes the three fields locally; backup collect/restore of them is a small additive follow-up (no contract change), out of v1 scope; until then bilingual config is device-local (safe default). The `PerBookBilingualStore` is confirmed device-local; backup-collect/restore is the scoped-out follow-up.

## Design gates (rule 51 — for `needs-design` filing)

1. **"Bilingual mode" setup sheet with BOTH Style AND Granularity in one Android sheet** — `vreader-bilingual.jsx` depicts Granularity (no Style); `vreader-ai-android.jsx` depicts Style (no Granularity); no committed bundle shows both together. v1 reproduces the granularity-only `vreader-bilingual.jsx` sheet and DROPS Style. If Style is wanted as an Android user control, file `Design needed: bilingual setup sheet (Style + Granularity) for feature #131`. **This is the one open design gate for #131.**
2. **Dependency gate (not a #131 design gate, but blocks the "Set up" affordance)** — the setup sheet's unconfigured "Set up" CTA has no live nav destination (`AiProviderListScreen` is unreachable in-app today; no `#119`). #131 does not invent it (box-F chrome / #118 follow-on); the CTA renders but is wired only once that route ships.

## Revision history

- v1 (2026-07-10): Gate-1 draft (Plan agent). Gate-2 Codex audit pending.
- v2 (2026-07-11): Gate-2 round-1 REDESIGN resolved — Readium-feasibility corrected, entry-point rebased on box F, setup-sheet design-gated, DI/cache/concurrency fixed.
209:| `ChapterTranslationService`          | `ChapterTranslationStore` + `AIService` | Translates one chapter unit for feature #56 bilingual reading. Pipeline: cache lookup → (on miss) `ChapterSegmenter` → `ChapterTranslationChunker` → one `AIService.sendRequest(_:using:)` per chunk → strict `TranslationChunkContract` JSON-array decode → per-segment fallback on any decode/count/element mismatch → recombine → cache-write. Reaches the AI side through the `TranslationRequestSending` boundary protocol (tests inject a mock). `Task.checkCancellation()` between chunks so a cancelled prefetch stops promptly |
512:## Android App (`android/` — feature #106 foundation bar)
514:vreader's Android app is a **second, independently-shippable native app**
535:| `:app` | Android application | Compose UI shell + the Room data layer + reader plumbing. `com.vreader.app`. |
536:| `:identity` | pure Kotlin/JVM (no Android deps) | The shared canonical contracts — `Identity` (fingerprint canonical key), `CanonicalLocator` (engine-neutral canonical JSON), `DocumentFingerprint` (streaming SHA-256 + format detection), and the `Locator` / `VReaderLocator` / `ReaderLocatorEngine` value types. **Both `:app` AND the `contracts/conformance` lane depend on this one module**, so the golden-vector conformance test proves the SAME code the app runs. |
540:- **Room** is the SwiftData analog. `VReaderDatabase` (`@Database` v4,
604:<sha>_<bytes>.<canonicalExt>` = content-addressed blob store), so an Android
612:| `net.SecretCipher` / `KeystoreSecretCipher` | AndroidKeyStore | AES-256-GCM (fresh IV, non-exportable key) for the password at rest — the EncryptedSharedPreferences replacement. |
648:| `AiProviderStore` | DataStore JSON list of provider profiles + an active-id; API key kept ONLY as a `KeystoreSecretCipher` token. Snapshot-consistent `apiKey(profile)`. |
667:| `AnnotationColor` | The 5 design colors (yellow/green/blue/pink/red — design parity; iOS has 4, `red` is Android-only). |
674:`ReaderActivity` configures the `EpubNavigatorFragment` with a `selectionActionModeCallback` that
677:(`ReaderActivityTest.seededHighlight_appliesAsDecoration_onLiveNavigator` drives the real WebView).
679:**TXT highlighting (feature #124)** reuses the same domain on the `TxtReaderActivity` side via a
685:`TxtHighlightHitTester`. **Feature #125 extended this to MD** (the same `TxtReaderActivity` hosts both):
690:marker-only slice washes nothing). The old `BookFormat.txt` gate is gone — `TxtReaderActivity` builds the
693:harness (`TxtReaderActivityTest` long-press/tap E2E), unlike the EPUB WebView gesture.
710:The TXT reader (`TxtReaderActivity`) brackets a session from the Activity

exec
/bin/zsh -lc "nl -ba dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md | sed -n '90,170p'
rg --files android/app/src | rg '(ReaderActivity|TxtReaderActivity|VReaderDatabase|AiProvider|AiClient|AiRequest|ChapterSegment|Translation|AppContainer|VReaderApp|BackupSections|ReaderSettingsStore)'
rg -n \"class ReaderActivity|EpubNavigatorFragment|evaluateJavascript|currentLocator|submitPreferences|onDestroy|onStop|Fragment|class TxtReaderActivity|fun TxtBody|items\\(\" android/app/src/main android/app/src/test android/app/src/androidTest" in /Users/ll/workspace/vreader
 succeeded in 0ms:
    90	- **Streaming translation progress** — the design's "38%" is chapter-level N-of-M chunk progress (from the chunker count), not token streaming. v1 shows N-of-M.
    91	
    92	## 3. Prior art / project precedent / rejected alternatives
    93	
    94	### The render-host decision (analysis — CORRECTED from v1)
    95	
    96	**How iOS does interlinear:** iOS renders EPUB/AZW3 in a WKWebView it fully controls. `EPUBBilingualOrchestrator` injects JS that (1) enumerates leaf blocks (`<p>/<li>/<blockquote>`) posting `[{bid,text}]` to Swift, (2) after translation injects a translation node after each block. TXT/MD render in a `UITextView`/attributed-string path where the renderer interleaves translation runs. The mechanism = **the app inserts translation nodes between source nodes.**
    97	
    98	**Android host-by-host injectability — the v1 verdict was WRONG for EPUB:**
    99	
   100	| Host | Layout tree owner | Content-insertion API | Interlinear feasible? |
   101	|---|---|---|---|
   102	| **Readium EPUB** (`EpubNavigatorFragment`) | Readium (internal WebView) | **`evaluateJavascript(script): String?`** is PUBLIC on the fragment (shipped 3.3.0 AAR) → arbitrary DOM read/write. Plus `currentLocator` (href), `firstVisibleElementLocator`, decorations (Highlight/Underline over existing text). | **YES — via JS injection** (not just decorations) |
   103	| **TXT/MD Compose** (`TxtReaderActivity`) | The app (`LazyColumn` over chunks) | Trivial — a translation `Text` after each source `Text` in the confirmed `items{}` loop | **YES** |
   104	| **AZW3 foliate** (`FoliateBridge` WebView) | The app (pinned foliate-js bundle) | Full DOM control via the bridge (same as iOS) | YES, but needs bundle-JS → follow-up |
   105	
   106	**Verification of the CRITICAL correction:** `javap -public org.readium.r2.navigator.epub.EpubNavigatorFragment` against the resolved AAR (`~/.gradle/caches/.../readium-navigator/3.3.0/.../readium-navigator-3.3.0.aar`) prints:
   107	```
   108	public final java.lang.Object evaluateJavascript(java.lang.String, kotlin.coroutines.Continuation<? super java.lang.String>);
   109	public kotlinx.coroutines.flow.StateFlow<org.readium.r2.shared.publication.Locator> getCurrentLocator();
   110	public java.lang.Object firstVisibleElementLocator(kotlin.coroutines.Continuation<...>);
   111	```
   112	i.e. `suspend fun evaluateJavascript(String): String?` exists. The app already holds the concrete fragment as `ReaderActivity.navigator` (it uses it for decorations/selection in #123). So EPUB interlinear via JS injection is feasible with the public API — **no Readium fork.** The v1 "infeasible inside Readium's navigator" rationale is discarded.
   113	
   114	**Chosen: EPUB (Readium JS-injection) as the PRIMARY host + TXT/MD (Compose) included.** WI-0 spikes the EPUB path first (it has the real unknowns); the Compose host is built alongside as the deterministic pipeline proof. AZW3/PDF deferred.
   115	
   116	**WI-0 — Readium bilingual spike (new, gates the EPUB render WI):** a throwaway harness that, against a real EPUB on the emulator, proves:
   117	- (a) **enumerate** current-resource leaf blocks via `navigator.evaluateJavascript(enumScript)` returning a JSON `[{id,text}]` array (parse the `String?` result);
   118	- (b) **inject** translation DOM nodes after each block, and **clear** them, via `evaluateJavascript`;
   119	- (c) **re-apply** after `currentLocator` href changes / reflow / page-fragment recreation (the WebView pager recreates fragments — injection must survive or re-fire);
   120	- (d) measure effects on **pagination/scroll** (does injecting content re-paginate? does it shift the reader's position?) and whether the **enumerated block count** diverges from `ChapterSegmenter` (the iOS #268 divergence class — if it diverges, adopt iOS's `translatePreSegmented` direct-block path).
   121	
   122	If WI-0 shows injection is stable → the EPUB render WI proceeds. If WI-0 surfaces a blocker (e.g. fragment recreation wipes injected nodes with no re-fire hook) → EPUB drops to a tracked follow-up and box D ships on TXT/MD (the phasing fallback), with the honest reason (a specific spike finding), never the false "requires a fork" claim.
   123	
   124	**Rejected alternatives:**
   125	1. **Readium interlinear via decorations only** — REJECTED (insufficient). Decorations style existing text; they cannot insert translation paragraphs. But `evaluateJavascript` (above) makes injection possible without decorations, so EPUB is feasible — it just uses the JS seam, not the decoration seam.
   126	2. **Forking Readium** — REJECTED + unnecessary (the public `evaluateJavascript` seam exists).
   127	3. **AZW3 foliate host first** — REJECTED for v1 (deferred, not dead). Feasible + design-aligned, but touches the security-sensitive #126 bridge; EPUB via the same JS-injection mechanism is the higher-value primary.
   128	4. **Eager whole-book pre-translation** — REJECTED (cost/latency). iOS lazily prefetches current+next + caches — port that.
   129	
   130	### The setup-sheet resolution (audit HIGH — rule 51)
   131	
   132	There are **two committed, differently-shaped** `BilingualSetupSheet`s:
   133	- `vreader-bilingual.jsx` → **language grid + Granularity (Paragraph/Sentence) + preview strip + Translation-engine strip (Set up/Change) + Cancel/Translate** header. **No Style, no provider/model card, no term-overrides, no cost.**
   134	- `vreader-ai-android.jsx` → **Languages (From/To) + Provider (provider/model card) + Style (Literal/Natural/Literary) + Keep-term-overrides toggle + cost footer.** **No language grid, no Granularity, no preview.**
   135	
   136	v1 merged both into a **third layout** — a rule-51 violation (self-designed UI). **Resolution:** this plan reproduces the **`vreader-bilingual.jsx` sheet EXACTLY** as the authoritative Android-native bilingual sheet (its language grid + granularity + preview + engine strip + CTA is the coherent bilingual-config surface, and its `BilingualPill`/`BilingualPageContent` are the matching reader surfaces). **Style is dropped from v1** (it is not in the authoritative sheet, and — verified — `bilingualStyle` is not a persisted contract field on either platform). Consequently the store/VM carry no `style`, and `promptVersion`'s `s=` component is a constant (§2 cache-identity correction).
   137	
   138	**Remaining design gate (rule 51):** a single Android sheet that offers **BOTH Style AND Granularity** (the union the `vreader-ai-android.jsx` "Style" and `vreader-bilingual.jsx` "Granularity" controls imply) is **not depicted anywhere** — no committed bundle shows both in one sheet. If style is wanted on Android as a user control, that needs an **updated committed design**. This plan does NOT invent it; it files a `needs-design` gate (see the §"Design gates" list) and ships the authoritative granularity-only sheet meanwhile.
   139	
   140	### Other precedents applied
   141	
   142	- **#118 provider seam**: reuse `AiProviderStore.snapshot()` (`snapshot.active`) + `store.apiKey(profile)` + `AiProviderFactory.create` (as the default of an injected factory param) + `AiClient.chat`. Prefetcher + readiness are the only new consumers; #118's AI files are unchanged; #131 additionally *wires* `AiProviderStore` into `AppContainer` (which #118 never did).
   143	- **Room additive-migration pattern** (#122/#123/#127): version bump + `MIGRATION_n_(n+1)` + exact-DDL + `VReaderDatabaseMigrationTest` PRAGMA guard. `@PrimaryKey` + `@Upsert` is the project's DAO pattern (`BookDao`).
   144	- **DataStore JSON-in-Preferences** for `PerBookBilingualStore` (the `ReaderSettingsStore`/`AiProviderStore` pattern).
   145	- **Pure-logic port**: iOS `ChapterSegmenter`/`ChapterTranslationChunker`/`TranslationChunkContract` are pure + heavily unit-tested — direct Kotlin ports with the same test vectors (all verified to exist).
   146	- **Entry point via box F**: the More-menu bilingual toggle + top-chrome pill are box-F surfaces; #131 depends on them (§4), mirroring how box B's annotations-review-sheet + bookmark "ride with item F."
   147	
   148	## 4. Work-item sequencing
   149	
   150	Foundational WI-1..4 (no UI, JVM-testable); a spike WI-0 (EPUB); behavioral WI-5..9. Each WI = one PR.
   151	
   152	**Dependency notes (audit HIGH — v1's graph was wrong):**
   153	- WI-3 depends on WI-1 (+2). WI-4 depends on WI-1+WI-3. WI-6 depends on WI-5. So WI-1..4 are NOT all independent — the graph below states the real edges.
   154	- **`Deps: [feat:#134, feat:#132]`** (transitively #129, #118) — box F is not yet decomposed (per `docs/parity/android-checklist.md`, box F "likely splits into ≥2 features: TOC/bookmarks; find-in-book; more-menu/details/share"); **#132 = the top-chrome sub-feature, #134 = the More-menu sub-feature** are the prospective box-F IDs this plan reserves. **#131's UI entry-point WIs (the pill mount + the More-menu toggle wiring) cannot ship until box F provides those surfaces.** The pipeline + setup sheet + interlinear render (WI-0..7) are built ahead; only the entry wiring (part of WI-9) waits on box F.
   155	- **Host-integration WIs are gated on #129's FINAL merge** — #129 owns `TxtReaderActivity`/`ReaderBottomChrome`; #131's `TxtReaderActivity` edit must land on top of #129's TXT/MD typography WIs (rule 48 one-writer-per-file).
   156	
   157	**WI-0 (spike): Readium EPUB bilingual injection.** The harness in §3 (enumerate / inject+clear / re-apply on reflow / pagination + count-divergence measurement). Output: a go/no-go on EPUB-in-v1 + the concrete `EpubChapterTextProvider` + injection-adapter surface. Deps: none (uses the existing #106 Readium host). Not TDD-gated (throwaway spike); its findings feed WI-7b's plan.
   158	
   159	**WI-1 (foundational): value types + pure segmentation/chunk/contract.** `TranslationUnitId`, `TranslationGranularity`, `BilingualLanguages`, `ChapterSegmenter`, `TranslationChunker`, `TranslationChunkContract`, `ChapterTranslationError`. Pure; ported iOS vectors. No Android deps. Deps: none.
   160	
   161	**WI-2 (foundational): Room translation cache.** `ChapterTranslationEntity` (PK = `lookupKey`) + `Dao` (`@Upsert`) + `ChapterTranslationStore`; `VReaderDatabase` migration (number at slot). Robolectric migration round-trip + upsert/get/delete-by-lookupKey + FK-CASCADE + exact-DDL guard. Deps: none.
   162	
   163	**WI-3 (foundational): `ChapterTranslationService`** against a fake `AiClient`. `cachedTranslation` (cache-only) + `translate` (per-chunk `chat`, per-segment decode-fail fallback, per-chunk graceful degrade, cancellation between chunks + before write, cache-write only on full success). Deps: **WI-1, WI-2**. Tests: cache hit → zero client calls; miss → translate + write; decode fail → per-segment fallback; one-chunk fail → source-only that chunk (others translated, NOT cached); all-chunks fail → throw; cancellation → `Cancelled` (no write); `AiError` mapping incl. `Config`/`InsecureUrl` → `ProviderFailed`.
   164	
   165	**WI-4 (foundational): `ChapterTextProvider` (TXT/MD) + `ChapterTranslationPrefetcher` + `BilingualAiReadiness`.** Provider slices per chapter from `TxtDocument`; `unitContaining`/`unitAfter`. Prefetcher resolves active profile from `snapshot()`, decrypts snapshot-consistent, builds client via the **injected factory param** (default `AiProviderFactory::create`), constructs `AiRequest` from the profile, cache-first then translate. Readiness = active profile with non-empty decrypted key; **cipher failure → not-ready, never a crash.** Fake store + fake factory. Deps: **WI-1, WI-3**. Tests: unit resolution + clamp + empty; cache-hit-no-profile still returns (#306); no-profile miss → `ProviderFailed`; readiness true/false; cipher-throw → readiness false (no crash).
   166	
   167	**WI-5 (behavioral): `PerBookBilingualStore` + `BilingualViewModel` state core.** Store per book (enabled/targetLanguage/granularity — no style); VM setters (persist + first-enable `needsSetupSheet`), language/granularity change clears cache-shaped state + bumps generation, the state fields. Turbine tests: first-enable raises sheet; re-enable persisted does not; disable clears; language change resets; granularity change resets + re-keys; round-trip through store. Deps: **WI-1** (+ store).
   168	
   169	**WI-6 (behavioral): VM prefetch trigger + generation/cancellation.** `onPositionChanged` derives current unit, dedupes, prefetches current+next; a **monotonic position-request sequence** checked after every suspension; **per-unit generation tokens**; a **captured language/granularity/provider snapshot per launch**; generation bumps on disable/language/granularity/unit-change discard stale; `CancellationException` handled BEFORE generic error mapping; `Offline`→`unavailableUnits`; transient failure leaves unit unfetched + clears anchor to retry; `retryUnit`. Fake prefetcher. Deps: **WI-4, WI-5**. Tests: current+next on unit change; same-unit no-op; cancel-mid discards stale; offline→unavailable; failure→retry-able; `retryUnit` re-fetches; granularity change cancels + re-fetches under the new key.
   170	
android/app/src/test/kotlin/com/vreader/app/data/VReaderDatabaseMigrationTest.kt
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderEditSheetTest.kt
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderListScreenTest.kt
android/app/src/test/kotlin/com/vreader/app/ai/AiProviderStoreTest.kt
android/app/src/test/kotlin/com/vreader/app/ai/AiProviderKindTest.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderFactory.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiClient.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderKind.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt
android/app/src/test/kotlin/com/vreader/app/reader/settings/ReaderSettingsStoreTest.kt
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt
android/app/src/androidTest/kotlin/com/vreader/app/reader/PdfReaderActivityTest.kt
android/app/src/androidTest/kotlin/com/vreader/app/reader/TxtReaderActivityTest.kt
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt
android/app/src/androidTest/kotlin/com/vreader/app/reader/Azw3ReaderActivityTest.kt
android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderActivityTest.kt
android/app/src/test/kotlin/com/vreader/app/opds/OpdsParserTest.kt:138:    @Test fun resolvesQueryAndFragmentOnlyHrefs_preserveBasePath() {
android/app/src/main/assets/foliate/foliate-bundle.js:1500:  var NS, MIME, PREFIX, RELATORS, ONIX5, camel, normalizeWhitespace, filterAttribute, getAttributes, getElementText, childGetter, resolveURL, isExternal, pathRelative, pathDirname, replaceSeries, regexEscape, tidy, getPrefixes, getPropertyURL, getMetadata, parseNav, parseNCX, parseClock, MediaOverlay, isUUID, getUUID, getIdentifier, deobfuscate, WebCryptoSHA1, deobfuscators, Encryption, Resources, Loader, getHTMLFragment, getPageSpread, getDisplayOptions, EPUB;
android/app/src/main/assets/foliate/foliate-bundle.js:2274:      getHTMLFragment = (doc, id) => doc.getElementById(id) ?? doc.querySelector(`[name="${CSS.escape(id)}"]`);
android/app/src/main/assets/foliate/foliate-bundle.js:2402:          const anchor = hash ? (doc) => getHTMLFragment(doc, hash) : () => 0;
android/app/src/main/assets/foliate/foliate-bundle.js:2408:        getTOCFragment(doc, id) {
android/app/src/main/assets/foliate/foliate-bundle.js:2489:  var unescapeHTML, MIME2, PDB_HEADER, PALMDOC_HEADER, MOBI_HEADER, KF8_HEADER, EXTH_HEADER, INDX_HEADER, TAGX_HEADER, HUFF_HEADER, CDIC_HEADER, FDST_HEADER, FONT_HEADER, MOBI_ENCODING, EXTH_RECORD_TYPE, MOBI_LANG, concatTypedArray, concatTypedArray3, decoder, getString, getUint, getStruct, getDecoder, getVarLen, getVarLenFromEnd, countBitsSet, countUnsetEnd, decompressPalmDOC, read32Bits, huffcdic, getIndexData, getNCX, getEXTH, getFont, isMOBI, PDB, MOBI, mbpPagebreakRegex, fileposRegex, getIndent, MOBI6, kindleResourceRegex, kindlePosRegex, parseResourceURI, parsePosURI, makePosURI, getFragmentSelector, replaceSeries2, getPageSpread2, KF8;
android/app/src/main/assets/foliate/foliate-bundle.js:3359:        getTOCFragment(doc, id) {
android/app/src/main/assets/foliate/foliate-bundle.js:3381:      getFragmentSelector = (str) => {
android/app/src/main/assets/foliate/foliate-bundle.js:3610:              const selector = getFragmentSelector(str);
android/app/src/main/assets/foliate/foliate-bundle.js:3611:              this.#setFragmentSelector(frag.index, offset2, selector);
android/app/src/main/assets/foliate/foliate-bundle.js:3642:        #setFragmentSelector(id, offset, selector) {
android/app/src/main/assets/foliate/foliate-bundle.js:3662:          const selector = getFragmentSelector(str);
android/app/src/main/assets/foliate/foliate-bundle.js:3663:          this.#setFragmentSelector(fid, off, selector);
android/app/src/main/assets/foliate/foliate-bundle.js:3672:        getTOCFragment(doc, { fid, off }) {
android/app/src/main/assets/foliate/foliate-bundle.js:5828:  var NS2, blockTags, getLang, getAlphabet, getSegmenter, fragmentToSSML, getFragmentWithMarks, rangeIsEmpty, ListIterator, TTS;
android/app/src/main/assets/foliate/foliate-bundle.js:5946:      getFragmentWithMarks = (range, textWalker2, granularity) => {
android/app/src/main/assets/foliate/foliate-bundle.js:6030:            const { entries, ssml } = getFragmentWithMarks(range, textWalker2, granularity);
android/app/src/main/assets/foliate/foliate-bundle.js:6112:    async init({ toc, ids, splitHref, getFragment }) {
android/app/src/main/assets/foliate/foliate-bundle.js:6129:      this.getFragment = getFragment;
android/app/src/main/assets/foliate/foliate-bundle.js:6141:        const el = this.getFragment(doc, fragment);
android/app/src/main/assets/foliate/foliate-bundle.js:6661:      if (book.splitTOCHref && book.getTOCFragment) {
android/app/src/main/assets/foliate/foliate-bundle.js:6665:        const getFragment = book.getTOCFragment.bind(book);
android/app/src/main/assets/foliate/foliate-bundle.js:6671:          getFragment
android/app/src/main/assets/foliate/foliate-bundle.js:6678:          getFragment
android/app/src/test/kotlin/com/vreader/app/reader/ReadiumLocatorReconstructorTest.kt:128:    fun cfi_carriedAsFragment() = runTest {
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:1500:  var NS, MIME, PREFIX, RELATORS, ONIX5, camel, normalizeWhitespace, filterAttribute, getAttributes, getElementText, childGetter, resolveURL, isExternal, pathRelative, pathDirname, replaceSeries, regexEscape, tidy, getPrefixes, getPropertyURL, getMetadata, parseNav, parseNCX, parseClock, MediaOverlay, isUUID, getUUID, getIdentifier, deobfuscate, WebCryptoSHA1, deobfuscators, Encryption, Resources, Loader, getHTMLFragment, getPageSpread, getDisplayOptions, EPUB;
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:2274:      getHTMLFragment = (doc, id) => doc.getElementById(id) ?? doc.querySelector(`[name="${CSS.escape(id)}"]`);
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:2402:          const anchor = hash ? (doc) => getHTMLFragment(doc, hash) : () => 0;
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:2408:        getTOCFragment(doc, id) {
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:2489:  var unescapeHTML, MIME2, PDB_HEADER, PALMDOC_HEADER, MOBI_HEADER, KF8_HEADER, EXTH_HEADER, INDX_HEADER, TAGX_HEADER, HUFF_HEADER, CDIC_HEADER, FDST_HEADER, FONT_HEADER, MOBI_ENCODING, EXTH_RECORD_TYPE, MOBI_LANG, concatTypedArray, concatTypedArray3, decoder, getString, getUint, getStruct, getDecoder, getVarLen, getVarLenFromEnd, countBitsSet, countUnsetEnd, decompressPalmDOC, read32Bits, huffcdic, getIndexData, getNCX, getEXTH, getFont, isMOBI, PDB, MOBI, mbpPagebreakRegex, fileposRegex, getIndent, MOBI6, kindleResourceRegex, kindlePosRegex, parseResourceURI, parsePosURI, makePosURI, getFragmentSelector, replaceSeries2, getPageSpread2, KF8;
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:3359:        getTOCFragment(doc, id) {
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:3381:      getFragmentSelector = (str) => {
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:3610:              const selector = getFragmentSelector(str);
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:3611:              this.#setFragmentSelector(frag.index, offset2, selector);
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:3642:        #setFragmentSelector(id, offset, selector) {
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:3662:          const selector = getFragmentSelector(str);
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:3663:          this.#setFragmentSelector(fid, off, selector);
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:3672:        getTOCFragment(doc, { fid, off }) {
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:5828:  var NS2, blockTags, getLang, getAlphabet, getSegmenter, fragmentToSSML, getFragmentWithMarks, rangeIsEmpty, ListIterator, TTS;
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:5946:      getFragmentWithMarks = (range, textWalker2, granularity) => {
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:6030:            const { entries, ssml } = getFragmentWithMarks(range, textWalker2, granularity);
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:6112:    async init({ toc, ids, splitHref, getFragment }) {
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:6129:      this.getFragment = getFragment;
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:6141:        const el = this.getFragment(doc, fragment);
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:6661:      if (book.splitTOCHref && book.getTOCFragment) {
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:6665:        const getFragment = book.getTOCFragment.bind(book);
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:6671:          getFragment
android/app/src/androidTest/assets/foliate-spike/foliate-bundle.js:6678:          getFragment
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:78:     *  (e.g. the reader's onStop position flush — it must finish even as the activity
android/app/src/main/kotlin/com/vreader/app/search/SearchScreen.kt:208:            items(recents, key = { "recent-$it" }) { r -> RecentRow(query = r, onTap = { onRecentTap(r) }) }
android/app/src/main/kotlin/com/vreader/app/search/SearchScreen.kt:292:        items(state.results, key = { it.book.fingerprintKey }) { row ->
android/app/src/main/kotlin/com/vreader/app/library/CollectionShelfBar.kt:45:        items(collections, key = { it.id }) { c ->
android/app/src/main/kotlin/com/vreader/app/library/LibraryScreen.kt:179:        items(books, key = { it.id }) { book ->
android/app/src/main/kotlin/com/vreader/app/library/LibraryScreen.kt:226:        items(books, key = { it.id }) { book ->
android/app/src/test/kotlin/com/vreader/app/reader/nav/ReadiumTocProviderTest.kt:145:    fun duplicateHrefs_differentFragments_yieldDistinctEntries() = runTest {
android/app/src/androidTest/kotlin/com/vreader/app/tts/TtsControlBarTest.kt:24:                onPlayPause = { pp = true }, onNext = { nx = true }, onPrevious = { pv = true }, onStop = { st = true },
android/app/src/main/kotlin/com/vreader/app/search/EpubTextExtractor.kt:202:        val noFragment = href.substringBefore('#')
android/app/src/main/kotlin/com/vreader/app/search/EpubTextExtractor.kt:204:            java.net.URLDecoder.decode(noFragment, Charsets.UTF_8.name())
android/app/src/main/kotlin/com/vreader/app/search/EpubTextExtractor.kt:206:            noFragment
android/app/src/main/kotlin/com/vreader/app/ai/AiChatPanel.kt:112:            items(AiChatUiState.SUGGESTED_PROMPTS) { p ->
android/app/src/main/kotlin/com/vreader/app/ai/AiChatPanel.kt:118:        items(state.messages) { m -> MessageRow(m) }
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubFindInBookTest.kt:22: * #128 FTS index. Instrumented because Readium's EpubNavigatorFragment renders in a REAL WebView (not
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubFindInBookTest.kt:35: * The live Readium `SearchIterator` is disposed on dismiss + onDestroy (the WI-8 `closeAllEpubCursors`
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubFindInBookTest.kt:43: * only the cursor dispose), so this layer asserts VM survival, not a false Idle. The onDestroy path runs through
android/app/src/main/kotlin/com/vreader/app/tts/TtsControlBar.kt:48:    onStop: () -> Unit = {},
android/app/src/main/kotlin/com/vreader/app/tts/TtsControlBar.kt:66:        else TransportLayout(state, onPlayPause, onPrevious, onNext, onStop, onSpeed, onVoice)
android/app/src/main/kotlin/com/vreader/app/tts/TtsControlBar.kt:73:    onStop: () -> Unit, onSpeed: () -> Unit, onVoice: () -> Unit,
android/app/src/main/kotlin/com/vreader/app/tts/TtsControlBar.kt:101:            IconBtn(Icons.Filled.Close, "Stop read-aloud", c.Ink, onStop, "tts-stop")
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderScreen.kt:120:            items(count = document.pageCount, key = { it }) { i -> PdfPage(document, i) }
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderScreen.kt:159:    currentLocator: vreader.contracts.Locator? = null,
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderScreen.kt:188:            currentLocator = currentLocator,
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubBookmarkNavTest.kt:20: * Feature #135 WI-7 — the EPUB bookmark host wiring, instrumented because Readium's EpubNavigatorFragment
android/app/src/androidTest/kotlin/com/vreader/app/reader/TxtReaderActivityTest.kt:33:class TxtReaderActivityTest {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderHighlightController.kt:1:// Purpose: feature #123 WI-3 — wraps Readium's selection + decoration APIs (EpubNavigatorFragment
android/app/src/main/kotlin/com/vreader/app/reader/ReaderHighlightController.kt:12:import org.readium.r2.navigator.epub.EpubNavigatorFragment
android/app/src/main/kotlin/com/vreader/app/reader/ReaderHighlightController.kt:17:class ReaderHighlightController(private val navigator: EpubNavigatorFragment) {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt:4:// EpubNavigatorFragment View under the chrome, not a Compose body), so it cannot reuse the Compose-native
android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt:43: * read from the navigator's `currentLocator`) to [tocIndexFor].
android/app/src/test/kotlin/com/vreader/app/reader/Azw3DisplayCssTest.kt:156:    // FoliateBridge.setStyles runs through evaluateJavascript) wraps the CSS in a JSON-encoded literal.
android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderChromeConnectedTest.kt:19: * the Readium EpubNavigatorFragment. Instrumented because the navigator resolves its TOC + reading
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubDisplaySettingsConnectedTest.kt:19: * EpubNavigatorFragment resolves its settings against a real WebView (not Robolectric). Seeds a
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubDisplaySettingsConnectedTest.kt:22: * theme mid-read and asserts the accepted background updates (live re-submission via submitPreferences).
android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeScaffold.kt:22:// (host wiring feeds the data in WI-7). [currentLocator] is threaded for the host to derive presence but the
android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeScaffold.kt:81: * Contents/Notes-only callers stay valid). [currentLocator] is the current reading position the host uses
android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeScaffold.kt:116:    currentLocator: Locator? = null,
android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderActivityTest.kt:18: * EpubNavigatorFragment renders in a real WebView (not Robolectric). Imports the
android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderActivityTest.kt:24:class ReaderActivityTest {
android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderActivityTest.kt:63:            // Background the reader → onStop flushes the current position synchronously.
android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderActivityTest.kt:72:            assertTrue("onStop flushed a reading position to Room", saved)
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:2:// EpubNavigatorFragment in scroll mode (Spike-B-verified), opening the stored EPUB
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:7:// EpubNavigatorFragment View under the chrome, not a Compose body) and the ONLY TOC-supplying host, so it
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:26:// disposed in onDestroy (onCleared → closeAllEpubCursors) BEFORE the publication closes, so the live Readium
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:88:import org.readium.r2.navigator.epub.EpubNavigatorFragment
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:101:class ReaderActivity : AppCompatActivity() {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:110:    private var navigator: EpubNavigatorFragment? = null
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:111:    private var publication: Publication? = null   // host-owned; closed in onDestroy
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:126:    // read from the navigator's currentLocator totalProgression (EPUB scroll mode).
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:149:    // onDestroy (`onCleared` → closeAllEpubCursors, so the live Readium SearchIterator never leaks). The sheet
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:168:        // The navigator fragment can't be restored before its FragmentFactory is set,
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:205:            // released in onDestroy; the activity recreates fresh on return).
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:206:            val nav: EpubNavigatorFragment? = withStarted {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:207:                if (supportFragmentManager.isStateSaved) return@withStarted null
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:208:                supportFragmentManager.fragmentFactory = factory.createFragmentFactory(
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:211:                    listener = object : EpubNavigatorFragment.Listener {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:214:                    configuration = EpubNavigatorFragment.Configuration().apply {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:219:                supportFragmentManager.commitNow {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:220:                    add(containerId, EpubNavigatorFragment::class.java, Bundle(), READER_TAG)
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:222:                supportFragmentManager.findFragmentByTag(READER_TAG) as EpubNavigatorFragment
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:252:     *  render the sheet. The VM's collectors run on [lifecycleScope]; it is disposed in [onDestroy]
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:268:    private suspend fun populateChromeModel(pub: Publication, current: Book, nav: EpubNavigatorFragment) {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:272:        val locator = nav.currentLocator.value
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:347:     *  first apply). Proves the reopen-render path ran against the real EpubNavigatorFragment. */
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:379:        override fun onDestroyActionMode(mode: ActionMode?) {}
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:444:    override fun onStop() {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:445:        super.onStop()
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:451:        val locator = nav.currentLocator.value
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:455:    override fun onDestroy() {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:456:        super.onDestroy()
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:463:        // fragment is torn down by super.onDestroy() above, then we release it.
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:482:    private fun observeDisplaySettings(nav: EpubNavigatorFragment) {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:485:                runCatching { nav.submitPreferences(EpubPreferences(scroll = true) + settings.toEpubPreferences()) }
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:486:                    .onFailure { android.util.Log.w("ReaderActivity", "submitPreferences failed; display change not applied", it) }
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:494:    private fun observePosition(nav: EpubNavigatorFragment, current: Book) {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:496:            nav.currentLocator
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:502:            nav.currentLocator.collect { locator ->
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:620:     *  body is a View (EpubNavigatorFragment), NOT a composable, the chrome cannot use the Compose-native
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:729:        val current = nav.currentLocator.value
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:849:    fun currentHref(): String? = navigator?.currentLocator?.value?.href?.toString()
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:897:     *  Proves the Display setting reached and was resolved by the live EpubNavigatorFragment — it does
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:955: * `currentLocator` as plain values so this stays pure/JVM-testable — the same thin-Readium-hop posture as
android/app/src/androidTest/kotlin/com/vreader/app/reader/foliate/FoliateSpikeHarnessTest.kt:133:        InstrumentationRegistry.getInstrumentation().runOnMainSync { wv.evaluateJavascript(js, null) }
android/app/src/main/kotlin/com/vreader/app/reader/EpubPreferencesMapper.kt:11:// @coordinates-with: ReaderActivity.kt (submits the mapped prefs live via submitPreferences()),
android/app/src/main/kotlin/com/vreader/app/reader/EpubReaderChrome.kt:2:// (ReaderActivity). The EPUB host is the outlier: a Readium EpubNavigatorFragment (a View) renders the
android/app/src/main/kotlin/com/vreader/app/reader/foliate/Azw3Document.kt:3:// state + the latest position (main-thread-owned, so the Activity's onStop can flush synchronously).
android/app/src/main/kotlin/com/vreader/app/reader/foliate/Azw3Document.kt:45:    /** The latest position foliate reported, main-thread-owned so onStop can flush it synchronously. */
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:6:// DisposableEffect; the page index is saved (debounced + onStop flush) via a conflated,
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:72:    // Hoisted so onStop can flush the latest page synchronously (mirrors TxtReaderActivity).
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:82:    // serialized (latest-wins) — the debounced save + the onStop flush never land out of order.
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:91:        // The lone writer — drains in order; runs on the process scope so an onStop save
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:92:        // completes through teardown; ends when onDestroy closes the channel.
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:209:                            currentLocator = liveCanonical,
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:228:    override fun onStop() {
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:229:        super.onStop()
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:233:    override fun onDestroy() {
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:234:        super.onDestroy()
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:7:// VReaderLocator.wrapLegacy envelope (debounced + onStop flush) and restore it via
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:158:class TxtReaderActivity : ComponentActivity() {
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:162:    // Hoisted out of composition so onStop can flush the latest position synchronously
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:163:    // (mirrors ReaderActivity's onStop flush). Set once the document is loaded.
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:172:    // saves are serialized (latest-wins) — the debounced save and the onStop flush can
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:183:        // pending one. Runs on the process scope so an onStop save completes through
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:184:        // teardown; ends when onDestroy closes the channel.
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:221:                        // onStop flush — captures the live list state + book/document.
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:402:                            currentLocator = liveCanonical,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:467:                                    onPrevious = ttsVm::previous, onNext = ttsVm::next, onStop = ttsVm::stop,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:587:    override fun onStop() {
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:588:        super.onStop()
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:592:    override fun onDestroy() {
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:593:        super.onDestroy()
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:853:    currentLocator: vreader.contracts.Locator? = null,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:881:            currentLocator = currentLocator,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:987:private fun TxtBody(
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1043:        items(count = document.chunkCount, key = { it }) { i ->
android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateBridge.kt:83:        // the OS freezer can suspend it after a few idle seconds, so a page-turn (evaluateJavascript)
android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateBridge.kt:161:     *  `evaluateJavascript` runs (no test-vs-production drift). Mirrors iOS Foliate `setStyles`. */
android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateBridge.kt:166:    private fun eval(js: String) = webView.evaluateJavascript(js, null)
android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateBridge.kt:303: * seam [FoliateBridge.setStyles] runs through `evaluateJavascript`, so the escaping the unit test pins
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:6:// + flushes on onStop, and recreates the WebView on render-process death.
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:98:    // Hoisted so onStop can flush the latest position synchronously (mirrors PdfReaderActivity).
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:108:        // The lone position writer — drains in order on the process scope so an onStop save survives
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:186:                        currentLocator = currentCanonical,
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:246:    override fun onStop() {
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:247:        super.onStop()
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:255:    override fun onDestroy() {
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:256:        super.onDestroy()
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:454:    currentLocator: Locator? = null,
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:484:            currentLocator = currentLocator,

exec
/bin/zsh -lc "sed -n '90,240p' android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt
sed -n '430,530p' android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt
sed -n '150,250p' android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt
sed -n '970,1075p' android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt
sed -n '1,240p' android/app/src/main/kotlin/com/vreader/app/ai/AiClient.kt
sed -n '1,220p' android/app/src/main/kotlin/com/vreader/app/ai/AiProviderFactory.kt
sed -n '1,260p' android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt" in /Users/ll/workspace/vreader
 succeeded in 0ms:
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.io.File
import vreader.contracts.Locator as CanonicalLocator

@OptIn(ExperimentalReadiumApi::class)
class ReaderActivity : AppCompatActivity() {

    private val container get() = (application as VReaderApp).container
    private val repository: LibraryRepository get() = container.repository
    private val bridge = ReadiumLocatorBridge()

    private val annotations: AnnotationsRepository get() = container.annotationsRepository

    private var containerId: Int = 0
    private var navigator: EpubNavigatorFragment? = null
    private var publication: Publication? = null   // host-owned; closed in onDestroy
    private var book: Book? = null

    // feature #132 WI-7-EPUB — the persistent chrome model the top/bottom bands + sheet layer collect,
    // populated as the async open completes and updated on every position change. The active Display
    // theme (also read by the chrome bands' colors) is mirrored so the ComposeViews can render immediately.
    private val chromeModel = MutableStateFlow(ReaderChromeModel())
    private val chromeTheme = mutableStateOf(ReaderTheme.Paper)
    // The hoisted top/bottom-visibility + open-sheet state (a Compose snapshot state, so the ComposeViews
    // recompose on change). Kept in-memory for the reader's lifetime (rotation always starts fresh — see
    // onCreate's super.onCreate(null)).
    private val chromeState = mutableStateOf(ReaderChromeState())
    // feature #129 — whether the Display settings sheet is open (opened from the bottom band's Aa slot).
    private val showDisplaySheet = mutableStateOf(false)
    // feature #132 WI-7-EPUB — the live reading fraction (0..1) for the bottom band's progress scrubber,
    // read from the navigator's currentLocator totalProgression (EPUB scroll mode).
    private val chromeProgress = mutableStateOf(0f)
    // feature #134 WI-5 — the More menu's Book-details model (null until the book loads AND its collection
    // names are read → the More button is omitted until then; no dead control). Rebuilt on collection change.
    private val chromeBookDetails = mutableStateOf<com.vreader.app.reader.details.BookDetailsUiModel?>(null)

    // feature #135 WI-7 — the top-bar bookmark toggle state + the Bookmarks-tab rows the chrome bands read.
    // isCurrentBookmarked drives the filled/outline glyph; it is refreshed on every position change AND right
    // after a toggle. currentCanonical is the live reading position mapped to canonical (the equality basis
    // for presence/create). bookmarkRows is the projected List<BookmarkRowItem> (observeBookmarks → WI-4
    // projection with a BookmarkTocIndex built ONCE per TOC). All in-memory for the reader's lifetime.
    private val isCurrentBookmarked = mutableStateOf(false)
    private val bookmarkRows = mutableStateOf<List<BookmarkRowItem>>(emptyList())
    // The live reading position as a canonical Locator (null until the navigator has a locator). Read on the
    // main thread; the toggle/presence reads snapshot it.
    @Volatile private var currentCanonical: CanonicalLocator? = null
    // The bookmark TOC index, built ONCE from the flattened TOC when the publication opens (WI-4 design —
    // the host owns index construction), reused across every projected row.
    @Volatile private var bookmarkTocIndex: BookmarkTocIndex? = null
    private val bookmarkDate = bookmarkDateRenderer()

    // feature #133 WI-11 — the in-book search VM (ONE per reader session), built once the publication opens
    // over the LIVE Readium publication (Readium's own SearchService — NOT the FTS index). Disposed in
    // onDestroy (`onCleared` → closeAllEpubCursors, so the live Readium SearchIterator never leaks). The sheet
    // renders in the sheetLayer ComposeView; the Search-icon presence follows the VM's `hidesSearchEntry`.
    private var inBookSearchVm: InBookSearchViewModel? = null
    private val inBookSearchState = mutableStateOf<com.vreader.app.search.InBookSearchScreenState?>(null)
    private val showSearchSheet = mutableStateOf(false)
    // How many times the per-session search VM has been constructed — a test seam proving exactly ONE is
    // built per reader open (never a fresh one per query/recomposition — the WI-8 one-per-session contract).
    @Volatile private var inBookSearchVmBuildCount: Int = 0

    // feature #123 — in-reader highlighting
    private var highlightController: ReaderHighlightController? = null
    private val popoverVm = SelectionPopoverViewModel()
    // the Readium locator of the live selection (create context: set on a fresh selection)
    private var pendingSelection: Locator? = null
    // edit context: the existing highlight being edited (set on a decoration tap) + its text for copy/share
    private var pendingHighlightId: String? = null
    private var pendingSelectedText: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // The navigator fragment can't be restored before its FragmentFactory is set,
        // and we set the factory only after the async open completes — so always start
        // fresh (the saved reading position is what actually persists across recreation).
        super.onCreate(null)

        val key = intent.getStringExtra(EXTRA_FINGERPRINT_KEY)
        if (key == null) { finish(); return }
        setContentView(buildChrome())

        // feature #132 WI-7-EPUB — the chrome band colors follow the user's stored Display theme (open-time
        // value + live updates), mirroring how observeDisplaySettings feeds the navigator.
        lifecycleScope.launch {
            container.readerSettingsStore.settings.collect { chromeTheme.value = it.theme }
        }

        lifecycleScope.launch {
            val loaded = repository.findBook(key)
            if (loaded?.localFilePath == null) { finish(); return@launch }
            book = loaded
            // Seed the chrome model title immediately (TOC + annotations arrive once the publication opens).
            chromeModel.value = chromeModel.value.copy(title = loaded.title)

            val pub = try {
                BookOpener(this@ReaderActivity).open(File(loaded.localFilePath!!))
            } catch (e: BookOpenException) {
                finish(); return@launch
            }
            publication = pub

            val initial = computeInitialLocator(key)
            // feature #129 WI-5 — open with the user's stored Display settings already applied (so a
            // non-default theme/typography renders on first paint, no flash), keeping the scroll layout.
            val initialPrefs = EpubPreferences(scroll = true) + container.readerSettingsStore.current().toEpubPreferences()
            val factory = EpubNavigatorFactory(pub)
            // Attach only when the activity is at least STARTED AND its fragment state
            // isn't already saved — `commitNow` against a state-saved manager throws
            // IllegalStateException. If we can't commit, abort (the publication is
            // released in onDestroy; the activity recreates fresh on return).
            val nav: EpubNavigatorFragment? = withStarted {
                if (supportFragmentManager.isStateSaved) return@withStarted null
                supportFragmentManager.fragmentFactory = factory.createFragmentFactory(
                    initialLocator = initial,
                    initialPreferences = initialPrefs,
                    listener = object : EpubNavigatorFragment.Listener {
                        override fun onExternalLinkActivated(url: AbsoluteUrl) {}
                    },
                    configuration = EpubNavigatorFragment.Configuration().apply {
                        // intercept the system selection menu → show the designed floating popover instead.
                        selectionActionModeCallback = selectionCallback()
                    },
                )
                supportFragmentManager.commitNow {
                    add(containerId, EpubNavigatorFragment::class.java, Bundle(), READER_TAG)
                }
                supportFragmentManager.findFragmentByTag(READER_TAG) as EpubNavigatorFragment
            }
            if (nav == null) { finish(); return@launch }
            navigator = nav
            val controller = ReaderHighlightController(nav)
            highlightController = controller
            repository.markOpened(key, System.currentTimeMillis())
            // feature #132 WI-7-EPUB — build the chrome model once the publication is open: the flattened
            // TOC (each entry retaining its native Readium locator for the jump), the Notes snapshot, and
            // the initial highlighted-chapter index for the current reading position.
            populateChromeModel(pub, loaded, nav)
            // feature #135 WI-7 — build the bookmark TOC index ONCE from the flattened TOC (WI-4 design),
            // then observe this book's bookmarks (project → rows) + keep the top-bar presence in sync.
            bookmarkTocIndex = BookmarkTocIndex.build(chromeModel.value.tocEntries)
            observeBookmarks(loaded)
            observePosition(nav, loaded)
            observeDisplaySettings(nav)
            observeHighlights(loaded, controller)
            observeAnnotationsSnapshot(loaded)
        val text = selectedTextForAction() ?: return
        val send = Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }
        startActivity(Intent.createChooser(send, null))
        clearSelectionAndDismiss()
    }

    private fun clearSelectionAndDismiss() {
        highlightController?.clearSelection()
        pendingSelection = null
        pendingHighlightId = null
        pendingSelectedText = null
        popoverVm.dismiss()
    }

    override fun onStop() {
        super.onStop()
        // Synchronous-intent flush: the last movement inside the debounce window would
        // otherwise be lost on back/home/rotation. Launched on the process scope so it
        // completes even as this activity is torn down.
        val nav = navigator ?: return
        val current = book ?: return
        val locator = nav.currentLocator.value
        container.appScope.launch { persist(locator, current) }
    }

    override fun onDestroy() {
        super.onDestroy()
        // feature #133 WI-11 — dispose the in-book search VM (its onCleared disposes the live Readium
        // SearchIterator via closeAllEpubCursors) BEFORE releasing the publication it searches over — the
        // iterator is a view over the publication, so it must go first (no leak, no use-after-close).
        inBookSearchVm?.onCleared()
        inBookSearchVm = null
        // Host owns the Publication (Readium's navigator does not close it). The
        // fragment is torn down by super.onDestroy() above, then we release it.
        publication?.close()
        publication = null
    }

    /** Restore precisely from the saved Readium locator; canonical-fallback (progression) is a follow-on. */
    private suspend fun computeInitialLocator(key: String): Locator? {
        val saved = repository.loadPosition(key) ?: return null
        return when (val target = ResumeResolver.resolve(saved)) {
            is ResumeTarget.Precise -> runCatching { Locator.fromJSON(JSONObject(target.readiumLocatorJSON)) }.getOrNull()
            else -> null
        }
    }

    /** feature #129 WI-5 — apply the live "Display" settings to the navigator: re-submit Readium
     *  EpubPreferences (typography + per-theme colors) on every change so a settings edit updates the
     *  open reader immediately. Scroll layout is preserved (WI-5 owns typography/theme only). The
     *  open-time value is already applied via `initialPrefs`; re-submitting the same value is a cheap
     *  no-op, so we don't drop the first emission (keeps the render authoritative). */
    private fun observeDisplaySettings(nav: EpubNavigatorFragment) {
        lifecycleScope.launch {
            container.readerSettingsStore.settings.collect { settings ->
                runCatching { nav.submitPreferences(EpubPreferences(scroll = true) + settings.toEpubPreferences()) }
                    .onFailure { android.util.Log.w("ReaderActivity", "submitPreferences failed; display change not applied", it) }
            }
        }
    }

    /** Save the current Readium position as a VReaderLocator envelope (debounced steady-state) AND keep the
     *  chrome model's highlighted-chapter index in sync as the reader scrolls (prompt, un-debounced — the
     *  Contents-sheet highlight should track the live position, and tocIndexFor is a cheap pure map). */
    private fun observePosition(nav: EpubNavigatorFragment, current: Book) {
        lifecycleScope.launch {
            nav.currentLocator
                .drop(1)            // skip the initial emission
                .debounce(1_000)
                .collect { locator -> persist(locator, current) }
        }
        lifecycleScope.launch {
            nav.currentLocator.collect { locator ->
                val model = chromeModel.value
                val index = tocIndexFor(locator.href.toString(), locator.locations.progression, tocPositions(model.tocEntries))
                if (index != model.currentTocIndex) {
                    chromeModel.value = chromeModel.value.copy(currentTocIndex = index)
                }
                chromeProgress.value = (locator.locations.totalProgression ?: 0.0).toFloat().coerceIn(0f, 1f)
                // feature #135 WI-7 — map the live Readium position to canonical (the toggle's equality
                // basis) + refresh the top-bar filled/outline presence as the reader scrolls.
                val canonical = canonicalForCurrent(locator, current)
                currentCanonical = canonical
                isCurrentBookmarked.value = canonical != null &&
                    runCatching { annotations.isBookmarked(current.fingerprintKey, canonical) }.getOrDefault(false)
            }
        }
    }

    /** feature #135 WI-7 — the live Readium position → canonical [CanonicalLocator] (the bookmark equality
     *  basis). Extracts the plain values (href + progression + totalProgression + cfi) off the Readium
     *  locator here (the thin Readium hop) and hands them to the pure [epubBookmarkLocator]. */
    private fun canonicalForCurrent(locator: Locator, current: Book): CanonicalLocator? {
        val href = locator.href.toString().takeIf { it.isNotBlank() } ?: return null
        val cfi = locator.locations.fragments.firstOrNull { it.startsWith("epubcfi(") }
        return runCatching {
            epubBookmarkLocator(
                href = href,
                progression = locator.locations.progression,
                totalProgression = locator.locations.totalProgression,
                cfi = cfi,
    data class Loaded(
        val title: String,
        val document: TxtDocument,
        val book: Book,
        val initialIndex: Int,
    ) : TxtUiState
}

class TxtReaderActivity : ComponentActivity() {

    private val container get() = (application as VReaderApp).container

    // Hoisted out of composition so onStop can flush the latest position synchronously
    // (mirrors ReaderActivity's onStop flush). Set once the document is loaded.
    private var flushPosition: (() -> Unit)? = null

    // feature #124 WI-4 — the existing TXT highlight being edited (set on a tap; null = create context)
    // + the text to copy/share (the selection's, or the tapped highlight's).
    private var pendingTxtHighlightId: String? = null
    private var pendingTxtText: String? = null

    // ALL position writes funnel through this CONFLATED channel + a SINGLE consumer, so
    // saves are serialized (latest-wins) — the debounced save and the onStop flush can
    // never land out of order and regress the position (Gate-4 High).
    private val saveRequests = Channel<PendingSave>(Channel.CONFLATED)
    private data class PendingSave(val book: Book, val offsetUtf16: Int)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val key = intent.getStringExtra(EXTRA_FINGERPRINT_KEY)
        if (key == null) { finish(); return }

        // The lone writer — drains requests in order; CONFLATED keeps only the latest
        // pending one. Runs on the process scope so an onStop save completes through
        // teardown; ends when onDestroy closes the channel.
        container.appScope.launch {
            for ((book, offset) in saveRequests) {
                val locator = Locator(
                    contentSHA256 = book.contentSHA256,
                    fileByteCount = book.fileByteCount,
                    format = book.originalFormat.name,
                    charOffsetUTF16 = offset,
                )
                container.repository.savePosition(
                    vreader.contracts.VReaderLocator.wrapLegacy(locator),
                    System.currentTimeMillis(),
                )
            }
        }

        setContent {
            VReaderTheme {
                val state by produceState<TxtUiState>(TxtUiState.Loading, key) {
                    value = withContext(Dispatchers.IO) {
                        runCatching { load(key) }.getOrDefault(TxtUiState.Failed)
                    }
                }
                // feature #129 — the live Display settings (theme/font/size/spacing/margin). NULL until
                // the DataStore's first emission; the reader body is withheld until then (Gate-4 Medium:
                // rendering defaults first would flash the wrong theme/typography for a user with stored
                // non-default settings). The empty loading scaffold is the only pre-emission surface.
                val settingsOrNull by container.readerSettingsStore.settings
                    .collectAsStateWithLifecycle(initialValue = null)
                val gated = if (settingsOrNull == null && state !is TxtUiState.Failed) TxtUiState.Loading else state
                when (val s = gated) {
                    is TxtUiState.Failed -> LaunchedEffect(Unit) { finish() }
                    is TxtUiState.Loading -> TxtLoadingScaffold((settingsOrNull ?: ReaderSettings()).theme)
                    is TxtUiState.Loaded -> {
                        // non-null by the gate above (Loaded is unreachable pre-emission).
                        val displaySettings = checkNotNull(settingsOrNull)
                        val listState = rememberLazyListState(initialFirstVisibleItemIndex = s.initialIndex)
                        // onStop flush — captures the live list state + book/document.
                        SideEffect {
                            flushPosition = { savePosition(s.book, s.document, listState.firstVisibleItemIndex) }
                        }
                        // Debounced steady-state save as the user scrolls.
                        LaunchedEffect(listState, s.document) {
                            snapshotFlow { listState.firstVisibleItemIndex }
                                .drop(1)
                                .debounce(1_000)
                                .collect { savePosition(s.book, s.document, it) }
                        }
                        // feature #121 — read-aloud. The VM drives the designed control bar; the spoken
                        // sentence is washed + auto-scrolled (TXT). Chunking is LAZY + off-main (only
                        // on Read aloud) so a large book never scans the whole text on composition.
                        val ttsVm: TtsViewModel = viewModel(factory = viewModelFactory {
                            initializer { TtsViewModel(AndroidTtsEngine(applicationContext)) }
                        })
                        val tts by ttsVm.state.collectAsStateWithLifecycle()
                        val ttsScope = rememberCoroutineScope()
                        LaunchedEffect(ttsVm) { ttsVm.intents.collect { launchTtsIntent(it) } }
                        // pause read-aloud when the reader is backgrounded (no MediaSession by design —
                        // plan §OOS); the engine is shut down on Activity finish via the VM's onCleared.
                        val lifecycleOwner = LocalLifecycleOwner.current
                        DisposableEffect(lifecycleOwner) {
                            // guard against ON_STOP firing on a rotation (config change) — the VM is
                            // retained across rotation, so don't pause when we're just reconfiguring.
                            val obs = LifecycleEventObserver { _, e -> if (e == Lifecycle.Event.ON_STOP && !isChangingConfigurations) ttsVm.pause() }
                            lifecycleOwner.lifecycle.addObserver(obs)
                            onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
                        }
            .clip(RoundedCornerShape(14.dp))
            .clickable(enabled = enabled, onClick = onReadAloud)
            .padding(horizontal = 12.dp, vertical = 4.dp)
            .testTag("tts-read-aloud-entry"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Icon(Icons.AutoMirrored.Filled.VolumeUp, contentDescription = "Read aloud", tint = tint, modifier = Modifier.size(24.dp))
        // accent label when enabled — the committed TtsEntry active treatment (pre-#129 TtsEntryBar parity).
        Text("Read aloud", color = tint, fontFamily = VReaderFonts.Sans, fontSize = 10.sp, fontWeight = FontWeight.Medium)
    }
}

/** The reading body — a LazyColumn over the document's chunk ranges. For BookFormat.md each chunk
 *  renders through MarkdownRenderer (styled); else verbatim. [textStyle] + [marginDp] come from the
 *  #129 Display settings (bodyTextStyle + the margin slider). */
@Composable
private fun TxtBody(
    document: TxtDocument, listState: LazyListState, format: BookFormat,
    // feature #125 — the single render owner. MD chunks render via mapper.renderedText so the body's
    // TextLayoutResult matches the controller/wash's offset map exactly (no double render, no drift).
    mapper: ChunkTextMapper,
    textStyle: TextStyle, marginDp: Float,
    highlightSpan: (chunkIndex: Int) -> IntRange? = { null },
    // feature #124 — annotation highlight washes per chunk (TXT only; the activity passes empty for MD).
    washesForChunk: (chunkIndex: Int) -> List<WashSpan> = { emptyList() },
    // feature #124 — TXT custom selection (null = no selection, e.g. MD). onSelectionFinalized fires on
    // long-press-drag release so the host can show the popover.
    selectionController: TxtSelectionController? = null,
    onSelectionFinalized: () -> Unit = {},
    // feature #124 WI-4 — a tap (LazyColumn-local point) → host hit-tests an existing highlight to edit.
    onTapAt: (androidx.compose.ui.geometry.Offset) -> Unit = {},
) {
    val isMarkdown = format == BookFormat.md
    val wash = VReaderColors.Accent.copy(alpha = 0.18f)
    val selectionAccent = Color(0x575C8FC4)   // design selection bg rgba(92,143,196,0.34)
    val selection by (selectionController?.selection ?: flowOf(null)).collectAsState(null)
    // the pointerInput block keys on selectionController (stable), so without this it would capture the
    // INITIAL onTapAt/onSelectionFinalized closures (stale highlightsList → tap-to-edit never hits).
    val currentOnTap by androidx.compose.runtime.rememberUpdatedState(onTapAt)
    val currentOnFinalize by androidx.compose.runtime.rememberUpdatedState(onSelectionFinalized)
    LazyColumn(
        Modifier
            .fillMaxSize()
            .onGloballyPositioned { selectionController?.setLazyCoords(it) }
            .then(
                if (selectionController != null) {
                    // ONE detector distinguishes a TAP (edit an existing highlight) from a LONG-PRESS+drag
                    // (new selection) — two separate pointerInput detectors conflict over the same down event.
                    Modifier.pointerInput(selectionController) {
                        awaitEachGesture {
                            val down = awaitFirstDown(requireUnconsumed = false)
                            val longPress = awaitLongPressOrCancellation(down.id)
                            if (longPress != null) {
                                // long-press → selection; finalize only on a COMPLETED drag/up (not a cancel).
                                selectionController.beginAt(longPress.position)
                                val completed = drag(longPress.id) { change -> selectionController.extendTo(change.position); change.consume() }
                                if (completed) currentOnFinalize() else selectionController.clear()
                            } else if (!down.isConsumed) {
                                // null also means cancel (e.g. a scroll won) — only a TAP leaves the down
                                // unconsumed; a scroll consumes it, so it won't be misread as tap-to-edit.
                                currentOnTap(down.position)
                            }
                        }
                    }
                } else {
                    Modifier
                },
            ),
        state = listState,
        contentPadding = PaddingValues(horizontal = marginDp.dp, vertical = 16.dp),
    ) {
        // Count-based: indices on demand (a newline-dense 14MB file can be 100k+ chunks).
        items(count = document.chunkCount, key = { it }) { i ->
            val raw = document.textForChunk(i).toString()
            // .md → styled markdown spans (no read-aloud span wash — markers shift offsets, plan §OOS).
            // .txt → raw verbatim, with the spoken-sentence span washed when read-aloud is active.
            val span = if (isMarkdown) null else highlightSpan(i)
            val text = when {
                isMarkdown -> mapper.renderedText(i)   // #125: the mapper is the single render owner
                span != null -> buildAnnotatedString {
                    append(raw)
                    val a = span.first.coerceIn(0, raw.length); val b = (span.last + 1).coerceIn(a, raw.length)
                    if (b > a) addStyle(SpanStyle(background = wash), a, b)
                }
                else -> AnnotatedString(raw)
            }
            // annotation washes drawn BEHIND the text (getPathForRange) — separate from the read-aloud span.
            val washes = washesForChunk(i)
            var layout by remember(i) { mutableStateOf<TextLayoutResult?>(null) }
            var coords by remember(i) { mutableStateOf<androidx.compose.ui.layout.LayoutCoordinates?>(null) }
            if (selectionController != null) {
                LaunchedEffect(i, layout, coords) {
                    val l = layout; val c = coords
                    if (l != null && c != null) selectionController.registerChunk(i, l, c)
                }
                DisposableEffect(selectionController, i) { onDispose { selectionController.unregisterChunk(i) } }
            }
            // read `selection` (a State) so a selection change recomposes + redraws the accent.
            val selRange = if (selection != null) selectionController?.selectionForChunk(i) else null
            Text(
                text = text,
                // merge over the material default (the pre-#129 explicit-param behavior) so platform
                // text defaults (letterSpacing etc.) are kept — only the Display settings change.
                style = androidx.compose.material3.LocalTextStyle.current.merge(textStyle),
                onTextLayout = { layout = it },
// Purpose: feature #118 WI-2 (#110 Phase 3) — the AI client seam + the shared HTTP/SSE plumbing.
// `AiClient` mirrors iOS `AIProvider` (stream + one-shot + test-connection); `BaseHttpAiClient` owns
// the POST-over-HttpURLConnection transport (the #116/#117 precedent), the typed-error mapping, the
// bounded streaming loop (cancellation disconnects), and a bounded one-shot read. The provider
// concretes supply only the endpoint path, auth headers, request body, and the per-wire payload
// parse (OpenAI vs Anthropic). The API key + auth headers are NEVER logged.
package com.vreader.app.ai

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.job
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import kotlin.coroutines.coroutineContext

interface AiClient {
    /** Streamed assistant text deltas. Cancelling the collector disconnects the HTTP stream. */
    fun streamChat(request: AiRequest): Flow<AiChunk>
    /** One-shot (non-streamed) completion. */
    suspend fun chat(request: AiRequest): AiResponse
    /** A tiny ping → Ok / typed Fail (the editor's Connection section). */
    suspend fun testConnection(): AiTestResult
}

/** A parsed SSE delta: incremental [text] (or null if this event carries none) + a [done] sentinel. */
data class DeltaParse(val text: String?, val done: Boolean)

abstract class BaseHttpAiClient(
    protected val baseUrl: String,
    protected val apiKey: String,
    protected val model: String,
    protected val temperature: Double,
    protected val maxTokens: Int,
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val connectTimeoutMs: Int = 15_000,
    private val readTimeoutMs: Int = 60_000,
) : AiClient {

    protected abstract val endpointPath: String
    protected abstract fun applyAuth(conn: HttpURLConnection)
    protected abstract fun requestBody(request: AiRequest, stream: Boolean): String
    protected abstract fun parseDelta(event: SseEvent): DeltaParse
    protected abstract fun parseOneShot(json: String): String

    final override fun streamChat(request: AiRequest): Flow<AiChunk> = flow {
        val conn = openPost(requestBody(request, stream = true))
        // Disconnect PROMPTLY on cancellation — otherwise a blocking reader.read() inside the
        // Sequence wouldn't honour cancel until readTimeout (up to 60s). Closing the socket makes
        // the blocked read throw, unwinding immediately.
        val onCancel = coroutineContext.job.invokeOnCompletion { runCatching { conn.disconnect() } }
        try {
            checkStatus(conn)
            var emitted = 0
            var sawTerminal = false
            for (ev in SseEventReader.events(conn.inputStream)) {
                coroutineContext.ensureActive()
                val d = parseDelta(ev)
                if (d.done) { sawTerminal = true; break }
                val text = d.text ?: continue
                emitted += text.length
                if (emitted > MAX_ANSWER_CHARS) throw AiError.Stream("answer exceeds the length limit")
                emit(AiChunk(text))
            }
            // EOF before the terminal sentinel ([DONE] / message_stop) = a dropped/truncated stream,
            // not a clean finish — surface it rather than returning a silent partial answer.
            if (!sawTerminal) { coroutineContext.ensureActive(); throw AiError.Stream("stream ended before its terminal event") }
        } finally {
            onCancel.dispose()
            conn.disconnect()
        }
    }.flowOn(dispatcher)

    final override suspend fun chat(request: AiRequest): AiResponse = withContext(dispatcher) {
        val conn = openPost(requestBody(request, stream = false))
        // Same prompt-cancellation guard as streamChat — a blocking one-shot read shouldn't hang to
        // readTimeout if the caller cancels.
        val onCancel = coroutineContext.job.invokeOnCompletion { runCatching { conn.disconnect() } }
        try {
            checkStatus(conn)
            AiResponse(parseOneShot(conn.inputStream.readBoundedText(MAX_ONESHOT_BYTES)))
        } finally {
            onCancel.dispose()
            conn.disconnect()
        }
    }

    final override suspend fun testConnection(): AiTestResult = try {
        chat(AiRequest(model, listOf(AiMessage(AiRole.user, "ping")), temperature, maxTokens = 8))
        AiTestResult.Ok
    } catch (e: AiError) {
        AiTestResult.Fail(e, e.message ?: "connection failed")
    }

    // ── transport ─────────────────────────────────────────────

    private fun openPost(body: String): HttpURLConnection {
        // Path-dedup (iOS Bug #185): if the base already ends with the endpoint, don't append again.
        val base = baseUrl.trim().trimEnd('/')
        val full = if (base.endsWith(endpointPath)) base else base + endpointPath
        val url = runCatching { URL(full) }.getOrNull() ?: throw AiError.Config("invalid base URL")
        requireSafeScheme(url)  // never send the key over cleartext to a remote host
        val conn = try { url.openConnection() as HttpURLConnection } catch (e: Exception) { throw AiError.Offline }
        try {
            conn.requestMethod = "POST"
            conn.connectTimeout = connectTimeoutMs
            conn.readTimeout = readTimeoutMs
            conn.instanceFollowRedirects = false  // never let HUC silently re-POST/forward the key on a 3xx
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Accept", "text/event-stream")
            applyAuth(conn)  // NEVER logged
            conn.doOutput = true
            conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            return conn
        } catch (e: SocketTimeoutException) {
            conn.disconnect(); throw AiError.Timeout
        } catch (e: IOException) {
            conn.disconnect(); throw AiError.Offline
        }
    }

    /** Map the response status; a 2xx returns, anything else throws a typed error (error body is
     *  bounded-discarded, never fully read). */
    private fun checkStatus(conn: HttpURLConnection) {
        val status = try {
            conn.responseCode
        } catch (e: SocketTimeoutException) {
            throw AiError.Timeout
        } catch (e: IOException) {
            throw AiError.Offline
        }
        if (status / 100 == 2) return
        // Do NOT read the error body — it could block/throw and mask the known status; disconnect
        // (in the caller's finally) tears the connection down.
        throw when (status) {
            401, 403 -> AiError.Auth401
            429 -> AiError.RateLimited429
            else -> AiError.Http(status)
        }
    }

    /** Refuse to send the API key over cleartext http:// to a non-local host (https required;
     *  loopback / the emulator host alias are allowed for local dev + tests). */
    private fun requireSafeScheme(url: URL) {
        if (url.protocol.equals("https", ignoreCase = true)) return
        val host = url.host
        val local = host == "127.0.0.1" || host == "::1" || host.equals("localhost", true) || host == "10.0.2.2"
        if (url.protocol.equals("http", ignoreCase = true) && local) return
        throw AiError.InsecureUrl
    }

    /** Accumulate the bounded body as BYTES, then decode UTF-8 ONCE — so a multibyte (CJK)
     *  character split across a read boundary isn't corrupted. */
    private fun InputStream.readBoundedText(max: Long): String {
        val out = ByteArrayOutputStream()
        val buf = ByteArray(16 * 1024)
        var total = 0L
        use {
            while (true) {
                val n = read(buf)
                if (n < 0) break
                total += n
                if (total > max) throw AiError.Decode("response exceeds the size limit")
                out.write(buf, 0, n)
            }
        }
        return out.toString("UTF-8")
    }

    protected companion object {
        const val MAX_ANSWER_CHARS = 200_000
        const val MAX_ONESHOT_BYTES = 4L * 1024 * 1024
    }
}
// Purpose: feature #118 WI-2 (#110 Phase 3) — builds the right AiClient for a provider profile +
// its decrypted API key. The chat/test request path resolves the active profile from a single
// AiProviderStore.snapshot(), decrypts via apiKey(profile), and calls this — so the client is built
// from one consistent snapshot, never live mid-request reads.
package com.vreader.app.ai

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers

object AiProviderFactory {
    fun create(profile: AiProviderProfile, apiKey: String, dispatcher: CoroutineDispatcher = Dispatchers.IO): AiClient {
        val base = profile.baseUrl.ifBlank { profile.kind.defaultBaseUrl }
        val model = profile.model.ifBlank { profile.kind.defaultModel }
        return when (profile.kind) {
            AiProviderKind.openAiCompatible ->
                OpenAiCompatibleProvider(base, apiKey, model, profile.temperature, profile.maxTokens, dispatcher)
            AiProviderKind.anthropicNative ->
                AnthropicProvider(base, apiKey, model, profile.temperature, profile.maxTokens, dispatcher)
        }
    }
}
// Purpose: feature #118 WI-1 (#110 Phase 3) — persists saved AI provider profiles + the active
// selection. Profile metadata (name/kind/baseUrl/model/temperature/maxTokens) lives in DataStore
// as a JSON list; the API key is kept ONLY as a SecretCipher token (the #116 KeystoreSecretCipher).
// Reuses the #116 WebDavServerStore DataStore+SecretCipher credential pattern, adding an active-id
// and a request-start `snapshot()` (a chat/test reads one consistent profile, not live mid-request
// store reads). The key + auth headers are NEVER logged.
package com.vreader.app.ai

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.vreader.app.backup.net.SecretCipher
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** A saved AI provider. `encryptedApiKey` is a [SecretCipher] token, never plaintext. */
@Serializable
data class AiProviderProfile(
    val id: String,
    val name: String,
    val kind: AiProviderKind,
    val baseUrl: String,
    val model: String,
    val temperature: Double = 0.7,
    val maxTokens: Int = 2048,
    val encryptedApiKey: String,
)

/** A consistent point-in-time view: the profiles + which is active. */
data class AiProviderSnapshot(val profiles: List<AiProviderProfile>, val activeId: String?) {
    val active: AiProviderProfile? get() = profiles.firstOrNull { it.id == activeId }
}

@Serializable
private data class AiStoreState(val profiles: List<AiProviderProfile> = emptyList(), val activeId: String? = null)

class AiProviderStore(
    private val dataStore: DataStore<Preferences>,
    private val cipher: SecretCipher,
    private val json: Json = Json { ignoreUnknownKeys = true; encodeDefaults = true },
) {
    /** One consistent profiles + active-id view (read once at request start). */
    suspend fun snapshot(): AiProviderSnapshot = read(dataStore.data.first()).toSnapshot()

    fun observe(): Flow<AiProviderSnapshot> = dataStore.data.map { read(it).toSnapshot() }

    suspend fun list(): List<AiProviderProfile> = snapshot().profiles

    suspend fun activeProfile(): AiProviderProfile? = snapshot().active

    /**
     * Insert/update a profile by [id]. [apiKey] is the PLAINTEXT to encrypt; pass null on an edit
     * that leaves the key unchanged (the existing ciphertext is kept). A brand-new id REQUIRES a
     * key. The first profile added becomes active. Returns the saved profile (key encrypted).
     */
    suspend fun upsert(
        id: String,
        name: String,
        kind: AiProviderKind,
        baseUrl: String,
        model: String,
        temperature: Double,
        maxTokens: Int,
        apiKey: String?,
    ): AiProviderProfile {
        lateinit var saved: AiProviderProfile
        dataStore.edit { prefs ->
            val cur = read(prefs)
            val existing = cur.profiles.firstOrNull { it.id == id }
            val encrypted = when {
                apiKey != null -> cipher.encrypt(apiKey)
                existing != null -> existing.encryptedApiKey  // unchanged on edit
                else -> throw IllegalArgumentException("a new provider ($id) requires an API key")
            }
            saved = AiProviderProfile(id, name, kind, baseUrl, model, temperature, maxTokens, encrypted)
            val next = cur.profiles.filterNot { it.id == id } + saved
            val activeId = cur.activeId ?: id  // first provider becomes active
            prefs[KEY] = json.encodeToString(AiStoreState(next, activeId))
        }
        return saved
    }

    /** Remove a profile. If it was active, the active selection moves to the first remaining (or null). */
    suspend fun delete(id: String) {
        dataStore.edit { prefs ->
            val cur = read(prefs)
            val next = cur.profiles.filterNot { it.id == id }
            val activeId = if (cur.activeId == id) next.firstOrNull()?.id else cur.activeId
            prefs[KEY] = json.encodeToString(AiStoreState(next, activeId))
        }
    }

    /** Select the active provider (no-op if the id isn't present). */
    suspend fun setActive(id: String) {
        dataStore.edit { prefs ->
            val cur = read(prefs)
            if (cur.profiles.any { it.id == id }) prefs[KEY] = json.encodeToString(cur.copy(activeId = id))
        }
    }

    /** Decrypt the key from a CAPTURED [profile] — snapshot-consistent (no live store read). The
     *  chat/test request path uses THIS with a profile from a single [snapshot], so it can't pair
     *  snapshot metadata with a concurrently-edited/deleted key. */
    fun apiKey(profile: AiProviderProfile): String = cipher.decrypt(profile.encryptedApiKey)

    /** The decrypted API key for [id] via a live read, or null if absent. Convenience for UI flows
     *  that aren't mid-request; the request path should prefer [apiKey] (profile). */
    suspend fun apiKey(id: String): String? =
        list().firstOrNull { it.id == id }?.let { cipher.decrypt(it.encryptedApiKey) }

    private fun read(prefs: Preferences): AiStoreState {
        val raw = prefs[KEY] ?: return AiStoreState()
        return runCatching { json.decodeFromString<AiStoreState>(raw) }.getOrDefault(AiStoreState())
    }

    private fun AiStoreState.toSnapshot() = AiProviderSnapshot(profiles, activeId)

    companion object {
        private val KEY = stringPreferencesKey("ai_providers_json")
    }
}

exec
/bin/zsh -lc "rg -n \"data class AiRequest|sealed class AiError|data class AiResponse|data class AiMessage|enum class AiRole\" android/app/src/main/kotlin/com/vreader/app/ai -C 4
sed -n '1,260p' android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt
sed -n '1,240p' android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt
rg -n \"data class TxtDocument|class TxtDocument|chapter|chunkStart|charOffset|originalFormat\" android/app/src/main/kotlin/com/vreader/app/reader android/app/src/main/kotlin/com/vreader/app -g '*.kt' | head -200" in /Users/ll/workspace/vreader
 succeeded in 0ms:
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-2-// iOS AITypes (AIRequest/AIResponse/AIStreamChunk/AIError). Provider-neutral; the OpenAI vs
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-3-// Anthropic wire differences live in the providers.
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-4-package com.vreader.app.ai
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-5-
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt:6:enum class AiRole { system, user, assistant }
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-7-
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt:8:data class AiMessage(val role: AiRole, val content: String)
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-9-
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-10-/** A chat request. `system` is the system prompt (Anthropic carries it top-level; the OpenAI
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-11- *  provider prepends it as a system message). */
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt:12:data class AiRequest(
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-13-    val model: String,
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-14-    val messages: List<AiMessage>,
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-15-    val temperature: Double,
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-16-    val maxTokens: Int,
--
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-20-/** One streamed delta (the incremental assistant text). */
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-21-data class AiChunk(val deltaText: String)
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-22-
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-23-/** A one-shot (non-streamed) response. */
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt:24:data class AiResponse(val text: String)
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-25-
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-26-/** Typed AI failures (HTTP + transport + protocol). */
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt:27:sealed class AiError(message: String) : Exception(message) {
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-28-    object Auth401 : AiError("authentication failed (401) — check the API key")
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-29-    object RateLimited429 : AiError("rate limited (429) — try again shortly")
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-30-    object Offline : AiError("the provider couldn't be reached")
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt-31-    object Timeout : AiError("the provider took too long to respond")
// Purpose: Room database + schema-versioned migration scaffold — feature #106 WI-3.
// Version 8 is the current schema; v1 was the initial books+positions baseline and
// MIGRATION_1_2 is the worked example of the additive-migration pattern (adds
// books.lastOpenedAt). Subsequent additive migrations: 2→3 daily_reading (#122),
// 3→4 annotations (#123), 4→5 collections (#127), 5→6 books.author (#128 search),
// 6→7 the FTS search index (search_sections + search_sections_fts + search_index_state
// + search_sections_staging, all #128 WI-4), 7→8 the composite UNIQUE (bookKey, profileKey)
// index on `bookmarks` — preceded by an in-migration dedupe of pre-existing duplicate rows so
// the unique index can't fail on a legacy duplicate (feature #135 WI-3). The migration round-trip
// test (VReaderDatabaseMigrationTest) guards them. Future schema changes append a
// Migration(n, n+1) to ALL_MIGRATIONS and bump `version`.
package com.vreader.app.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [
        BookEntity::class, ReadingPositionEntity::class, DailyReadingEntity::class,
        HighlightEntity::class, AnnotationNoteEntity::class, BookmarkEntity::class,
        CollectionEntity::class, BookCollectionCrossRef::class,
        SearchSectionEntity::class, SearchSectionFtsEntity::class,
        SearchIndexStateEntity::class, SearchStagingEntity::class,
    ],
    version = 8,
    exportSchema = true,
)
abstract class VReaderDatabase : RoomDatabase() {
    abstract fun bookDao(): BookDao
    abstract fun readingPositionDao(): ReadingPositionDao
    abstract fun readingStatsDao(): ReadingStatsDao
    abstract fun annotationDao(): AnnotationDao
    abstract fun collectionDao(): CollectionDao
    abstract fun searchDao(): SearchDao

    companion object {
        private const val DB_NAME = "vreader.db"

        /** v1 → v2: add the nullable `lastOpenedAt` recents column to `books`. */
        val MIGRATION_1_2: Migration = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE books ADD COLUMN lastOpenedAt INTEGER")
            }
        }

        /** v2 → v3: feature #122 — add the additive `daily_reading` per-day/per-book stats table +
         *  its bookKey index. No data transform. DDL matches Room's generated schema exactly. */
        val MIGRATION_2_3: Migration = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `daily_reading` (`date` TEXT NOT NULL, `bookKey` TEXT NOT NULL, " +
                        "`minutes` INTEGER NOT NULL, PRIMARY KEY(`date`, `bookKey`))",
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_daily_reading_bookKey` ON `daily_reading` (`bookKey`)")
            }
        }

        /** v3 → v4: feature #123 — add the additive `highlights`, `annotation_notes`, and `bookmarks`
         *  annotation tables (each FK→books ON DELETE CASCADE; highlights has the unique
         *  `(profileKey, anchorKey)` dedupe index). No data transform. DDL matches Room's generated
         *  schema for v4 exactly (the migration test opens the real Room DB, whose structural PRAGMA
         *  validation catches any drift). */
        val MIGRATION_3_4: Migration = object : Migration(3, 4) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `highlights` (`highlightId` TEXT NOT NULL, " +
                        "`bookKey` TEXT NOT NULL, `profileKey` TEXT NOT NULL, `anchorKey` TEXT NOT NULL, " +
                        "`color` TEXT NOT NULL, `selectedText` TEXT NOT NULL, `note` TEXT, " +
                        "`locatorJSON` TEXT NOT NULL, `anchorJSON` TEXT, `createdAt` INTEGER NOT NULL, " +
                        "`updatedAt` INTEGER NOT NULL, PRIMARY KEY(`highlightId`), " +
                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_highlights_bookKey` ON `highlights` (`bookKey`)")
                db.execSQL(
                    "CREATE UNIQUE INDEX IF NOT EXISTS `index_highlights_profileKey_anchorKey` " +
                        "ON `highlights` (`profileKey`, `anchorKey`)",
                )
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `annotation_notes` (`noteId` TEXT NOT NULL, " +
                        "`bookKey` TEXT NOT NULL, `profileKey` TEXT NOT NULL, `content` TEXT NOT NULL, " +
                        "`locatorJSON` TEXT NOT NULL, `anchorJSON` TEXT, `createdAt` INTEGER NOT NULL, " +
                        "`updatedAt` INTEGER NOT NULL, PRIMARY KEY(`noteId`), " +
                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
                )
                db.execSQL(
                    "CREATE INDEX IF NOT EXISTS `index_annotation_notes_bookKey` " +
                        "ON `annotation_notes` (`bookKey`)",
                )
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `bookmarks` (`bookmarkId` TEXT NOT NULL, " +
                        "`bookKey` TEXT NOT NULL, `profileKey` TEXT NOT NULL, `title` TEXT, " +
                        "`locatorJSON` TEXT NOT NULL, `createdAt` INTEGER NOT NULL, " +
                        "`updatedAt` INTEGER NOT NULL, PRIMARY KEY(`bookmarkId`), " +
                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_bookmarks_bookKey` ON `bookmarks` (`bookKey`)")
            }
        }

        /** v4 → v5: feature #127 — add the additive `collections` table (unique `nameKey` index) +
         *  the `book_collection` many-to-many join (composite PK, both FKs ON DELETE CASCADE, a
         *  `collectionId` index for the reverse lookup). No data transform. DDL matches Room's generated
         *  v5 schema exactly (the migration test opens the real Room DB, whose structural PRAGMA
         *  validation catches any drift). */
        val MIGRATION_4_5: Migration = object : Migration(4, 5) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `collections` (`id` TEXT NOT NULL, `name` TEXT NOT NULL, " +
                        "`nameKey` TEXT NOT NULL, `createdAt` INTEGER NOT NULL, PRIMARY KEY(`id`))",
                )
                db.execSQL(
                    "CREATE UNIQUE INDEX IF NOT EXISTS `index_collections_nameKey` ON `collections` (`nameKey`)",
                )
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `book_collection` (`bookKey` TEXT NOT NULL, " +
                        "`collectionId` TEXT NOT NULL, PRIMARY KEY(`bookKey`, `collectionId`), " +
                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE , " +
                        "FOREIGN KEY(`collectionId`) REFERENCES `collections`(`id`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
                )
                db.execSQL(
                    "CREATE INDEX IF NOT EXISTS `index_book_collection_collectionId` " +
                        "ON `book_collection` (`collectionId`)",
                )
            }
        }

        /** v5 → v6: feature #128 — add the nullable `author` column to `books` (library search).
         *  Purely additive; migrated rows read `author = null` until a backfill or restore sets it. */
        val MIGRATION_5_6: Migration = object : Migration(5, 6) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE books ADD COLUMN author TEXT")
            }
        }

        /** v6 → v7: feature #128 WI-4 — add the cross-book search index (all in the one `vreader.db`):
         *  `search_sections` (+ bookKey index + FK→books CASCADE), its FTS4/unicode61 content-table
         *  shadow `search_sections_fts`, `search_index_state` (+ FK→books CASCADE), and the transient
         *  `search_sections_staging` buffer (+ bookKey index + FK→books CASCADE). The migration ships
         *  the base + FTS VIRTUAL tables only; Room recreates the FTS content-table sync triggers when
         *  it opens the DB. DDL matches Room's generated v7 schema exactly (the migration test opens the
         *  real Room DB, whose structural PRAGMA validation catches any drift). No data transform. */
        val MIGRATION_6_7: Migration = object : Migration(6, 7) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `search_sections` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                        "`bookKey` TEXT NOT NULL, `sectionIndex` INTEGER NOT NULL, `chunkOrdinal` INTEGER NOT NULL, " +
                        "`sectionTitle` TEXT, `text` TEXT NOT NULL, `indexedText` TEXT NOT NULL, " +
                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_search_sections_bookKey` ON `search_sections` (`bookKey`)")
                db.execSQL(
                    "CREATE VIRTUAL TABLE IF NOT EXISTS `search_sections_fts` USING FTS4(" +
                        "`indexedText` TEXT NOT NULL, tokenize=unicode61, content=`search_sections`)",
                )
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `search_index_state` (`bookKey` TEXT NOT NULL, " +
                        "`indexerVersion` INTEGER NOT NULL, `indexedAt` INTEGER NOT NULL, `status` TEXT NOT NULL, " +
                        "PRIMARY KEY(`bookKey`), FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
                )
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `search_sections_staging` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                        "`bookKey` TEXT NOT NULL, `sectionIndex` INTEGER NOT NULL, `chunkOrdinal` INTEGER NOT NULL, " +
                        "`sectionTitle` TEXT, `text` TEXT NOT NULL, `indexedText` TEXT NOT NULL, " +
                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
                )
                db.execSQL(
                    "CREATE INDEX IF NOT EXISTS `index_search_sections_staging_bookKey` " +
                        "ON `search_sections_staging` (`bookKey`)",
                )
            }
        }

        /** v7 → v8: feature #135 WI-3 — make re-bookmarking the same position idempotent by adding a
         *  composite UNIQUE index on `bookmarks (bookKey, profileKey)` (the atomic-toggle enforcer,
         *  mirroring the highlights `(profileKey, anchorKey)` dedupe precedent).
         *
         *  A pre-#135 create path (`upsertBookmark`, UUID-keyed) could have produced DUPLICATE rows at
         *  the same `(bookKey, profileKey)`; `CREATE UNIQUE INDEX` would FAIL on such a duplicate. So
         *  the migration first DEDUPES — deleting every duplicate LOSER, keeping a DETERMINISTIC winner
         *  per `(bookKey, profileKey)`: the row with the greatest `updatedAt`, tie-broken by the
         *  greatest `createdAt`, then the LOWEST `bookmarkId` (a total, stable order). This is a
         *  targeted dedupe — a non-duplicate row (unique `(bookKey, profileKey)`) is never deleted, and
         *  no other table is touched. THEN the unique index is created, matching Room's generated name
         *  + columns (`index_bookmarks_bookKey_profileKey` on `(bookKey, profileKey)`) exactly, so
         *  Room's structural PRAGMA validation passes. DDL is idempotent (`IF NOT EXISTS`). */
        val MIGRATION_7_8: Migration = object : Migration(7, 8) {
            override fun migrate(db: SupportSQLiteDatabase) {
                // 1) Dedupe: delete every row that is NOT the deterministic winner within its
                //    (bookKey, profileKey) group. The winner is the row whose (updatedAt, createdAt,
                //    -rowid-preference-on-bookmarkId) is greatest — expressed as: a row is a loser iff
                //    another row in the same group ranks strictly higher by (updatedAt DESC,
                //    createdAt DESC, bookmarkId ASC).
                db.execSQL(
                    "DELETE FROM `bookmarks` WHERE `bookmarkId` IN (" +
                        "SELECT b.`bookmarkId` FROM `bookmarks` b JOIN `bookmarks` w " +
                        "ON b.`bookKey` = w.`bookKey` AND b.`profileKey` = w.`profileKey` " +
                        "AND b.`bookmarkId` <> w.`bookmarkId` " +
                        "WHERE (w.`updatedAt` > b.`updatedAt`) " +
                        "OR (w.`updatedAt` = b.`updatedAt` AND w.`createdAt` > b.`createdAt`) " +
                        "OR (w.`updatedAt` = b.`updatedAt` AND w.`createdAt` = b.`createdAt` " +
                        "AND w.`bookmarkId` < b.`bookmarkId`))",
                )
                // 2) Now that each (bookKey, profileKey) is unique, create the unique index.
                db.execSQL(
                    "CREATE UNIQUE INDEX IF NOT EXISTS `index_bookmarks_bookKey_profileKey` " +
                        "ON `bookmarks` (`bookKey`, `profileKey`)",
                )
            }
        }

        /** All registered migrations, oldest first. Append future Migration(n,n+1) here. */
        val ALL_MIGRATIONS: Array<Migration> =
            arrayOf(
                MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4, MIGRATION_4_5,
                MIGRATION_5_6, MIGRATION_6_7, MIGRATION_7_8,
            )

        /** The production on-disk database (app-private storage). */
        fun build(context: Context): VReaderDatabase =
            Room.databaseBuilder(context.applicationContext, VReaderDatabase::class.java, DB_NAME)
                .addMigrations(*ALL_MIGRATIONS)
                .build()
    }
}
// Purpose: Application + manual DI container — feature #106 WI-8. Holds the
// process-singleton Room database, repository, and importer so the Library
// ViewModel gets shared instances (a Hilt module is a Phase-3 follow-on; manual
// wiring at the app edge keeps the foundation bar dependency-light — rule 50 §5).
package com.vreader.app

import android.app.Application
import android.content.Context
import com.vreader.app.data.BookImporter
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import com.vreader.app.reader.BookOpener
import com.vreader.app.search.BookTextExtractor
import com.vreader.app.search.EpubTextExtractor
import com.vreader.app.search.asSearcher
import com.vreader.app.search.SearchIndexCoordinator
import com.vreader.app.search.TxtMdTextExtractor
import com.vreader.app.annotations.AnnotationsRepository
import com.vreader.app.stats.ReadingStatsRepository
import com.vreader.app.stats.ReadingTimeTracker
import com.vreader.app.stats.clock.SystemDateClock
import com.vreader.app.stats.clock.SystemElapsedClock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.map
import vreader.contracts.BookFormat
import java.io.File

/** Process-wide singletons, lazily built. */
class AppContainer(context: Context) {
    private val appContext = context.applicationContext

    val database: VReaderDatabase by lazy { VReaderDatabase.build(appContext) }
    val repository: LibraryRepository by lazy {
        LibraryRepository(database.bookDao(), database.readingPositionDao())
    }
    val importer: BookImporter by lazy {
        BookImporter(File(appContext.filesDir, "books"), repository)
    }

    // feature #122 — reading-stats. The repository + the time tracker are process-singletons so a
    // reading session survives the (shorter-lived) reader ViewModel / rotation. ONE shared DateClock
    // so the dashboard's "today" and the tracker's bucket dates can't drift apart.
    private val dateClock: SystemDateClock by lazy { SystemDateClock() }
    val statsRepository: ReadingStatsRepository by lazy {
        ReadingStatsRepository(database.readingStatsDao(), repository, dateClock)
    }
    val readingTimeTracker: ReadingTimeTracker by lazy {
        ReadingTimeTracker(statsRepository, SystemElapsedClock(), dateClock)
    }

    // feature #123 — annotations (EPUB highlights & notes). Process-singleton so the reader VM /
    // rotation share one instance (the statsRepository precedent).
    val annotationsRepository: AnnotationsRepository by lazy {
        AnnotationsRepository(database.annotationDao())
    }

    // feature #127 — library collections. Process-singleton (the annotationsRepository precedent).
    val collectionRepository: com.vreader.app.data.CollectionRepository by lazy {
        com.vreader.app.data.CollectionRepository(database.collectionDao())
    }

    // feature #129 — reader display settings. A device-local DataStore (the OpdsSourceStore /
    // AiProviderStore precedent), global (not per-book), process-singleton so a settings change
    // propagates to whatever reader is open. Stored under noBackupFilesDir — display prefs are
    // per-device (NOT in the backup contract), so they must be excluded from Android Auto Backup.
    private val readerSettingsDataStore: androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences> by lazy {
        androidx.datastore.preferences.core.PreferenceDataStoreFactory.create {
            File(appContext.noBackupFilesDir, "reader_settings.preferences_pb")
        }
    }
    val readerSettingsStore: com.vreader.app.reader.settings.ReaderSettingsStore by lazy {
        com.vreader.app.reader.settings.ReaderSettingsStore(readerSettingsDataStore)
    }

    /** Process-lifetime scope for fire-and-forget writes that must outlive a screen
     *  (e.g. the reader's onStop position flush — it must finish even as the activity
     *  is being torn down). */
    val appScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    // feature #128 WI-5 — cross-book search index. The coordinator observes the library and
    // streams each indexable book (epub/txt/md) through the WI-3 extractors into WI-4's staging →
    // atomic publish. Eagerly started once from onCreate; pdf/azw3 map to null (never indexable).
    private val bookOpener: BookOpener by lazy { BookOpener(appContext) }
    private val epubTextExtractor: EpubTextExtractor by lazy { EpubTextExtractor(bookOpener) }
    private val txtMdTextExtractor: TxtMdTextExtractor by lazy { TxtMdTextExtractor() }
    val searchIndexCoordinator: SearchIndexCoordinator by lazy {
        SearchIndexCoordinator(
            repository = repository,
            searchDao = database.searchDao(),
            extractorFor = { fmt: BookFormat ->
                when (fmt) {
                    BookFormat.epub -> epubTextExtractor
                    BookFormat.txt, BookFormat.md -> txtMdTextExtractor
                    BookFormat.pdf, BookFormat.azw3 -> null   // metadata-only — never indexed
                }
            },
            scope = appScope,
            ioDispatcher = Dispatchers.IO,
        )
    }

    /** Idempotent — starts the single search-index collector (the coordinator's own AtomicBoolean
     *  makes a repeat call a no-op). Called once from [VReaderApp.onCreate]. */
    fun startSearchIndexing() = searchIndexCoordinator.startSearchIndexing()

    // feature #128 WI-6 — the query pipeline. SearchRepository turns a raw query into an observable
    // Flow of first-hit-per-book text hits (grows as indexing completes); RecentSearchesStore is a
    // device-local DataStore under noBackupFilesDir (the readerSettingsStore precedent — recents are
    // per-device, NOT in the backup contract). The SearchViewModel factory wires the metadata filter,
    // the text-hit Flow, the completeness gate, and recent-recording for the WI-7 screen.
    val searchRepository: com.vreader.app.search.SearchRepository by lazy {
        com.vreader.app.search.SearchRepository(database.searchDao())
    }
    private val recentSearchesDataStore: androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences> by lazy {
        androidx.datastore.preferences.core.PreferenceDataStoreFactory.create {
            File(appContext.noBackupFilesDir, "recent_searches.preferences_pb")
        }
    }
    val recentSearchesStore: com.vreader.app.search.RecentSearchesStore by lazy {
        com.vreader.app.search.RecentSearchesStore(recentSearchesDataStore)
    }

    /**
     * feature #133 WI-10 — the per-reader-session in-book-search ViewModel for a TXT/MD host. Wires the
     * WI-6 [InBookSearchRepository] (FTS DAO page/count/resume + the WI-4 [TxtMdInBookHitResolver] over the
     * already-decoded [decodedText]) behind the WI-8 [InBookSearchViewModel], gated by the WI-7
     * [IndexStateGate] over the DAO's `observeIndexState` Flow and fed the GLOBAL recents store.
     *
     * The EPUB engine seam is NEVER invoked for a TXT/MD host (the repository dispatches only the TXT/MD
     * branch for `txt`/`md`), so `epubEngineFor` is an error-throwing guard — a call would be a wiring bug.
     * ONE [InBookSearchRepository] per session (the VM's `closeAllEpubCursors` lifecycle contract holds
     * uniformly even though TXT has no cursors). [coroutineScope] is the VM's `viewModelScope` in production
     * (the VM cancels its child collectors on `onCleared`).
     */
    fun inBookSearchViewModel(
        bookKey: String,
        format: BookFormat,
        decodedText: String,
        contentSHA256: String,
        fileByteCount: Long,
        coroutineScope: CoroutineScope,
    ): com.vreader.app.search.InBookSearchViewModel {
        val searchDao = database.searchDao()
        val repository = com.vreader.app.search.InBookSearchRepository(
            dispatcher = Dispatchers.Default,
            fts = com.vreader.app.search.InBookFtsDeps(
                matchingChunksPage = { ftsQuery, afterSectionIndex, afterChunkOrdinal, afterId, limit ->
                    searchDao.matchingChunksPage(bookKey, ftsQuery, afterSectionIndex, afterChunkOrdinal, afterId, limit)
                },
                chunkAtOrAfter = { ftsQuery, atSectionIndex, atChunkOrdinal, atId ->
                    searchDao.chunkAtOrAfter(bookKey, ftsQuery, atSectionIndex, atChunkOrdinal, atId)
                },
                // The resolver re-derives the chunk boundaries from the ALREADY-decoded reader text (no I/O);
                // memoized per session inside the resolver (built once).
                resolverFor = {
                    com.vreader.app.search.TxtMdInBookHitResolver(
                        contentSHA256 = contentSHA256,
                        fileByteCount = fileByteCount,
                        format = format.name,
                        decodedText = decodedText,
                    )
                },
            ),
            // TXT/MD never reaches the EPUB branch — a call here is a dispatch bug, fail fast.
            epubEngineFor = { error("EPUB in-book search engine requested on a TXT/MD host") },
        )
        return com.vreader.app.search.InBookSearchViewModel(
            bookKey = bookKey,
            format = format,
            searcher = repository.asSearcher(),
            indexStateGate = com.vreader.app.search.IndexStateGate(Dispatchers.Default),
            indexStateFlow = searchDao.observeIndexState(bookKey),
            // For a settled-`indexed` TXT/MD row the gate consults this to decide Ready vs definitive
            // NoResults. `hasOccurrence` carries no query, so we report Ready (true) and let the actual
            // `page(...)` be the source of truth: a settled book with zero matches runs one fast FTS query
            // and the repository returns NoResults — the SAME UI outcome the gate's occurrence short-circuit
            // would give, without threading the live query through a shared mutable seam (no race). The gate
            // is only consulted on a settled-indexed row, so this never fires while Indexing/missing/failed.
            hasOccurrence = { true },
            recentsFlow = recentSearchesStore.recents(),
            recordQuery = { q -> recentSearchesStore.record(q) },
            dispatcher = Dispatchers.Default,
            coroutineScope = coroutineScope,
        )
    }

    /**
     * feature #133 WI-11 — the per-reader-session in-book-search ViewModel for the EPUB host. EPUB search does
     * NOT use the #128 FTS index at all (a chunk-level, location-less index cannot yield a jumpable position);
     * instead the WI-6 [InBookSearchRepository]'s EPUB branch runs Readium's OWN `SearchService` over the LIVE
     * [publication] via the WI-5 [EpubInBookSearchEngine] production constructor (which wraps the real
     * publication behind the `PublicationSearchSource` seam), returning navigable Readium `Locator`s the host
     * jumps to with `navigator.go`.
     *
     * EPUB bypasses the WI-7 index-state gate entirely: the [indexStateFlow] emits `null` (missing) and
     * [hasOccurrence] reports Ready, so the gate resolves to Ready and the engine's own `isSearchable` probe
     * is the real capability check (an un-searchable publication → the repository's [InBookSearchOutcome.Unsupported]
     * → the WI-8 VM's `hidesSearchEntry`, so the host omits the Search icon). The TXT/MD FTS branch is NEVER
     * invoked for an EPUB host, so its factories are error-throwing guards (a call would be a wiring bug).
     *
     * ONE [InBookSearchRepository] per session (so the live Readium `SearchIterator` behind
     * `SearchCursor.Epub` is held once and disposed via `closeAllEpubCursors` on dismiss / `onCleared`).
     * [coroutineScope] is the host's `lifecycleScope` in production (the VM cancels its child collectors on
     * `onCleared`).
     */
    fun epubInBookSearchViewModel(
        bookKey: String,
        publication: org.readium.r2.shared.publication.Publication,
        coroutineScope: CoroutineScope,
    ): com.vreader.app.search.InBookSearchViewModel {
        val repository = com.vreader.app.search.InBookSearchRepository(
            dispatcher = Dispatchers.Default,
            // The EPUB host never reaches the FTS branch (the repository dispatches only the EPUB branch for
            // `epub`), so the TXT/MD deps are error-throwing guards — a call here is a wiring bug, fail fast.
            fts = com.vreader.app.search.InBookFtsDeps(
                matchingChunksPage = { _, _, _, _, _ -> error("FTS matchingChunksPage requested on an EPUB host") },
                chunkAtOrAfter = { _, _, _, _ -> error("FTS chunkAtOrAfter requested on an EPUB host") },
                resolverFor = { error("FTS resolver requested on an EPUB host") },
            ),
            // The LIVE wiring: build the WI-5 engine over the real Readium publication (its production
            // constructor wraps the publication behind the `PublicationSearchSource` seam). One engine per
            // repository/session; the repository memoizes it per bookKey.
            epubEngineFor = { com.vreader.app.search.EpubInBookSearchEngine(publication) },
        )
        return com.vreader.app.search.InBookSearchViewModel(
            bookKey = bookKey,
            format = BookFormat.epub,
            searcher = repository.asSearcher(),
            indexStateGate = com.vreader.app.search.IndexStateGate(Dispatchers.Default),
            // EPUB bypasses the FTS index-state gate: a `null` (missing) row + `hasOccurrence == true` resolve
            // the gate to Ready, so the engine's own `isSearchable` probe is the capability check.
            indexStateFlow = kotlinx.coroutines.flow.flowOf(null),
            hasOccurrence = { true },
            recentsFlow = recentSearchesStore.recents(),
            recordQuery = { q -> recentSearchesStore.record(q) },
            dispatcher = Dispatchers.Default,
            coroutineScope = coroutineScope,
        )
android/app/src/main/kotlin/com/vreader/app/reader/share/BookShareIntent.kt:53:        type = mimeFor(book.originalFormat)
android/app/src/main/kotlin/com/vreader/app/reader/share/BookFileProvider.kt:88:            val name = safeDisplayName(book.title, extensionFor(book.originalFormat))
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderScreen.kt:156:    // default so #132/#134 callers stay valid). The Bookmarks-tab row shows "p. N" (no preview/chapter).
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderScreen.kt:204:        format = book.originalFormat.name,
android/app/src/main/kotlin/com/vreader/app/data/SearchDao.kt:81:            "WHERE b.originalFormat IN ('epub', 'txt', 'md') " +
android/app/src/main/kotlin/com/vreader/app/data/SearchDao.kt:91:            "WHERE b.originalFormat IN ('epub', 'txt', 'md') " +
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:64:        "UPDATE books SET title = :title, originalFormat = :fmt, contentSHA256 = :sha, " +
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:89:                fmt = book.originalFormat,
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:87:            "One key unlocks bilingual translation, chat about a book, and chapter summaries. Your key is stored on-device only.",
android/app/src/main/kotlin/com/vreader/app/reader/nav/ReadiumTocProvider.kt:42: * (`contentSHA256`/`fileByteCount`/`originalFormat`) is threaded into every canonical
android/app/src/main/kotlin/com/vreader/app/reader/nav/ReadiumTocProvider.kt:80:            bookFormat = book.originalFormat,
android/app/src/main/kotlin/com/vreader/app/data/SearchEntities.kt:50:    val sectionIndex: Int,       // per-book reading-order/section index (chapter attribution + tie-break)
android/app/src/main/kotlin/com/vreader/app/data/SearchEntities.kt:52:    val sectionTitle: String?,   // chapter label for the snippet attribution; null for TXT/MD
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocBookmarksSheet.kt:8:// serif preview · `chapter · p.N · date` sub-line · chevron. Tap-to-jump is capability-gated (a null
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocBookmarksSheet.kt:277: * [BookmarkRowUi.preview] and the `chapter · p.N · date` meta sub-line, and a trailing chevron. The row is
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocBookmarksSheet.kt:286:    // chapter — else "Bookmark" — stands in so the row is never blank (still italic serif, per the design).
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocBookmarksSheet.kt:287:    val primary = ui.preview ?: ui.chapter ?: "Bookmark"
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocBookmarksSheet.kt:350: * The design's `chapter · p.N · date` meta sub-line — only the present parts, joined by " · ". A row
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocBookmarksSheet.kt:351: * with no chapter/page (TXT/MD, which carry a preview instead) shows just the date; nothing is fabricated.
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocBookmarksSheet.kt:354:    listOfNotNull(ui.chapter, ui.pageLabel, ui.dateLabel.takeIf { it.isNotBlank() })
android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt:3:// produces a per-chapter summary cached by (book + chapter + source digest + provider + model +
android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt:85:    /** Show the chapter summary — cache hit is instant; else a one-shot request, then cached. */
android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt:86:    fun summarize(bookFingerprintKey: String, chapterId: String, chapterText: String, regenerate: Boolean = false) {
android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt:94:            // different chapters can't share a cached summary.
android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt:95:            val cacheKey = listOf(bookFingerprintKey, chapterId, sha256(chapterText), profile.id, effectiveModel, SUMMARY_PROMPT_VERSION).joinToString("|")
android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt:105:                    listOf(AiMessage(AiRole.user, "Summarize this chapter in 4 concise key points (markdown bullet list):\n\n$chapterText")),
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:2:// a stored BookmarkRecord into a display row (BookmarkRowUi) DERIVED every call (Risk-7: preview/chapter
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:3:// are NEVER stored). Per format: EPUB/AZW3 = nearest-at-or-above TOC chapter via a PREVALIDATED
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:24:    /** EPUB/AZW3 only: the nearest-at-or-above TOC chapter title; null otherwise / before the first entry. */
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:25:    val chapter: String?,
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:46: * A prevalidated, searchable view of a book's reading-ordered TOC for EPUB/AZW3 bookmark-chapter lookup.
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:64:     * The nearest chapter at or before [target]:
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:67:     *  - **degraded TOC** → href-exact fallback (last same-href entry at/before the in-chapter
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:69:     * Returns null (never a fabricated chapter) when the target can't be placed / the TOC is empty.
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:100:     * The same-`href` TOC entry whose in-chapter `progression` is the GREATEST at or before the target's
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:101:     * — the chapter the bookmark lives in — chosen by `progression`, NOT by list order (a same-href TOC
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:103:     * (conservative: never select a chapter whose position can't be compared). Null when no same-href
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:155:     * @param tocIndex a PREVALIDATED [BookmarkTocIndex] for EPUB/AZW3 chapter lookup (built once from the
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:156:     *   TOC and reused across rows — see [BookmarkTocIndex]); null degrades to a null chapter.
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:176:                    chapter = entry?.title,
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:184:                chapter = null,
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:195:                val raw = locator.charOffsetUTF16
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:199:                    chapter = null,
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:260:    fun cacheOffset(fingerprintKey: String, charOffsetUtf16: Int) { lastOffsets[fingerprintKey] = charOffsetUtf16 }
android/app/src/main/kotlin/com/vreader/app/data/LibraryRepository.kt:22:    val originalFormat: BookFormat,
android/app/src/main/kotlin/com/vreader/app/data/LibraryRepository.kt:117:        originalFormat = BookFormat.valueOf(e.originalFormat),
android/app/src/main/kotlin/com/vreader/app/data/LibraryRepository.kt:130:        originalFormat = originalFormat.name,
android/app/src/main/kotlin/com/vreader/app/data/BookImporter.kt:97:                        originalFormat = format,
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:26:    val originalFormat: String,   // BookFormat raw value (epub/pdf/txt/md/azw3)
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:149: * `title` is the optional user/chapter label. The composite UNIQUE `(bookKey, profileKey)` index
android/app/src/main/kotlin/com/vreader/app/ai/AiChatUiState.kt:29:            "What themes appear in this chapter?",
android/app/src/main/kotlin/com/vreader/app/ai/AiChatUiState.kt:30:            "Summarize this chapter",
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocSheetRows.kt:3:// chapter number (the 1-based row position — our model carries no explicit `ch`), the section title
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocSheetRows.kt:4:// (serif; accent + heavier weight when it is the current chapter, per the design's highlighted row),
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocSheetRows.kt:40: * One Contents row for [entry] at [index]. Shows `chapter# · title · p.N`; when [isCurrent] the row
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocSheetRows.kt:42: * highlighted-chapter state). Tapping calls [onClick] with [index]. testTags: `toc-row-$index` (+
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocSheetRows.kt:62:    // A11y: announce the chapter number, the title, the page label, and the current-chapter state —
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocSheetRows.kt:68:        if (isCurrent) append(", current chapter")
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocSheetRows.kt:85:        // accent bg + accent/600 title is the visible form of the same "current chapter" state).
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocSheetRows.kt:100:        // Title — the highlighted chapter is accent + weight-600; nested entries indent by depth.
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocContentsSheet.kt:6:// `title="Pride and Prejudice"`), a bottom rule, then [TocEntry] rows (chapter# · title · p.N) with the
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocEntry.kt:13: * A single chapter/section row of a book's table of contents.
android/app/src/main/kotlin/com/vreader/app/MainActivity.kt:104:                    onOpenBook = { book -> openBook(book.originalFormat, book.id) },
android/app/src/main/kotlin/com/vreader/app/MainActivity.kt:138:                            openBook(row.book.originalFormat, row.book.fingerprintKey)
android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:3:// units against the RAW text — NO line-ending normalization, so charOffsetUTF16 stays
android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:9:class TxtDocument private constructor(
android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:63:            var chunkStart = 0
android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:70:                        if (i < n) { push(i); chunkStart = i }
android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:75:                        if (i < n) { push(i); chunkStart = i }
android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:81:                        if (i - chunkStart >= maxChunkChars && i < n && !text[i - 1].isHighSurrogate()) {
android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:82:                            push(i); chunkStart = i
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPreviewProvider.kt:19:    /** A snippet starting near [charOffsetUTF16] (clamped >= 0), at most [maxLen] chars, or null. */
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPreviewProvider.kt:20:    fun snippet(charOffsetUTF16: Int, maxLen: Int): String?
android/app/src/main/kotlin/com/vreader/app/reader/TxtSourceOffsets.kt:27:            val chunkStart = base
android/app/src/main/kotlin/com/vreader/app/reader/TxtSourceOffsets.kt:29:            val s = maxOf(range.startInclusive, chunkStart) - base
android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt:7:// locator for the jump), the highlighted-chapter index, and the Notes review snapshot. [tocIndexFor] is
android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt:9:// TOC entry so the Contents sheet highlights the current chapter as the reader scrolls.
android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt:20: * highlighted chapter row (-1 when there is no TOC or no positional signal maps to a row); [annotations]
android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt:32: * A plain (Readium-free) descriptor of a TOC entry's reading position — its spine href and intra-chapter
android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt:35: * [progression] is treated as 0.0 (chapter start).
android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt:53: * [currentProgression]) among [positions] — i.e. the current chapter/section row to highlight in the
android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt:62: * row, e.g. between chapters), a lexical href comparison is the best-effort fallback for the highlight —
android/app/src/main/kotlin/com/vreader/app/backup/BackupCollector.kt:92:            val blobPath = BlobPath.make(book.originalFormat, book.contentSHA256, book.fileByteCount)
android/app/src/main/kotlin/com/vreader/app/backup/BackupCollector.kt:94:            blobs += BlobUpload(blobPath, path, book.originalFormat, book.contentSHA256, book.fileByteCount)
android/app/src/main/kotlin/com/vreader/app/backup/BackupCollector.kt:150:        format = originalFormat.name,
android/app/src/main/kotlin/com/vreader/app/backup/BackupCollector.kt:153:        originalExtension = originalFormat.name,
android/app/src/main/kotlin/com/vreader/app/reader/details/BookDetailsMapper.kt:27:            formatLabel = formatLabel(book.originalFormat),
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:98:                    format = book.originalFormat.name,
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:178:                            bookmarkRowItems(bookmarkRecords, s.book.originalFormat, tocIndex = null, previewProvider = null, dateRenderer = dateRenderer)
android/app/src/main/kotlin/com/vreader/app/tts/TtsHighlight.kt:10:     * `[chunkStart, chunkEnd)` to wash for the spoken `[charStart, charEnd)`, or null when the spoken
android/app/src/main/kotlin/com/vreader/app/tts/TtsHighlight.kt:13:    fun localSpan(chunkStart: Int, chunkEnd: Int, charStart: Int, charEnd: Int): IntRange? {
android/app/src/main/kotlin/com/vreader/app/tts/TtsHighlight.kt:14:        if (chunkEnd <= chunkStart || charEnd <= charStart) return null
android/app/src/main/kotlin/com/vreader/app/tts/TtsHighlight.kt:15:        val s = maxOf(charStart, chunkStart)
android/app/src/main/kotlin/com/vreader/app/tts/TtsHighlight.kt:18:        return (s - chunkStart) until (e - chunkStart)
android/app/src/main/kotlin/com/vreader/app/annotations/EpubAnnotationMapper.kt:34:            format = book.originalFormat.name,
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:146:                    // has no chapter/page (the WI-4 EPUB/AZW3 branch degrades to null fields — no crash) — a
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:231:            // the initial highlighted-chapter index for the current reading position.
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:492:     *  chrome model's highlighted-chapter index in sync as the reader scrolls (prompt, un-debounced — the
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:533:                format = current.originalFormat.name,
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:540:     *  extraction — chapter/page come from the TOC). Lifecycle-scoped so the collector is cancelled with
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:547:                    format = current.originalFormat,
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:613:                bookFormat = current.originalFormat,
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:983: * projection: EPUB/AZW3 chapter/page from the prevalidated [tocIndex] (built ONCE per host from its TOC),
android/app/src/main/kotlin/com/vreader/app/reader/ReadiumLocatorBridge.kt:85:            originalFormat = bookFormat,
android/app/src/main/kotlin/com/vreader/app/reader/TxtProgress.kt:2:// chunks (not chapters) and no progress model; reading-stats' "time left in book" needs a 0..1
android/app/src/main/kotlin/com/vreader/app/reader/TxtProgress.kt:3:// fraction. Pure: the top-visible char offset over the document's total length. No "left in chapter"
android/app/src/main/kotlin/com/vreader/app/reader/TxtProgress.kt:4:// for TXT (no chapter index).
android/app/src/main/kotlin/com/vreader/app/reader/ChunkTextMapper.kt:11://   TxtReaderActivity.kt (#125 WI-3 builds the right impl from book.originalFormat), TxtSelectionController.kt
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:6:// path (NOT the Readium bridge): save the top-visible chunk's charOffsetUTF16 as a
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:19:// (TXT/MD jump via the plain Locator's charRangeStartUTF16/charOffsetUTF16 → the existing chunk scroll
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:26:// hit's canonical charOffsetUTF16 resolves to a scroll via the EXISTING chunk-scroll seam
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:190:                    format = book.originalFormat.name,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:191:                    charOffsetUTF16 = offset,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:276:                        val annotatable = s.book.originalFormat == BookFormat.txt || s.book.originalFormat == BookFormat.md
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:277:                        val chunkMapper = remember(s.document, s.book.originalFormat) {
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:278:                            if (s.book.originalFormat == BookFormat.md) MarkdownChunkTextMapper(s.document)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:344:                        // projection degrades chapter/page to null) but DOES supply a preview provider (a bounded
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:355:                            bookmarkRowItems(bookmarkRecords, s.book.originalFormat, tocIndex = null, previewProvider = previewProvider, dateRenderer = dateRenderer)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:372:                        val inBookSearchVm = remember(bookKey, s.book.originalFormat) {
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:375:                                format = s.book.originalFormat,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:407:                                val target = txtBookmarkScrollTarget(record.locator.charOffsetUTF16, s.document.text.length)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:438:                                        // Resolve the tapped hit's canonical charOffsetUTF16 → scroll via the
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:448:                                            val off = hit.canonicalLocator?.charOffsetUTF16
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:513:                                    s.document, listState, s.book.originalFormat, chunkMapper,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:609:    /** Restore: the saved legacy locator's charOffsetUTF16 → the chunk containing it. */
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:616:        // (non-Readium) envelope → Canonical; its charOffsetUTF16 is the anchor.
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:618:            ?.locator?.charOffsetUTF16 ?: return 0
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:747:            book.contentSHA256, book.fileByteCount, book.originalFormat.name,   // #125: NOT hardcoded "txt" — MD key is "md:…"
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:896: * save-position construction (identity triple + `charOffsetUTF16`), so a bookmark's position lines up with
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:899:fun txtBookmarkLocator(book: com.vreader.app.data.Book, charOffsetUTF16: Int): vreader.contracts.Locator =
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:903:        format = book.originalFormat.name,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:904:        charOffsetUTF16 = charOffsetUTF16.coerceAtLeast(0),
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:927:    BookmarkPreviewProvider { charOffsetUTF16, maxLen ->
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:929:        val start = charOffsetUTF16.coerceAtLeast(0)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:943: *  `charRangeStartUTF16`; a standalone note (or a highlight without a range) at `charOffsetUTF16`; a
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:947:    return (loc.charRangeStartUTF16 ?: loc.charOffsetUTF16 ?: 0).coerceAtLeast(0)
android/app/src/main/kotlin/com/vreader/app/reader/share/BookShareIntent.kt:53:        type = mimeFor(book.originalFormat)
android/app/src/main/kotlin/com/vreader/app/reader/share/BookFileProvider.kt:88:            val name = safeDisplayName(book.title, extensionFor(book.originalFormat))
android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:3:// units against the RAW text — NO line-ending normalization, so charOffsetUTF16 stays
android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:9:class TxtDocument private constructor(
android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:63:            var chunkStart = 0
android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:70:                        if (i < n) { push(i); chunkStart = i }
android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:75:                        if (i < n) { push(i); chunkStart = i }
android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:81:                        if (i - chunkStart >= maxChunkChars && i < n && !text[i - 1].isHighSurrogate()) {
android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:82:                            push(i); chunkStart = i
android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt:7:// locator for the jump), the highlighted-chapter index, and the Notes review snapshot. [tocIndexFor] is
android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt:9:// TOC entry so the Contents sheet highlights the current chapter as the reader scrolls.
android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt:20: * highlighted chapter row (-1 when there is no TOC or no positional signal maps to a row); [annotations]
android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt:32: * A plain (Readium-free) descriptor of a TOC entry's reading position — its spine href and intra-chapter
android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt:35: * [progression] is treated as 0.0 (chapter start).
android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt:53: * [currentProgression]) among [positions] — i.e. the current chapter/section row to highlight in the
android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt:62: * row, e.g. between chapters), a lexical href comparison is the best-effort fallback for the highlight —
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderScreen.kt:156:    // default so #132/#134 callers stay valid). The Bookmarks-tab row shows "p. N" (no preview/chapter).
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderScreen.kt:204:        format = book.originalFormat.name,
android/app/src/main/kotlin/com/vreader/app/search/InBookSearchRepository.kt:293:    /** The 1-based human section label ("Section 1", …) or the stored chapter title when present. */
android/app/src/main/kotlin/com/vreader/app/reader/nav/ReadiumTocProvider.kt:42: * (`contentSHA256`/`fileByteCount`/`originalFormat`) is threaded into every canonical
android/app/src/main/kotlin/com/vreader/app/reader/nav/ReadiumTocProvider.kt:80:            bookFormat = book.originalFormat,
android/app/src/main/kotlin/com/vreader/app/reader/TxtSourceOffsets.kt:27:            val chunkStart = base
android/app/src/main/kotlin/com/vreader/app/reader/TxtSourceOffsets.kt:29:            val s = maxOf(range.startInclusive, chunkStart) - base
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:231:            // the initial highlighted-chapter index for the current reading position.
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:492:     *  chrome model's highlighted-chapter index in sync as the reader scrolls (prompt, un-debounced — the
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:533:                format = current.originalFormat.name,
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:540:     *  extraction — chapter/page come from the TOC). Lifecycle-scoped so the collector is cancelled with
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:547:                    format = current.originalFormat,
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:613:                bookFormat = current.originalFormat,
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:983: * projection: EPUB/AZW3 chapter/page from the prevalidated [tocIndex] (built ONCE per host from its TOC),
android/app/src/main/kotlin/com/vreader/app/search/InBookSearchHitResolver.kt:29: * `charOffsetUTF16` from `TxtDocument` — no stored offset column.
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocBookmarksSheet.kt:8:// serif preview · `chapter · p.N · date` sub-line · chevron. Tap-to-jump is capability-gated (a null
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocBookmarksSheet.kt:277: * [BookmarkRowUi.preview] and the `chapter · p.N · date` meta sub-line, and a trailing chevron. The row is
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocBookmarksSheet.kt:286:    // chapter — else "Bookmark" — stands in so the row is never blank (still italic serif, per the design).
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocBookmarksSheet.kt:287:    val primary = ui.preview ?: ui.chapter ?: "Bookmark"
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocBookmarksSheet.kt:350: * The design's `chapter · p.N · date` meta sub-line — only the present parts, joined by " · ". A row
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocBookmarksSheet.kt:351: * with no chapter/page (TXT/MD, which carry a preview instead) shows just the date; nothing is fabricated.
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocBookmarksSheet.kt:354:    listOfNotNull(ui.chapter, ui.pageLabel, ui.dateLabel.takeIf { it.isNotBlank() })
android/app/src/main/kotlin/com/vreader/app/reader/details/BookDetailsMapper.kt:27:            formatLabel = formatLabel(book.originalFormat),
android/app/src/main/kotlin/com/vreader/app/library/LibraryViewModel.kt:44:    val originalFormat: BookFormat,    // typed — drives reader routing
android/app/src/main/kotlin/com/vreader/app/library/LibraryViewModel.kt:50:    val format: String get() = originalFormat.name.uppercase()
android/app/src/main/kotlin/com/vreader/app/library/LibraryViewModel.kt:196:        originalFormat = book.originalFormat,
android/app/src/main/kotlin/com/vreader/app/reader/TxtProgress.kt:2:// chunks (not chapters) and no progress model; reading-stats' "time left in book" needs a 0..1
android/app/src/main/kotlin/com/vreader/app/reader/TxtProgress.kt:3:// fraction. Pure: the top-visible char offset over the document's total length. No "left in chapter"
android/app/src/main/kotlin/com/vreader/app/reader/TxtProgress.kt:4:// for TXT (no chapter index).
android/app/src/main/kotlin/com/vreader/app/search/BookTextExtractor.kt:14:    /** Per-book reading-order/section index — chapter attribution + first-hit tie-break. */
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:146:                    // has no chapter/page (the WI-4 EPUB/AZW3 branch degrades to null fields — no crash) — a
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:2:// a stored BookmarkRecord into a display row (BookmarkRowUi) DERIVED every call (Risk-7: preview/chapter
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:3:// are NEVER stored). Per format: EPUB/AZW3 = nearest-at-or-above TOC chapter via a PREVALIDATED
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:24:    /** EPUB/AZW3 only: the nearest-at-or-above TOC chapter title; null otherwise / before the first entry. */
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:25:    val chapter: String?,
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:46: * A prevalidated, searchable view of a book's reading-ordered TOC for EPUB/AZW3 bookmark-chapter lookup.
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:64:     * The nearest chapter at or before [target]:
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:67:     *  - **degraded TOC** → href-exact fallback (last same-href entry at/before the in-chapter
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:69:     * Returns null (never a fabricated chapter) when the target can't be placed / the TOC is empty.
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:100:     * The same-`href` TOC entry whose in-chapter `progression` is the GREATEST at or before the target's
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:101:     * — the chapter the bookmark lives in — chosen by `progression`, NOT by list order (a same-href TOC
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:103:     * (conservative: never select a chapter whose position can't be compared). Null when no same-href
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:155:     * @param tocIndex a PREVALIDATED [BookmarkTocIndex] for EPUB/AZW3 chapter lookup (built once from the
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:156:     *   TOC and reused across rows — see [BookmarkTocIndex]); null degrades to a null chapter.
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:176:                    chapter = entry?.title,
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:184:                chapter = null,
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:195:                val raw = locator.charOffsetUTF16
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPresentation.kt:199:                    chapter = null,

codex
Two live-code mismatches have surfaced so far: the plan’s Room baseline is stale (`VReaderDatabase` is version 8, not 5), and the reader/chrome code already contains features #132/#134 rather than merely “prospective” surfaces. I’m checking whether these are documentation-only corrections or whether they alter WI dependencies and implementation scope.
exec
/bin/zsh -lc "rg -n \"\\| (129|131|132|134) \\||Feature #12?9|Feature #132|Feature #134|#129|#132|#134\" docs/features.md docs/parity/android-checklist.md | head -160
sed -n '1,180p' android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt
sed -n '1,220p' android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt
sed -n '1,220p' android/app/src/main/kotlin/com/vreader/app/search/TxtMdTextExtractor.kt
sed -n '1,260p' android/app/src/main/kotlin/com/vreader/app/search/EpubTextExtractor.kt
rg -n \"ChapterSegmenter|TranslationChunkContract|ChapterTranslationChunker|translatePreSegmented|BilingualReadingViewModel|EPUBBilingualOrchestrator\" vreader vreaderTests | head -160" in /Users/ll/workspace/vreader
 succeeded in 0ms:
docs/features.md:129:| 76 | Vertical-writing windowed continuous scroll for Foliate (AZW3/MOBI) — extend Feature #73's K=3 windowed scroll to vertical-writing books (`vertical-rl`/`-lr`), which #73 gated out (`#ensureWindow` returns on `#vertical`), so they still use the per-section swap = the Bug #283 chapter-boundary jump | Reader/Foliate | Medium | VERIFIED | **VERIFIED 2026-06-02 (v3.42.40)** — WI-1 + WI-2 (axis-aware scrolled container layout, PR #1385) + WI-3 (remove the `#vertical` windowing gates + axis-aware primitives, PR #1386) merged = vertical-writing windowed-scroll implemented. All acceptance criteria device-verified on real books: **WI-4 horizontal continuity** (mini-azw3, no #73 regression); **WI-6 large-CJK K=3 memory gate** on the real `被讨厌的勇气` AZW3 (85 ch, 6.3 MB) — baseline RSS 402 MB → peak 403 MB across 60 idb swipes (delta +1 MB / ratio 1.0, far under `≤ baseline+120MB AND ≤ baseline×2.0`), `#evictOutsideWindow` keeps RSS bounded (resolves the #73 Gate-2 H7 concern); **WI-5 vertical-rl windowed crossing** — since no real vertical-rl AZW3 exists (the repo's only AZW3 is horizontal-tb; the `mini-cjk-vlong` vertical fixture is EPUB not AZW3), a DEBUG-only `--force-foliate-vertical-rl` harness (locked `window.__vreaderForceVerticalRL` → section `afterLoad` injects `writing-mode:vertical-rl` before `getDirection`) forces the REAL AZW3 to vertical-rl: it renders genuine vertical-rl columns + windowed-scrolls continuously across sections BOTH directions with RSS bounded (395→415 MB), exercising the full WI-3 vertical path; harness is Release-inert + 2-round-Codex-audited (closed a global-poisoning bypass). Evidence: `dev-docs/verification/feature-76-20260602.md` (result=pass). Residual (non-blocking): a real vertical-authored AZW3 for publisher-CSS coverage + rare vertical-lr. **Reclassified from Bug #283 / GH #1260** (2026-05-31, per user direction): Feature #73's windowing coordinate math is vertical-scroll-axis-only; vertical-WRITING books scroll on the horizontal axis, so windowing was gated out (never implemented for vertical), not broken — per AGENTS.md a feature, the vertical-axis sibling of #73. **Gate 1 + Gate 2 complete**: plan at `dev-docs/plans/20260531-feature-76-vertical-windowed-scroll.md`; Codex `codex exec` plan audit **3 rounds** → READY (zero open Critical/High/Medium). Audit (deepest of the remaining features) caught: vertical sections need an explicit `#container` flex LAYOUT (not just axis math); `getDirection` DISCARDS `writing-mode` (vertical-rl vs -lr lost — live `FIXME`) so an explicit `ScrollModel{axis,scrollProp,sizeProp,rectStartProp,directionSign}` is required; a single canonical `#logicalScrollOffset` API must route every existing axis caller (avoid double-normalize); `#onNeighbourExpand` is unguarded; a numeric memory-gate ceiling (K=3 ≤ baseline+120MB AND ≤ baseline×2.0, else K=2); a mandatory #73 horizontal-AZW3 regression WI. 7 WIs. **Gate 3 (TDD) IN PROGRESS: WI-1 Swift seam SHIPPED 2026-06-01** (commit `e0929934` / PR #1322 — `FoliateScrolledWindowMath.logicalOffset`/`rawOffset(sign:)` canonical logical-offset conversion + tests). **Remaining: the JS portion of WI-1 + WI-2/WI-3 in vendored `paginator.js`** (getDirection→`writingMode`/`ScrollModel`, route every axis caller through `#logicalScrollOffset`, axis-aware `#container` flex, ScrollModel-aware windowed primitives + `#onNeighbourExpand`) — coupled (vertical windowing is only device-verifiable once all land together) + device-gated (WI-5 on a real vertical-writing AZW3 book; no JS unit-test harness). High-risk vendored-Foliate-js; #73's shipped horizontal scroll is guarded by WI-4's regression. GH: #1260 |
docs/features.md:130:| 74 | Locate/flash indicator when navigating to a saved highlight/note from the Notes/Highlights list (TXT) — after the jump, briefly emphasize the target so the reader can see where it landed | Reader/Annotations | Medium | VERIFIED | Filed 2026-05-30 via /triage. The persisted highlight DOES render at the navigated spot (no render-gap), but there is NO post-navigate flash/pulse/scroll-to-prominent emphasis: `handleNavigateToLocator` (`ReaderNotificationHandlers.swift:114-130`) sets a temporary highlight to the highlight's EXACT range, and `HighlightableTextView.setHighlightRanges(persisted:active:)` (`:156-161`) DROPS the temporary highlight when its range equals a persisted range (dedup to avoid double-fill darkening) — so tapping a saved highlight shows the unchanged persisted fill with nothing to call attention to the destination. The transient yellow flash exists for SEARCH results (Feature #2) but was never built for annotation-list jumps. **Rule 51**: the emphasis treatment (a distinct pulse/border/flash that survives the dedup without double-darkening) is a UI decision → needs-design when planned. Cross-ref Feature #2 (search-result flash at destination). **BLOCKED: needs-design (#1343)** — filed 2026-06-01; the highlight-landing emphasis has no committed design (the only designed motion cues are the tap-zone hint flash + skeleton-pulse, neither covers this). Resume Gate 1 once the design bundle lands. Not yet PLANNED → not mirrored to GH as a feature. **DESIGN LANDED 2026-06-02** — claude.ai/design handoff committed (`dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-highlight-landing.md`, canvas `VReader Highlight Landing Canvas.html`); resolves needs-design #1343. Decision: a one-shot "locate bloom" (wash value-lift 0.42→0.86 + same-hue focus ring + soft glow, ~1.5s, fires once; scroll-to-prominent if off-screen; reduce-motion = static-hold opacity fade; covers 5 themes). Also fixes the dedup no-op (temp==persisted is deduped away) via a third non-deduped `landing:` range layer. Scope TXT/MD first (EPUB/Foliate/PDF later). **Gate 1+2 complete 2026-06-03**: plan `dev-docs/plans/20260603-feature-74-locate-bloom.md`; **Gate-2 Codex audit 3 rounds** (`/tmp/feat74-planaudit{,-r2,-r3}.txt`, READY TO BUILD): R1 2 Med (wash baseline vs code's `fillAlpha`; perf-mitigation overstated) → v2; R2 1 Med (separate landing layer at rest still composites a 2nd 0.4 fill → darkens) → v3 **replace-don't-stack** render rule (the landing wash REPLACES the persisted fill for an equal range — design's single wash value-lift); R3 clean. **WI-1 SHIPPED** (v3.49.10, foundational/dormant): the landing render layer (replace-don't-stack vs the equal-range persisted fill, defeating the dedup no-op) + pure `LandingBloomPaint`. **WI-2 SHIPPED** (final WI → DONE): `LandingBloomCurve` (§3 motion + §5 reduce-motion), `reduceMotion`/`ringAlpha` paint, the `CADisplayLink` driver, and the nonce-gated cancellable navigate-from-list trigger. **Gate-4 Codex audit** (`.claude/codex-audits/feat-feature-74-wi2-locate-bloom-animation-audit.md`, **3 rounds**, ship-as-is): R1 2 High (re-tap never re-blooms; interruptibility unwired) + 2 Med (teardown; reduce-motion §5) → R2 1 High (highlight-hit tap didn't cancel) → R3 clean. 17 unit tests (curve / paint+reduce-motion / nonce-trigger / cancellation / render-layer). **Gate-5b**: the bloom is a transient ~1.5s animation; CU-free capture defeated the harness (`search?query=` CJK injection + sub-second screenshot timing) → visual-render `awaiting-device-verification` (logic exhaustively unit+audit-proven; render reuses the production `drawBackground` idiom). **2026-06-06 Gate-5b (CU-free harness, PR #1541, v3.59.2):** built a DEBUG `vreader-debug://locate?highlight=N` command + `landingBloomCount`/`landingBloomPeakIntensity` snapshot readback (the sub-second visual cannot be screenshot/video-captured on the virtual display — the plan's recommended unblock). **Non-chunked TXT bloom VERIFIED**: e2e on `bloom-sample` fixture → `locate?highlight=0` → snapshot `landingBloomCount` 0→1, `peakIntensity` 1.0 through the real `.readerNavigateToLocator` → `TXTTextViewBridge` → `playLandingBloom` CADisplayLink path. **BUT the bloom trigger is NOT wired into the chunked `TXTChunkedReaderBridge`** (chaptered TXT in Scroll layout — the large-CJK-novel case #74 targets): e2e on chaptered `war-and-peace` → `landingBloomCount=0` (no bloom). Filed **Bug #322 / GH #1542** (real coverage gap, not a verification gap). **2026-06-06 — Bug #322 FIXED (PR pending) + #74 → VERIFIED**: wired the bloom trigger into `TXTChunkedReaderBridge`; e2e on chaptered `war-and-peace` (chunked) now → `landingBloomCount` 0→1, `peakIntensity` 1.0. **BOTH TXT bridges verified** (non-chunked + chunked). Evidence `dev-docs/verification/feature-74-20260606.md` (result=pass, both paths). GH: #1456. |
docs/features.md:138:| 84 | Secondary-text `sub`-token AA bump (Paper/Sepia ink@55%→68%) — implement the landed #1292 design so the Display panel's section headers / footers / value captions clear WCAG AA 4.5:1 (Paper 5.81:1, Sepia 4.88:1; Sepia is the binding case). A 2-value change in `ReaderThemeV2.subColor` + a RED→GREEN AA contrast test (the existing `ReaderSettingsPanelContrastTests` asserts only the project's 3.0 secondary bar). | Models/ReaderThemeV2.swift | Low | VERIFIED | Filed 2026-06-02 via /triage — the IMPLEMENTATION slice of the now-closed needs-design #1292 (design delivered PR #1317, `design-notes/secondary-text-sub-token.md`). Rule-51-exempt (restore-to-designed-state). **DONE 2026-06-02** (user lifted the hold): bumped Paper/Sepia `sub` ink@0.55→0.68 (`ReaderThemeV2.subColor`); new `ReaderSettingsPanelContrastTests.secondaryChromeLabelClearsAA` (≥4.5) + design-pin/EPUB-CSS/SettingsHeader test updates. PR #1417, v3.46.0 (build 823), merge `482be9f0`. Plan `dev-docs/plans/20260602-feature-84-sub-token-aa-bump.md`. Gate-4 Codex audit `019e88ef`, 1 round, follow-up-recommended (Medium EPUB-CSS pin fixed; Medium other-light-surface scope accepted + surfaced; 2 Lows fixed). **VERIFIED 2026-06-02** — Gate-5 contrast suites green on merged main (Paper 5.82:1 / Sepia 4.88:1 over `#fcf8f0`; evidence `dev-docs/verification/feature-84-20260602.md`). **Follow-up (surface to user, not filed):** Sepia `chromeColor`/`paperColor` sub (~4.27–4.39:1, improved from 3.36 but <AA) + Dark/OLED secondary (~3.06–3.75:1) — separate visual-weight design calls. GH: #1413. |
docs/features.md:180:| 129| **Android reader display settings — typography slice** (Phase 3, #110 driver; parity-checklist item **E** minus the layout toggle). The designed "Display"/Aa sheet across the readers: the 5 reader themes, font family/size, line spacing, margin — persisted + applied live. **Layout (scroll/paged) is a tracked follow-up** (TXT/MD are scroll-only Compose hosts → a layout toggle would be non-functional there; needs a paged renderer first), so **box E checks only when BOTH #129 AND the layout follow-up are VERIFIED**. Reached via the designed `ReaderBottomChrome` Display slot (other slots omitted until F/D). iOS parity: #60 WI-10. | android/app/.../reader/settings/* + chrome/ReaderBottomChrome + per-host (Txt/Md/Pdf/Epub/Azw3) application | Medium | VERIFIED | **WI-4 (2026-07-11): merged — TXT/MD reader applies Display settings (theme colors/bg, fontSize/family/lineHeight, margin); MD inherits base size via em-relative headings; Display-settings writes serialized in `ReaderSettingsStore` (process-wide Mutex + synchronous per-field submission-sequence latest-wins). Gate-4 3 rounds (follow-up-recommended); JVM 16/16 + connected TxtDisplaySettingsUiTest 3/3. WI-1/2/3 previously merged (android/v0.13.9–v0.13.11).** **WI-5 (2026-07-11): merged — EPUB reader applies Display settings via Readium `EpubPreferences.submitPreferences` (fontSize=fontSizeSp/18.0, lineHeight=lineSpacing, pageMargins=marginDp/20.0, fontFamily SERIF/SANS_SERIF, per-theme backgroundColor/textColor from the 5 themes' ARGB; scroll left at default). Pure `EpubPreferencesMapper` (RED `EpubPreferencesMappingTest`, 12 cases) + open-time `initialPrefs` + live re-submit observer; Gate-4 1 round ship-as-is; connected `EpubDisplaySettingsConnectedTest` green on the real navigator.** **WI-6 (2026-07-11): merged — AZW3 reader applies Display settings via foliate-bridge CSS injection (theme bg/ink, font-family/size, line-height, padding; JS-escape-safe via the shared `foliateSetStylesJs` seam; `Azw3Document` re-applies at book-ready + after render-death recovery). Gate-4 1 round ship-as-is. RED `Azw3DisplayCssTest` (CSS-blob per theme/typography). AZW3 live render deferred to WI-8 (no in-lane AZW3 fixture; foliate WebView styling hard to assert CU-free — #68 precedent).** **WI-7 (2026-07-11): merged — PDF viewer backdrop inherits the theme background color from `ReaderSettingsStore` (composition gated on the first settings emission so a stored dark theme never flashes a bright frame); no Display sheet/Aa slot on PDF — rule 51. Pure `PdfDisplayBackdrop` (RED `PdfDisplayBackdropTest`, 5 themes + default + typography-inert) + connected `PdfDisplaySettingsConnectedTest` (open-time + live update on the synthetic PDF fixture). Gate-4 2 rounds ship-as-is.** **WI-8 (2026-07-11): VERIFIED** — Gate-5 acceptance PASS on `emulator-5554` (verifier observations, evidence `dev-docs/verification/feature-129-20260711.md`): 3 per-format DisplaySettings connected tests green (TXT/MD 3/3, EPUB 1/1, PDF 1/1) + 42 JVM mapping tests (0 fail); AZW3 live-render pipeline confirmed on a REAL 6MB CJK book (render+reopen connected tests pass, chromium renderer + 87 frames) with theme-CSS injection **documented-injecting** via the JVM-tested `setStyles` seam (the WebView bg isn't screencap-readable — sanctioned #68-class limitation, no false visual claim); persistence via ReaderSettingsStoreTest 9/9 + cross-activity read. **All 8 WIs done + VERIFIED.** Box E still needs the separate layout-toggle follow-up before it checks. **PLANNED 2026-06-29 — Gate-2 clean (3 Codex rounds, gpt-5.5/high: R1 1C/1H → R2 1H-resolved+4M → R3 2 mechanical WI-label typos; all applied).** Plan `dev-docs/plans/20260629-feature-129-android-reader-display-settings.md` v3. **Gate-2 caught a Critical pre-build**: a standalone Display Aa button is NOT design-grounded (the design shows Display only inside `ReaderBottomChrome`) → #129 builds the designed chrome shell with Contents/Notes/AI slots omitted-until-ready (LibraryScreen precedent). Readium 3.3.0 `EpubPreferences` (fontSize/family/lineHeight/pageMargins/backgroundColor/textColor + `submitPreferences()`) confirmed; exact sp/dp→Double conversions pinned. Layout toggle + brightness scoped out (tracked follow-ups). **8 WIs**: WI-1 store+themes (foundational); WI-2 Display sheet; WI-3 ReaderBottomChrome shell; WI-4 TXT/MD; WI-5 EPUB; WI-6 AZW3; WI-7 PDF theme-bg; WI-8 acceptance+VERIFIED. GH: #1879 |
docs/features.md:184:| 131| **Android bilingual interlinear reading** (parity box D) — per-book toggle renders each source paragraph followed by an AI-backed translation (muted, accent border), cached to disk; Android parity of iOS #56/#100, building on the #118 AI foundation. | android/app/.../bilingual/* + reader hosts + ReaderBottomChrome/More-menu entry | Medium | PLANNED | Deps:[feat:#132, feat:#134] (entry wiring via box-F chrome + More-menu; #118 AI foundation DONE). Plan `dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md` (Gate-1 v2, ~62 WIs; WI-0 Readium JS-injection spike gates the render WIs). Design authority (landed): vreader-bilingual.jsx + vreader-reader.jsx + vreader-more.jsx. **Gate-2 round-2 audit pending — not yet dispatched; box-F chrome must land first.** GH: #1923 |
docs/features.md:185:| 132| **Android reader nav chrome — shell + Contents (TOC) + annotations-review sheet** (parity box F pt1 + box B annotations-review remainder) — reader chrome shell (top bar + bottom-chrome Contents/Notes slots), the Contents/TOC sheet, the annotations-review (highlights+notes) sheet, and the full annotations.json (highlights+notes+bookmarks) backup round-trip. Root of box F. | android/app/.../reader/{ReaderTopChrome,ReaderChromeScaffold,ReaderChromeState} + panels/TOCSheet + annotations review sheet + backup/{BackupCollector,RestoreImporter} | High | VERIFIED | (root of box F — no deps; chrome files one-writer-coordinate with #129/#131 via nullable-default params). Plan `dev-docs/plans/20260710-feature-132-android-reader-nav-chrome-toc-bookmarks.md` (Gate-1 v4, ~51 WIs). Design authority (landed): vreader-reader.jsx + vreader-panels.jsx + the Android annotations sheet; per-card affordances design gate #1902 CLOSED. Box F checks done only when #132+#133+#134+#135 VERIFIED; box B when #132 review-sheet + #135 bookmark-create VERIFIED. **Gate-2 signed off (round-3 FIX-THEN-PROCEED, findings resolved — the #128 pass pattern). READY TO BUILD — box-F root; Gate-3 dispatch starts here.** **WI-1 (2026-07-11): merged — reader/nav TOC model + providers (foundational): TocEntry (canonical Locator with the Book identity triple + retained native epubReadiumLocator), TocProvider fun-interface, ReadiumTocProvider (flatten tableOfContents children with depth, locatorFromLink nullable-skip, epubReadiumLocator retained, canonical via the adapter-(i) toJSON then ReadiumLocatorBridge.toEnvelope hop so the bridge stays Readium-free; internal PublicationTocSource seam since Readium Publication is final/unmockable), EmptyTocProvider. Robolectric ReadiumTocProviderTest 9/9 green. Gate-4 Codex ship-as-is. Box-F chrome WIs (WI-2 ReaderTopChrome onward) build on this.** **WI-2 (2026-07-11): merged — ReaderTopChrome composable (implements vreader-reader.jsx ReaderTopChrome, rule 51): leading Library back + centered italic-serif title (maxLines=1 ellipsize) live; Search/More/bookmark slots OMITTED when null (no dead controls, #129 rule) - filled by #133/#134/#135 via existing nullable params. Same ReaderTheme token map as ReaderBottomChrome; testTags reader-top-chrome/chrome-back/chrome-search/chrome-more/chrome-bookmark-slot; a11y descriptions + >=48dp targets; RTL. Instrumented ReaderTopChromeTest (createComposeRule) compiles green + JVM suite green; live Compose run defers to a WI-5/WI-8 connected slice. Gate-4 Codex ship-as-is (3 rounds; High title-centering + two Mediums resolved).** **WI-3 (2026-07-11): merged — TocContentsSheet + TocSheetRows (implements vreader-panels.jsx TOCSheet Contents tab, rule 51): single-pane ModalBottomSheet (no dead Bookmarks tab - that is #135) with the design book-title Sheet header + bottom rule, over WI-1 TocEntry rows (ch/title/p.N), currentTocIndex row highlighted (theme-accent tint at design alphas 0.08 light/0.12 dark + accent/weight-600 title). Tap row -> onJump(index) Boolean; sheet dismisses ONLY on success, failed jump keeps sheet open with NO invented error surface (nav-error-presentation). testTags toc-sheet/toc-row-N/toc-empty/toc-title; empty entries -> toc-empty; richer row a11y. Instrumented TocContentsSheetTest compiles green + JVM green; live Compose run rides a WI-5/WI-8 connected slice. Gate-4 Codex 2 rounds -> ship-as-is (round-1 block: book-title header, exact alphas, row a11y - all fixed).** **WI-6b (2026-07-11): merged - annotation snapshot + restore seams (foundational): AnnotationsSnapshot + AnnotationsRepository.annotationsForBook (deterministic (createdAt,id)-sorted highlights+notes one-shot, corrupt rows dropped via toRecordOrNull), AnnotationDao.allNotes/allBookmarks (collector reads) + insertNote/BookmarkIfAbsent, and the UUID-preserving transactional restoreAnnotations(env, allowedBookKeys) -> RestoreAnnotationsReport(KindCounts per kind): preserves backed-up id+timestamps (NOT minting), insert-if-absent idempotent (repeat applies 0), allowed-book scope skips, locator parse / bookKey mismatch counts failed, one @Transaction. NO Room migration; updateNote deferred to the note-Edit WI. In-memory Room tests green. Gate-4 Codex ship-as-is. Unblocks WI-4 + WI-8. **WI-8 CONTRACT (from WI-6b): the restore seam decodes locatorJSON as a PLAIN BackupJson-decodable Locator (the position precedent) - WI-8 MUST encode locatorJSON = BackupJson.encode(locator), NOT canonicalJson() (which emits flattened dotted keys NOT Locator-decodable -> would count every restore row failed); verify vs what iOS writes for cross-platform parity.**** **WI-4 (2026-07-11): merged — AnnotationsReviewSheet + AnnotationCards (implements vreader-android-annotations.jsx AnnotationsSheet, rule 51): ModalBottomSheet over WI-6b AnnotationsSnapshot with All/Highlights/Notes filter chips (no Bookmarks chip - #135), HighlightCard + StandaloneNoteCard (no BookmarkCard - #135), empty (annot-empty) + populated, sheet-level trailing Share (onShareAll -> ACTION_SEND host-side), capability-based nullable onJumpToAnnotation (non-null card clickable+jumps, null card review-only non-clickable - no dead no-op). Per-card Copy/Share + the ... Edit/Delete menu GATED (absence-asserted - the Android cards depict neither; those live on the in-reader SelectionPopover / iOS notes-delete; GH #1902 design landed -> a follow-up WI with updateNote + jump-coupling). Cards render the design dashed note-rule + metaLine + card shadow (Gate-4 round-1 rule-51 fidelity fixes). testTags annotations-sheet/annot-filter-N/annot-card-id/annot-empty/annot-share. Instrumented AnnotationsReviewSheetTest compiles green + JVM green; live Compose run rides a WI-6/WI-8 connected slice. Gate-4 Codex ship-as-is (3 rounds). Notes bottom-chrome slot now has a live destination.** **WI-5 (2026-07-11): merged — chrome scaffold + state: ReaderBottomChrome extended (additive nullable onOpenContents/onOpenNotes; #129 Display slot preserved, Display-only callers still valid; AI omitted; Contents-Notes-Display design order), ReaderChromeState + ReaderSheet(None/Toc/Notes, no Bookmarks - #135) + ReaderChromeStateSaver (mirrors #127 SheetRouteSaver: string-encodes visible+sheet, garbage/empty/wrong-separator/unknown-sheet token -> None/false, never throws), ReaderChromeScaffold (stacks ReaderTopChrome + body + bottomChrome slot receiving Contents/Notes open callbacks + Toc-route->TocContentsSheet / Notes-route->AnnotationsReviewSheet; Contents control hidden when tocEntries empty; center-tap toggles chrome; no bookmark route). JVM ReaderChromeStateSaverTest 10/10 green (round-trip + invalid-token->None); instrumented slot/scaffold tests compile (live Compose run rides WI-6 connected slice). Gate-4 manual-fallback audit ship-as-is (Codex quota-limited) + one audit-driven hardening (fresh-read sheet transitions). WI-6 (TXT host) is the first to render the scaffold.** **WI-6 (2026-07-11): merged — TXT/MD host renders ReaderChromeScaffold: TxtReaderActivity upgraded from the #129 Display-only ReaderBottomChrome to the full scaffold (top bar with book title + Library back, Search/More/bookmark null-omitted; bottom Contents(hidden via empty tocEntries / EmptyTocProvider posture) / Notes / Display; center-tap toggles chrome via rememberSaveable ReaderChromeState + ReaderChromeStateSaver). Notes opens AnnotationsReviewSheet over annotationsForBook(this book) (reloaded on highlight change) with onShareAnnotations firing ACTION_SEND and non-null onJumpToAnnotation scrolling to charRangeStartUTF16/charOffsetUTF16 via the existing TXT chunk scroll seam. #129 Display settings sheet + #121 TTS bar preserved. New instrumented TxtReaderChromeUiTest compiles + JVM AnnotationScrollOffsetTest 5/5 (live Compose/host render rides WI-9 acceptance). Gate-4 ship-as-is (Codex quota exhausted, rule-47 manual fallback). First host to render the scaffold; WI-7-hosts (PDF/AZW3) + WI-7-EPUB follow.** **WI-7-hosts (2026-07-11): merged — PDF + AZW3 hosts render ReaderChromeScaffold (mirror of WI-6): PdfReaderActivity + Azw3ReaderActivity host the scaffold (top bar title + Library back, Search/More/bookmark null; Contents hidden via empty tocEntries/EmptyTocProvider posture; Notes -> AnnotationsReviewSheet over annotationsForBook; onShareAnnotations -> ACTION_SEND; center-tap toggles; ReaderChromeStateSaver-persisted). PDF onJumpToAnnotation NON-null jumps to the annotation page via the existing listState.scrollToItem page-scroll seam (pdfAnnotationPage, clamped); AZW3 onJumpToAnnotation NULL (review-only capability gate - no in-session goTo until #135, FoliateBridge/Azw3Document/foliate-js untouched, WebView sizing (bug #357 MATCH_PARENT) undisturbed; card non-clickable). Each host's #129 Display affordance preserved (PDF theme backdrop / AZW3 live foliate CSS, no control surface) so the bottom chrome is Notes-only. New instrumented PdfReaderChromeUiTest + Azw3ReaderChromeUiTest + JVM PdfAnnotationPageTest; both source sets compile + the JVM helper passes (live Compose run rides WI-9). Gate-4 ship-as-is (manual-fallback, Codex quota). WI-7-EPUB (persistent StateFlow chrome + native-locator TOC jump) is the last host.** **WI-7-EPUB (2026-07-11): merged — EPUB host chrome (the only TOC-supplying host): ReaderActivity now owns a persistent MutableStateFlow<ReaderChromeModel> (title, tocEntries via ReadiumTocProvider(publication,book), currentTocIndex, annotations) fed on async open + position change (tocIndexFor maps the live Readium locator to the nearest TOC entry, exact-href-match-first then a lexical fallback). Three ComposeViews over the fragment FrameLayout — a WRAP_CONTENT top band, a WRAP_CONTENT bottom band, and a full-screen sheet layer that renders NOTHING until a sheet opens — collect it via collectAsStateWithLifecycle, so the Readium fragment underneath keeps scroll/selection/link input (touch-through). Contents onJump -> navigator.go(epubReadiumLocator):Boolean (dismiss on success, stay-open on false, no invented error surface); Notes -> AnnotationsReviewSheet with jump-to-annotation NULL (EPUB review-only until #135, cards non-clickable); onShareAll -> ACTION_SEND via the shared annotationsShareText formatter. #129 observeDisplaySettings + Display sheet + selection popover + highlight decorations + position save + publication.close all preserved; chrome extracted to ReaderChromeModel.kt + EpubReaderChrome.kt to keep ReaderActivity focused. JVM ReaderChromeModelTest (tocIndexFor) 11/11 green; instrumented ReaderChromeConnectedTest compiles (live navigator/Compose render rides WI-9). Gate-4 manual-fallback ship-as-is. All 5 formats now render the nav chrome; WI-8 (annotations.json backup) + WI-9 (acceptance) remain.** **WI-8 (2026-07-11): merged — annotations.json backup+restore (box B remainder): BackupCollector emits a deterministic annotations.json section (BackupAnnotationsEnvelope of highlights+notes+bookmarks, filtered to the collected manifest books, byte-stably sorted by (bookFingerprintKey,id), UUID preserved, totalSize includes it) beside positions/collections; RestoreImporter decodes it + calls WI-6b restoreAnnotations(env, allowedBookKeys) (UUID-preserving, idempotent, per-kind counts) scoped to the manifest's in-selection books. CRITICAL locatorJSON is the PLAIN serialized Locator (BackupJson.encode(locator)) matching iOS encoder.encode(locator) + contracts/vectors/backup-sections.json + WI-6b's plain decode - NOT canonicalJson (the plan text was wrong; canonical emits non-Locator-decodable dotted keys); profileKey derived on restore, not emitted. bookmarks wired (usually empty until #135). pre-#132 backup (no annotations.json) restores zero annotations, no crash. #113 :identity DTOs reused, no contracts change. JVM BackupAnnotationsCollectorTest green (11 tests: plain-not-canonical, byte-stable sort, filter-to-manifest, populate bookmarks, empty, totalSize, round-trip UUID-preserve, idempotent, scope-filter, absent-section-no-crash, malformed-drop); connected AnnotationBackupRoundTripConnectedTest compiles (live WebDAV round-trip rides WI-9). Gate-4 manual-fallback ship-as-is (Codex quota outage).** **STATUS -> DONE (2026-07-11): all 8 code WIs merged (WI-1/2/3/6b/4/5/6/7-hosts/7-EPUB/8, android/v0.14.x->v0.15.3); implementation complete. Box B review-sheet + annotation backup now done on Android (bookmark half stays #135). Awaiting Gate-5 acceptance (all-5-format chrome + live WebDAV annotation round-trip) -> VERIFIED.** **VERIFIED (2026-07-11): Gate-5 acceptance PASS on emulator-5554 (v0.15.3). Live WebDAV annotation backup->wipe->restore round-trip green (highlight + note restored under ORIGINAL UUIDs over a real rclone server; AnnotationBackupRoundTripConnectedTest tests=1/0). 7 connected chrome suites green = 61 tests / 0 failures / 0 flakes first-try (TxtReaderChromeUiTest 6, PdfReaderChromeUiTest 5, Azw3ReaderChromeUiTest 5, ReaderChromeConnectedTest 6 (EPUB TOC/native-jump/touch-through/dismiss), nav.TocContentsSheetTest 11, AnnotationsReviewSheetTest 14, chrome.ReaderTopChromeTest 14). Real 19MB CJK EPUB on-device: top bar + Contents/Notes/Display bottom chrome, native Readium TOC populated + Contents-jump confirmed, review sheet (All/Highlights/Notes + Share). Evidence: dev-docs/verification/feature-132-20260711.md. Box F still open until #133/#134/#135 VERIFIED; box B still open until #135 bookmark-create VERIFIED.** GH: #1924 |
docs/features.md:186:| 133| **Android find-in-book** (in-reader text search, parity box F pt2) — book-scoped full-text search returning matches grouped by chapter with p.N badges + jump-to-location, a NEW all-hits-in-one-book query shape over #128's existing FTS4 index. | android/app/.../search/* (additive DAO + book-scoped results) + reader top-bar Search entry | Medium | VERIFIED | Deps:[feat:#128, feat:#132] (#128 search index MERGED/VERIFIED; #132 reader top-bar Search entry). Plan `dev-docs/plans/20260710-feature-133-android-find-in-book.md` (Gate-1 draft, ~11 WIs). Design authority (landed): vreader-search.jsx 'This book' scope. **Gate-2 CLEANED round-3 (2026-07-12) — plan v3.1, READY TO BUILD.** 3 rounds (r1: 2C/5H/7M/2L; r2: 2C/2M; r3: 1M — all resolved). Key redesigns from the audits: (1) EPUB search does NOT reuse the FTS index for position — the text-quote-only reconstruction was IMPOSSIBLE (ReadiumLocatorReconstructor.toReadium REQUIRES a nonblank href; no publication-wide text-quote search; sectionIndex is a content-iterator counter, NOT readingOrder index + href never persisted) → EPUB pivots to Readium 3.3.0's own SearchService (Publication.search->SearchIterator->LocatorCollection; verified present + the bundled StringSearchService/IcuAlgorithm default engine in readium-shared-3.3.0-runtime.jar); the FTS index serves TXT/MD only. (2) Occurrence extraction can NOT reuse BuiltQuery.tokens (a flat highlight list, wrong for CJK phrases/prefix/AND) → new additive SearchQueryBuilder.structuredQuery + a dedicated RawOffsetMatcher (raw UTF-16 offsets, phrase/prefix/AND + CJK + surrogate + NFKC) with a RESUMABLE intra-chunk pagination cursor (sectionIndex, chunkOrdinal, id, occurrenceIndex) so append-on-scroll is COMPLETE (no silent hit drop). (3) DB stays v7 (Readium search obviates a href column). (4) No needs-design (p.N omitted matching shipped iOS; indexing=NoResults hint; PDF/AZW3 hidden; jump-failure=sheet-stays-open; truncation surface removed). 12 WIs, each with enumerated files; WI-10/WI-11 serialize the shared AppContainer edit in VReaderApp.kt. Full plan + revision history in dev-docs/plans/20260710-feature-133-android-find-in-book.md. **WI-1 (2026-07-12): merged — book-scoped find-in-book DAO surface added to SearchDao.kt (additive, query-only, NO schema change and NO DB version bump; the live DB @Database is already v8, #135 took it there): matchingChunksPage (cursor page over (sectionIndex, chunkOrdinal, id) strict-greater, s.id = f.rowid, MATCH search_sections_fts, book-scoped), chunkAtOrAfter (INCLUSIVE >= LIMIT 1 — the round-3 resume path so a partially-consumed chunk is not skipped), matchingChunkCount, observeIndexState (Flow). No occurrence logic (deferred WI-3); existing corpus query untouched. Robolectric in-memory Room InBookSearchDaoTest 10/10 (book exclusion, gapless/disjoint/ordered paging, empty last page, s.id=f.rowid, chunkAtOrAfter resume+advance+null, count, index-state Flow) + full JVM suite 881/881. Gate-4 follow-up-recommended (all Low, adjudicated; corrected the plan's stale 'DB stays v7' — live is v8). Feeds WI-6 repository. DOWNSTREAM NOTE: the plan v3.1 says 'DB stays v7' but the live @Database version is 8 — additive-no-migration conclusion unaffected; downstream WI notes should say 'no DB version bump' not pin v7.** **WI-2 (2026-07-12): merged — SearchQueryBuilder.structuredQuery(raw): StructuredQuery? added ADDITIVELY (round-2 Critical-2 half 1): typed QueryUnits (Phrase for a contiguous CJK run, PrefixTerm for the final Latin bareword, Term for AND barewords + quoted FTS keywords) from a SHARED private buildGroupedParts intermediate both ftsQuery + structuredQuery project from — NOT the flat BuiltQuery.tokens (which loses phrase/prefix/AND structure); special-only/blank -> null. ftsQuery + BuiltQuery return byte-for-byte UNCHANGED (existing SearchQueryBuilderTest 13/13 + a 10-input regression asserting exact fts+tokens). New StructuredQuery.kt model; buildFtsParts stayed private (file-private GroupedPart sealed intermediate, safely additive). Pure-JVM StructuredQueryTest green + full JVM suite green. Gate-4 ship-as-is (Codex 1 round). Feeds WI-3 RawOffsetMatcher.** **WI-3 (2026-07-12): merged — RawOffsetMatcher.occurrences(rawChunkText, StructuredQuery, fromOccurrenceIndex, maxThisPage): RawOccurrenceSlice (round-2 Critical-2 half 2): re-scans RAW chunk text by code point for every StructuredQuery occurrence, returning per-occurrence RAW UTF-16 spans (NOT the FTS4 offsets() segmented/byte trap, NOT display-collapsed). Normalization (NFKC full-width->half, case-fold, ss/ß, combining-mark strip) at COMPARISON time only — a length-changing fold never shifts the raw span; surrogate pairs never split; Phrase spans TIGHT (关于编程的书 + 编程 -> 编程 only); PrefixTerm boundary + Term whole-token; word boundaries mirror FTS unicode61 (punctuation separator; NFKC-fold-to-token compat chars stay in-word); overlapping-match dedupe (leftmost non-overlapping); folded-only-no-anchor -> 0 (head fallback). RESUMABLE within a chunk: fromOccurrenceIndex/maxThisPage page window + nextOccurrenceIndex (null=exhausted) so append-on-scroll is COMPLETE (40-occurrence chunk with maxThisPage=10 retrieved IN FULL across 4 gapless/dupe-free pages, 4th nextOccurrenceIndex=null); enumeration naturally bounded (each iteration advances >=1 UTF-16 unit) so NO artificial cap and NO truncation. New InBookSearchModels.kt (RawOccurrence, RawOccurrenceSlice, SearchCursor). Pure-JVM RawOffsetMatcherTest green + full JVM suite green. Gate-4 3 rounds all resolved (r1 block caught the FTS-unicode61 word-boundary Critical, follow-up-recommended). Feeds WI-4 TXT/MD resolver + WI-6 repository.** **WI-4 (2026-07-12): merged — TXT/MD hit resolver: NEW InBookSearchHitResolver interface (FTS-track resolver seam WI-6 dispatches to; EPUB resolves natively via Readium in WI-5, not this seam) + TxtMdInBookHitResolver mapping a matched chunk + RawOccurrence to a jumpable canonical Locator via charOffsetUTF16 = TxtDocument.offsetForChunk(sectionIndex) + rawOccurrence.startUtf16 (the round-2 Critical-2 deterministic re-derivation — no stored offset column; TxtDocument.of re-derives the same boundaries the FTS extractor used), fingerprintKey identity + validatedOrNull(); out-of-range sectionIndex/occurrence rejected BEFORE the offset math (offsetForChunk clamps + validatedOrNull only checks non-negativity/ordering) so a bogus/clamped jump is impossible. Pure-JVM TxtMdInBookHitResolverTest green (real TxtMdTextExtractor.extract round-trip returns the same chunk, exact charOffsetUTF16, CJK offset exact UTF-16 not byte, validatedOrNull non-null with correct fingerprint, edge/first/last chunk, md parity, out-of-range rejects) + full JVM suite green. Gate-4 ship-as-is (2 rounds; r1 block caught tests-not-driving-the-real-extractor + missing bounds check). Feeds WI-6 repository.** **WI-5 (2026-07-12): merged — EpubInBookSearchEngine over Readium's OWN SearchService (round-2 Critical-1 resolution: EPUB search/position does NOT use the FTS index). Behind a mockable PublicationSearchSource seam (Readium Publication is final, mirroring #135 PublicationLocatorSource): isSearchable gate (extension property; not searchable -> Unsupported, no iterator opened) -> publication.search(query) (nullable SearchIterator? -> null = immediately-exhausted) -> next() -> Try<LocatorCollection, SearchError> pages -> each Locator mapped to an EpubInBookHit (group by Locator.title chapter first-seen order, snippet from Locator.text.highlight + before/after all @Nullable orEmpty, raw readiumLocator retained for navigator.go jump); exhaustion -> moreAvailable=false; SearchError -> Error (surfaced); CJK passes through verbatim. Paging COMPLETE + resumable (round-3): a page over budget carries an EpubSearchCursor (live iterator + un-placed leftover) with idempotent close + atomic single-consumption (Gate-4 round-2 lifecycle fixes). Engine-only self-contained EPUB result types (EpubInBookHit/EpubGroup/EpubSearchPage/EpubSearchOutcome/EpubSearchCursor); WI-6 adapts to the shared DTOs. Pure-JVM EpubInBookSearchEngineTest green (fake seam, real Readium Locator/Locator.Text value types via Robolectric) + full JVM suite green. Gate-4 3 rounds ship-as-is (r1 Critical paging data-loss -> r2 2 Highs cursor-leak+reuse-race -> r3 clean). ACCEPTED-LOW: engine file ~348 lines (>300 soft guideline, cohesive; a split needs orchestrator regen). Feeds WI-6 repository (EPUB path) + WI-11 EPUB host wiring.** **WI-6 (2026-07-12): merged — InBookSearchRepository, the format-dispatch integrator that unifies WI-1..WI-5 behind one book-scoped search entry point returning the shared DTOs (InBookHit/InBookGroup/InBookSearchPage/InBookSearchOutcome added to InBookSearchModels.kt). EPUB -> EpubInBookSearchEngine (WI-5): the raw Readium locator is carried as readiumLocatorJson (String?, keeping the models file pure-JVM), the live SearchIterator held behind SearchCursor.Epub for resumable append-on-scroll, exposed closeAllEpubCursors() for reader-session dismiss + a Codex-r1 fix that closes abandoned/superseded iterators. TXT/MD -> the FTS pipeline (SearchDao book-scoped page -> RawOffsetMatcher occurrences -> TxtMdInBookHitResolver canonical Locator), grouped by Section in first-seen order, resume-within-chunk (SearchCursor.Fts occurrenceIndex) so a partially-consumed chunk is completed not skipped. Blank / special-only query -> NoResults with NO DAO call. Injected CoroutineDispatcher + ensureActive() cancellation guards throughout. Robolectric InBookSearchRepositoryTest 15/15 (format dispatch, EPUB cursor lifecycle + closeAll, FTS grouping/paging/resume, blank short-circuit, cancellation) + full JVM suite 968/968. Gate-4 ship-as-is (Codex 2 rounds; r1 caught an EPUB iterator leak). Feeds WI-8 ViewModel.** **WI-7 (2026-07-12): merged — search/IndexStateGate.kt -> a sealed InBookIndexState (Ready / Indexing / NoResults / Unsupported / Failed; Unsupported hides the Search entry) + a pure classify() ladder + an observe(format, bookKey, hasOccurrence, indexStateFlow) Flow the WI-8 ViewModel collects so a held query re-runs on settle. State mapping (TXT/MD): missing OR stale indexerVersion -> Indexing; current-version failed -> Failed (retryable); current-version indexed + >0 occ -> Ready, +0 -> NoResults; current-version skipped_unsupported -> Unsupported. EPUB-bypass invariant: EPUB always Ready, never subscribes to the FTS flow (Readium searches live); PDF/AZW3 -> Unsupported. Staleness MIRRORS SearchIndexCoordinator.isEligible exactly: version-staleness dominates (a stale row of any status is re-indexed -> Indexing), and a current-version UNEXPECTED status maps to Failed (not forever-Indexing) since isEligible never retries it (Gate-4 High, fixed r1). 25 JVM tests green; RUN-ANDROID-TESTS RESULT: SUCCEEDED (targeted InBookIndexStateTest + full :app:testDebugUnitTest). Gate-4 Codex 2 rounds -> ship-as-is. Feeds WI-8 ViewModel.** **WI-8 (2026-07-12): merged — InBookSearchViewModel state machine over WI-6 repo + WI-7 gate. UI state = InBookSearchScreenState(query, recents, content) where content sealed = Idle/Loading/Indexing/Results(groups,moreAvailable)/NoResults/Unsupported/Error (+hidesSearchEntry). 250ms debounce -> flatMapLatest(cancel-prior) -> IndexStateGate.observe; stale-tag + generation-token discard of superseded/dismissed sessions. TXT/MD Indexing held-query auto-re-runs on index settle (no re-type); EPUB bypasses Indexing. loadMore() single-flight, threads nextCursor for BOTH tracks (Fts + Epub) and coalesces same-section groups -> append complete, no gap/dup, moreAvailable=false stops. Global RecentSearchesStore reuse (record on commit, surface list; store owns dedupe/cap-8). closeAllEpubCursors() on empty-reset/dismiss/onCleared -> no Readium iterator leak (one repo instance/session). Split into InBookSearchViewModel.kt + InBookSearchViewState.kt (both <300 lines). 27 JVM tests; RUN-ANDROID-TESTS RESULT: SUCCEEDED (full module 1017 tests 0 fail). Gate-4 Codex 3 rounds -> follow-up-recommended (ACCEPTED-LOW: bounded stale-EPUB-cursor hold reaped at next beginSession/onCleared; the repo exposes only a close-ALL seam, so a precise per-session close is deferred to a WI-6 follow-up). Feeds WI-9 sheet.** **WI-9 (2026-07-12): merged — InBookSearchSheet + InBookSearchField + InBookSearchRows + InBookSearchStates built to vreader-search.jsx 'This book' scope (rule 51, no invented UI; the out-of-scope 'All books' scope toggle + 'Try searching' helper are intentionally omitted). Renders the WI-8 InBookSearchScreenState -> autofocus query pill (search / input / clear / 48dp Cancel), grouped chapter headers with 'N matches in M chapters' summary + per-group counts + tinted containers + 0.5dp separators, snippet rows bolded from InBookHit.matchRanges (surrogate-safe), recents (tap fills query via onPickRecent), TXT/MD Indexing hint, NoResults empty state; Loading/Error/Unsupported render no invented body (rule 51, library SearchScreen precedent). onJump dismisses only on JumpResult.Succeeded (Failed keeps sheet open, no error surface); append-on-scroll fires onLoadMore when the tail group nears the viewport, re-arming on (lastGroupIndex, lastGroupHitCount) for coalesced same-group pages, gated by moreAvailable, no disclosure row. testTags inbook-search-sheet/-field/-cancel/-clear/-result-g-i/-group-g/-results-summary/-no-results/-indexing/-recent-i. 18 instrumented Compose tests; the androidTest set COMPILES + full JVM unit suite green via scripts/run-android-tests.sh (RUN-ANDROID-TESTS RESULT: SUCCEEDED) -> the live render rides WI-10/WI-11 host wiring + WI-12 acceptance. Gate-4 Codex 3 rounds -> follow-up-recommended (High surrogate-split + Mediums: invented accent border, missing design structure, append re-arm, 48dp targets all fixed). Feeds WI-10/WI-11 host wiring.** **WI-10 (2026-07-12): merged — TXT/MD host wiring: top-bar Search slot filled (previously null); InBookSearchSheet mounted from TxtReaderActivity; per-session InBookSearchViewModel (ONE per reader open, built from the already-decoded reader text, closeAllEpubCursors/onCleared lifecycle on teardown + onDismiss on sheet close); hit-jump resolves canonicalLocator.charOffsetUTF16 via the existing chunkForOffset scroll seam (txtBookmarkScrollTarget range-guard -> Succeeded, out-of-range -> Failed sheet stays open); EPUB engine seam is an error-throwing guard, never reached for txt/md (EPUB-seam-null-safe); Search icon hidden only on the WI-7 Unsupported gate (no dead control); minimal additive VReaderApp.inBookSearchViewModel factory so WI-11 rebases cleanly; MD parity via the same host. Connected TxtFindInBookTest compiles + JVM suite green (RUN-ANDROID-TESTS RESULT: SUCCEEDED); live emulator run rides WI-12. Gate-4: 2 Codex rounds -> ship-as-is (round-1 Medium resolved, residual Lows = WI-12 test-strength debt). Feeds WI-11 EPUB host + WI-12 acceptance.** **WI-11 (2026-07-12): merged — EPUB host wiring (final host WI): EpubTopBand.onSearch added (icon hidden when hidesSearchEntry -> non-searchable publication), sheet in the sheetLayer ComposeView (open-only -> touch-through preserved), per-session InBookSearchViewModel over the LIVE Readium publication via new VReaderApp.epubInBookSearchViewModel factory wiring the WI-6 repository EPUB branch to EpubInBookSearchEngine(publication) (WI-5 production constructor over the real publication -> Readium SearchService, NOT the FTS index); the FTS branch is error-guarded (never invoked for EPUB), IndexStateGate bypasses EPUB. Hit-jump via Locator.fromJSON(readiumLocatorJson) -> navigator.go (Succeeded dismisses / Failed keeps open, no invented error surface); null/blank/malformed locator un-jumpable -> Failed not crash. One-VM-per-session + closeAllEpubCursors on dismiss (VM.onDismiss) AND onDestroy (VM.onCleared, BEFORE publication.close so the live SearchIterator never leaks). Reused WI-5 EpubInBookSearchEngine(publication) rather than a duplicate adapter (no dead code). Connected EpubFindInBookTest compiles + JVM unit suite green (RUN-ANDROID-TESTS RESULT: SUCCEEDED); connected + real-CJK-EPUB slice rides WI-12. Gate-4 Codex ship-as-is (round 1): 0 Critical/High/Medium; 3 test-file Lows fixed/accepted. docs-sync applied (architecture.md Android reader + README Reader feature). **STATUS -> DONE (2026-07-12): all 11 implementation WIs merged (WI-1..WI-11, android/v0.17.x -> v0.18.0); in-book find-in-book is code-complete + user-reachable across TXT/MD/EPUB (PDF/AZW3 Search hidden). Awaiting Gate-5 acceptance (WI-12: real-CJK find on TXT/MD/EPUB + PDF/AZW3 no-icon on emulator-5554) -> VERIFIED.**** **WI-12 test (2026-07-12): merged — SearchHiddenOnPdfAzw3Test asserts chrome-search absent on PDF + AZW3 host chromes (IndexStateGate Unsupported -> no onOpenSearch into ReaderChromeScaffold); positive controls (reader-top-chrome/chrome-back/chrome-notes) confirm the chrome rendered. androidTest compiles + JVM suite green; rides the WI-12 Gate-5 acceptance on emulator-5554. Gate-4 Codex ship-as-is (1 round).** **WI-13 (test-hardening, 2026-07-12): merged — the connected find-in-book suites (TxtFindInBookTest/EpubFindInBookTest) were async-mis-synchronized (waitForIdle did NOT await the 250ms VM debounce + index-state gate recompute) -> replaced waitForIdle-then-immediate-assert with bounded compose.waitUntil(5s) polls on the awaited node (result row / no-results body / gate-driven icon removal) mirroring the EPUB awaitFirstHit helper; unsupportedGate now types a query so the gate actually recomputes to Unsupported; the EPUB dismiss test dropped a false 'returns to Idle' assertion (onDismiss keeps the query, does NOT reset content -> verified against the VM + its dismiss_closesEpubCursors unit test) for the real vmSurvives contract (build-count unchanged + live queryable state). NO product change. Connected gate GREEN 14/0 (Txt 6/0, Epub 6/0, PdfAzw3 2/0) on emulator-5554 (orchestrator independent re-run also 14/0); JVM suite green. Gate-4 SHIP-AS-IS (2 rounds). This is the Gate-5 acceptance substantiation for the TXT/MD + EPUB find flows.** **VERIFIED (2026-07-12): Gate-5 acceptance PASS on emulator-5554 (v0.18.2, HEAD 84e6b2d5). The 3 find-in-book connected suites GREEN 14/0 (TxtFindInBookTest 6/0 = Search icon + type->grouped hits->tap->scroll-to-offset + zero-hit->NoResults + out-of-range->Failed + MD parity; EpubFindInBookTest 6/0 against the REAL Readium SearchService = grouped hits + navigator.go lands + null/malformed-un-jumpable-not-crash + one-VM-per-session; SearchHiddenOnPdfAzw3Test 2/0 = PDF/AZW3 Search hidden). Real 18MB CJK EPUB on-device: EPUB top-band Search icon + working search sheet confirmed. CJK correctness unit-verified (RawOffsetMatcher/EpubInBookSearchEngine/TxtMdInBookHitResolver). Documented modality gap: real-book CJK keystroke query->jump not adb-drivable (no ADBKeyboard IME; a 3rd-party IME install declined per rule 54) — covered by the unit CJK + the identical connected EPUB flow + the real-book entry smoke. Evidence: dev-docs/verification/feature-133-20260712.md. Box F pt2 complete.** GH: #1925 |
docs/features.md:187:| 134| **Android reader More menu + book details + share** (parity box F pt3) — the reader More-menu popover + Book Details sheet + share, extending #132's chrome. | android/app/.../reader More-menu + BookDetailsSheet (extends #132 ReaderChromeState/ReaderSheet) | Medium | VERIFIED | Deps:[feat:#132] (HARD — ReaderTopChrome/ReaderChromeScaffold/ReaderChromeState land in #132; author line soft-deps #128 DONE). Plan `dev-docs/plans/20260710-feature-134-android-more-menu-book-details-share.md` (Gate-1 v3). Design authority (landed): vreader-more.jsx + vreader-book-details.jsx; generated-cover fallback design gate #1905 CLOSED. **Gate-2 SIGNED OFF (2026-07-11): round-1 audit = 4 findings (3 High, 1 Medium, all in the #132 chrome-extension coordination, core model assumptions verified correct); plan v3 corrected the ReaderChromeScaffold signature, enumerated all 4 exhaustive when(sheet) Details edit sites + the token round-trip, pinned moreMenuSlot-supersedes-onMore, named the EpubTopBand/EpubReaderSheets EPUB sites; round-2 re-audit CLEAN (Gate-3 ready). Codex quota-down -> independent fresh-subagent auditor per rule-47 manual fallback. READY TO BUILD.** **WI-1 (2026-07-11): merged — Book Details model foundation: BookDetailsUiModel + pure BookDetailsMapper (fingerprintFull==fingerprintKey + middle-truncated display, size 0/-1->Unknown + Long.MAX_VALUE-safe, format label per BookFormat md->Markdown, null author/location omitted, pagesLabel only when pageCount supplied, NO year/cover/tags) + CollectionDao.collectionNamesForBook join query (ordered names, empty when none). JVM + in-memory Room BookDetailsMapperTest (23 cases) green. Gate-4 ship-as-is (manual-fallback; Codex quota-limited). First #134 WI; feeds WI-4 BookDetailsSheet + WI-5 host wiring.** **WI-2 (2026-07-11): merged — FileProvider + share plumbing (foundational): res/xml/file_paths.xml grants ONLY filesDir/books; AndroidManifest FileProvider BookFileProvider (exported=false, grantUriPermissions, authority com.vreader.app.fileprovider); BookFileProvider DISPLAY_NAME reports title.ext for Unicode/CJK/illegal/all-illegal titles per BookFormat WITHOUT renaming the on-disk file; BookShareIntent.shareBookFileIntent builds ACTION_SEND with the content URI + per-format MIME + FLAG_GRANT_READ_URI_PERMISSION + ClipData; path-outside-books rejected (canonical-path prefix check + FileProvider IllegalArgumentException); ActivityNotFoundException/no-receiver -> silent no-op. Robolectric BookShareIntentTest + BookFileProviderDisplayNameTest green. Gate-4 ship-as-is (manual-fallback — Codex quota-exhausted). Feeds WI-5 host wiring.** **WI-3 (2026-07-11): merged — MorePopup + MoreRow (implements vreader-more.jsx, rule 51): the anchored top-right More popover over a MoreRow model (Action/Toggle/Disabled, MoreActionId DETAILS/SHARE/TTS/AUTO_TURN/BILINGUAL); renders ONLY supplied rows (unsupplied id ABSENT - no dead TTS/AutoTurn/Bilingual/Export rows, the more-row-ownership contract; no EXPORT id at all); Action fires onTap (chevron), Toggle reflects on + onToggle (switch), Disabled non-interactive + subText; backdrop-tap dismiss; TopEnd anchor flips under RTL, width clamps on narrow screen; reuses the ReaderTheme token map. Instrumented MorePopupTest compiles (live Compose run rides WI-6 acceptance). Gate-4 ship-as-is (manual-fallback, Codex quota-exhausted). Feeds WI-5 host wiring.** **WI-4 (2026-07-11): merged — BookDetailsSheet + BookDetailsRows (implements vreader-book-details.jsx, rule 51): non-interactive stacked details sheet over WI-1's BookDetailsUiModel; meta rows (title/author/format/size/location/pages/fingerprint/collections) each absent when its model value null/empty; copy-fingerprint invokes onCopyFingerprint with fingerprintFull (the FULL canonical key, not the truncated display); share invokes onShare; Location read-only. ABSENCE invariants held (Design-gate #1): NO cover art, NO Tap-to-add-cover placeholder, NO Export, no author-when-null, no tag-when-empty, no Pages-when-null. Tag chips wrap (FlowRow); Share row has the designed chevron. Instrumented BookDetailsSheetTest compiles (14 tests; live Compose run rides WI-6). Gate-4 ship-as-is (2 rounds; Codex ran). Feeds WI-5 host wiring.** **WI-5 (2026-07-11): merged — More-menu host wiring (the integrator): added ReaderSheet.Details + its token/sheetFromToken round-trip; ReaderChromeScaffold + EpubReaderChrome take a bookDetails param + render BookDetailsSheet on the Details route (null-model normalizes to None so the EPUB fragment dismiss overlay never blocks Readium touch-through — Gate-4 P1 fix); top-bar More button now shows WI-3 MorePopup (Details + Share rows only via one shared internal readerMoreRows() assembler — no dead TTS/AutoTurn/Bilingual/Export) across all 4 hosts (TxtReaderActivity TXT+MD, Azw3ReaderActivity, PdfReaderScreen/PdfReaderActivity, ReaderActivity/EpubReaderChrome); each host builds BookDetailsUiModel via BookDetailsMapper + collectionNamesForBook; Details opens the sheet, Share launches BookShareIntent for the on-disk book file (graceful no-receiver), copy-fingerprint copies fingerprintFull to the OS clipboard (no custom toast, rule 51). Both source sets compile + JVM tests (ReaderChromeStateSaverTest details round-trip, ReaderMoreRowsTest) green; live Compose/connected run rides WI-6 acceptance. Gate-4 ship-as-is (2 rounds; Codex ran, round-1 caught the touch-through P1). ORCHESTRATOR NOTE (rule-55 batch evidence): the lane edited PdfReaderActivity.kt (18-line host-model wiring mirroring the other 3 hosts) which the brief write-set under-declared (named PdfReaderScreen.kt only; the PDF host is split Activity+Screen) — surfaced not silent, on-platform reader-host file, no orchestrator surface, ACCEPTED. Feature code-complete; WI-6 = acceptance -> DONE -> VERIFIED.** **WI-6 / VERIFIED (2026-07-11): Gate-5 acceptance PASS on emulator-5554 — all 5 code WIs merged (android/v0.16.0), feature DONE then VERIFIED. Verifier ran the deferred live Compose/connected suites + real-book end-to-end on TWO CJK formats (19.4 MB EPUB via Readium + 14.1 MB TXT): More menu shows exactly Details + Share on both hosts (no dead TTS/AutoTurn/Bilingual/Export), Details opens the Book Details sheet with correct real metadata + absence invariants (no cover art, no Export, TXT omits author/pages/collections), Share launches the system chooser with the correct book filename, and copy-fingerprint's live clipboard overlay showed the FULL canonical key (epub:1f5aecb8659d9033…, not the truncated display). Connected suites all green: BookDetailsSheetTest 14/0, MorePopupTest 11/0, ReaderChromeScaffoldTest 11/0, EpubReaderChromeTest 3/0, PdfReaderChromeUiTest 5/0 regression (44/0 total). WI-6a: Gate-5 caught a test-authoring bug (both rendersAcrossThemes tests looped compose.setContent -> IllegalStateException; NO product defect) -> fixed single-setContent-per-test, Gate-4 ship-as-is (Codex 019f515b), shipped android/v0.16.1 (PR #1949); both suites re-run green. Evidence dev-docs/verification/feature-134-20260711.md. Box F pt3 complete.** GH: #1926 |
docs/features.md:188:| 135| **Android reader bookmarks — create / toggle / list / jump** (parity box F, split from #132) — box F hardest coupled sub-problems: canonical->Readium locator reconstruction, awaited AZW3 foliate goTo, the bookmark unique-index migration. | android/app/.../reader bookmark locator reconstruction + foliate awaited-goTo + TOCSheet Bookmarks tab + unique-index migration | Medium | VERIFIED | Deps:[feat:#132] (#132 wires the annotations.json bookmark backup already; #135 needs no backup change). Plan `dev-docs/plans/20260710-feature-135-android-bookmarks.md` (Gate-1 v2, ~21 WIs). Design authority (landed): vreader-reader.jsx toggle + vreader-panels.jsx Bookmarks tab; row-deletion design gate #1903 CLOSED (deletion DESIGNED but deferred to a follow-up WI — #135 scoped to create/toggle/list/jump). **Gate-2 SIGNED OFF (2026-07-11): round-1 audit = 6 findings (2 High, 4 Medium; core design sound + API-grounded); plan v2 fixed the stale DB version (v5->v7, migration MIGRATION_7_8), removed the duplicate insertBookmarkIfAbsent declaration (reuse #132 WI-6b's), corrected linkWithHref(Url) + cited the locatorFromLink->copyWithLocations reconstruction seam, reworded the #1903-closed delete design. Round-2 re-audit CLEAN: awaited AZW3 goTo rides the existing secure post()/addWebMessageListener channel (never addJavascriptInterface); migration dedupe-before-unique-index. Codex quota-down -> independent fresh-subagent auditor per rule-47 manual fallback. READY TO BUILD.** **WI-1 (2026-07-11): merged — ReadiumLocatorReconstructor(expectedFingerprintKey, publication).toReadium(canonical): Readium Locator? via the faithful seam Url(href)?->linkWithHref(Url)->locatorFromLink(Link)->copyWithLocations(progression, fragments=cfi?) (+ text from textQuote/textContext via .copy(text=Locator.Text)), mirroring ReadiumTocProvider's extracted PublicationLocatorSource seam (Publication is final/unmockable). Kept SEPARATE from the pure-JVM Readium-free ReadiumLocatorBridge. Identity gate FIRST (Gate-4 fix): a canonical whose fingerprintKey differs from the book's is rejected before any publication access, so a bookmark for a different book cannot resolve a coincidentally-matching href. EVERY other degrade -> null so the caller keeps the bookmark sheet open (null Url, null linkWithHref, null locatorFromLink, structurally-invalid). Robolectric ReadiumLocatorReconstructorTest 14/0 (resolvable->valid, cfi->fragments, textQuote->text, all null-degrade paths incl. fingerprint-mismatch-asserts-seam-not-invoked, round-trip). Gate-4 codex 2 rounds ship-as-is (round-1 block on the missing fingerprint guard, fixed). First #135 WI; feeds WI-7 EPUB bookmark jump + WI-8 backup-restored jump.** **WI-3 (2026-07-11): merged — atomic bookmark toggle + unique-index migration. BookmarkEntity gains a composite UNIQUE @Index([bookKey, profileKey]) so re-bookmarking the same position is idempotent; DB version 7->8 with MIGRATION_7_8 that DEDUPES duplicate loser rows (deterministic winner: greatest updatedAt, then createdAt, then lowest bookmarkId) BEFORE CREATE UNIQUE INDEX index_bookmarks_bookKey_profileKey (matching Room's generated name/cols, 8.json validated) so a pre-existing duplicate can't fail the migration; MIGRATION_7_8 appended to ALL_MIGRATIONS. Daos.toggleBookmark (@Transaction, REUSES the pre-existing insertBookmarkIfAbsent; decides add-vs-remove by POSITION PRESENCE via findBookmarkByProfile, re-keys on a bookmarkId PK collision so Added is truthful) + findBookmarkByProfile/deleteBookmarkByProfile/isBookmarked; AnnotationsRepository.toggleBookmark/isBookmarked + BookmarkToggleResult. In-memory Room + migration harness green (Robolectric): 7->8 dedupe (winner survives, losers deleted, other tables preserved, index rejects new dup) + clean 7->8, toggle add->one/again->zero, concurrent/repeat add->exactly one (idempotent), isBookmarked presence, id-collision truthful-Added regression (11+10 tests). Gate-4 follow-up-recommended (2 correctness findings fixed over 3 rounds; sole residual an accepted-Low ~1-in-2^122 double-UUID-collision). Feeds WI-5 top-bar toggle + WI-7 host wiring.** **WI-4 (2026-07-11): merged — per-format bookmark presentation projection (pure, read-time): BookmarkPresentation.bookmarkRow(record, format, tocIndex?, previewProvider?, dateRenderer) -> BookmarkRowUi(preview?, chapter?, pageLabel?, dateLabel). EPUB/AZW3 chapter = nearest-at-or-above via a PREVALIDATED BookmarkTocIndex (built once from the TOC in a single up-to-O(n) pass validating totalProgression completeness+monotonicity; each lookup O(log n) binary search when monotonic, else an href-exact fallback picking the greatest progression at-or-below — huge-book safe + correct for partial/out-of-order TOCs) + page label from the TOC entry. PDF = one-based p.N (valid non-negative non-overflow only). TXT/MD preview = BookmarkPreviewProvider.snippet clamped <=120 single-line ellipsized. Deterministic dateLabel via an injected BookmarkDateRenderer (zone+formatter, no now()/default-locale). Absence-safe: no TOC / no provider / null-or-negative offset -> null fields, no crash; nothing stored (derived every call). fun interface BookmarkPreviewProvider (pure read contract). Pure-JVM BookmarkPresentationTest 29/0. DESIGN REFINEMENT vs plan: bookmarkRow takes BookmarkTocIndex? not List<TocEntry>? (Gate-4-required for correct O(log n) lookup); WI-6/WI-7 host builds the index once. Gate-4 ship-as-is (3 rounds; Codex caught the non-monotonic binary-search key + hrefFallback ordering). Feeds WI-6 Bookmarks surface + WI-7 host wiring (TXT supplies the provider).** **WI-2 (2026-07-11): merged — awaited AZW3/foliate goTo bridge. FoliateBridge.goTo(target): Azw3GoToResult mints a request id, evals the JSON-escaped (jsString) shell-shim call window.__vreaderGoTo(id,target), suspends on a CompletableDeferred keyed by id resolved by a matching goto-ack; withTimeoutOrNull(~3s) -> Timeout (entry cleared in finally, no leak); a caller cancellation OR supersede also clears the entry + completes the orphan (Gate-4 F1); a superseding goTo cancels the prior (Superseded). FoliateMessage.GoToAck(id, ok, cfi?, fraction?) + strict parser branch (id required, ok JSON-boolean-only, fraction finite-only). Azw3Document.goTo(canonical) derives CFI-first-else-fraction and maps the ack; render-death mid-jump survives document recreation via takePendingGoTo() + run(pendingGoTo=...) seeding the replacement, re-issued ONCE after book-ready (Gate-4 F2, wired by WI-7). Bundle patch: readerAPI.goTo/goToFraction now RETURN view.goTo's promise; reader.html window.__vreaderGoTo awaits it + posts goto-ack (id echoed) on resolve/reject; provenance SHA pin updated (bundle-patch.md Patch 2). SECURITY (#126): ack rides the existing addWebMessageListener vreaderHost channel (shell origin + main-frame only), NEVER addJavascriptInterface, unknown/stale/missing-id acks ignored. JVM FoliateGoToTest (10) + FoliateMessageParser goto-ack green; androidTest Azw3GoToSliceTest compiles (real relocate + render-death carry-across ride WI-7). Gate-4 ship-as-is (2 rounds: block -> ship). Feeds WI-7 AZW3 bookmark jump.** **WI-5 (2026-07-11): merged — top-bar bookmark toggle + Bookmarks route + current-locator state. NEW BookmarkToggleButton (implements vreader-reader.jsx, rule 51: filled Icons.Filled.Bookmark accent when isBookmarked / outline BookmarkBorder ink when not, 18dp icon in a 48dp touch target, a11y content-desc flips Add/Remove) fills #132's reserved topBookmarkSlot iff onToggleBookmark != null (so #132 Contents/Notes-only callers stay back-compatible + the slot is absent when null). ReaderSheet gains a Bookmarks case + its token/sheetFromToken round-trip + Saver (the #134 Details precedent, all 4 exhaustive when sites); ReaderChromeScaffold + EpubReaderChrome gain isCurrentBookmarked/onToggleBookmark/currentLocator params (mirroring annotations/bookDetails nullable defaults). NO undesigned Bookmarks-list surface (that is WI-6 TocBookmarksSheet) — the Bookmarks branch is a documented no-op; the EPUB host normalizes Bookmarks to None BEFORE the dismiss scrim so Readium touch-through is preserved. Params UNWIRED by hosts (WI-7 feeds them). Both source sets compile + JVM ReaderChromeStateSaver bookmarks round-trip 15/0; instrumented BookmarkToggleButtonTest + scaffold slot-absent test compile (live Compose rides WI-9). Gate-4 ship-as-is (Codex round 1, no blocking findings). Feeds WI-6 Bookmarks surface + WI-7 host wiring.** **WI-6 (2026-07-11): merged — Bookmarks surface: two-tab TocBookmarksSheet + review Bookmarks chip/card. NEW TocBookmarksSheet (implements vreader-panels.jsx, rule 51) is a WRAPPER hosting a Contents/Bookmarks tab bar that REUSES #132's TocContentsSheet UNCHANGED as the Contents tab (one-writer serialization — no in-place edit); Bookmarks tab = rows (OUTLINE bookmark icon / italic serif preview / chapter . p.N . date / chevron) rendered from List of BookmarkRowItem (BookmarkRowUi + source BookmarkRecord), tap -> onJumpBookmark + dismiss ONLY on JumpResult.Succeeded (a Failed jump keeps the sheet open, #132 navigation-outcome posture); onJumpBookmark nullable + capability-gated (null host -> review-only non-clickable rows, NO dead rows); empty-state; NO delete affordance (deferred). Declares JumpResult + BookmarkRowItem. ReaderChromeScaffold + EpubReaderChrome Toc arm switch to TocBookmarksSheet + the Bookmarks route opens it on the Bookmarks tab, adding bookmarks/onJumpBookmark nullable-defaulted params (#132 callers stay valid). AnnotationsReviewSheet gains a Bookmarks filter chip + BookmarkCard (vreader-android-annotations.jsx, FILLED icon / serif label / sans meta, capability-gated tap-to-jump). Both source sets compile + JVM suite green; instrumented TocBookmarksSheetTest + review-chip test compile (live Compose rides WI-9). Params UNWIRED by hosts (WI-7 feeds them). Gate-4 ship-as-is (2 rounds: r1 block-recommended caught clickable-dead-rows + filled-vs-outline TOC icon, both fixed). Feeds WI-7 host wiring.** **WI-7 (2026-07-11): merged — host wiring (the integrator, feature lights up): all 5 hosts (ReaderActivity EPUB, TxtReaderActivity TXT/MD, Azw3ReaderActivity, PdfReaderScreen/PdfReaderActivity) feed the chrome isCurrentBookmarked/onToggleBookmark/currentLocator (presence + toggle via repository.isBookmarked/toggleBookmark keyed by the current canonical locator, refreshed after toggle) + bookmarks List of BookmarkRowItem (observeBookmarks -> BookmarkPresentation.bookmarkRow with a BookmarkTocIndex built ONCE per host; TXT supplies the BookmarkPreviewProvider) + onJumpBookmark. Per-host jump: EPUB ReadiumLocatorReconstructor(publication).toReadium -> navigator.go (null/false -> Failed, sheet stays open; the fresh-process/backup-restored jump path); AZW3 Azw3Document.goTo launched off-thread with a SYNCHRONOUS target-validity dismiss decision (azw3JumpDecision — the awaited ~3s goTo cannot block the tap thread/ANR; render-death carry-across takePendingGoTo off the dying doc + run(pendingGoTo=) re-issue once wired in the host DisposableEffect); TXT scroll-to-charOffsetUTF16 (at/past-EOF rejected, Gate-4 R1 High fix); PDF page; out-of-range -> Failed. Dismiss only on JumpResult.Succeeded; NO invented error UI on Failed (rule 51 / #132 navigation-outcome). Both source sets compile + JVM BookmarkHostWiringTest 14/0; per-host instrumented slices (EpubBookmarkNavTest, TxtPdfBookmarkTest) compile — live runs ride WI-9 acceptance. NOTE: host Activity files already >300 lines pre-WI-7 (ReaderActivity 862, TxtReaderActivity 1002, Azw3ReaderActivity 569) — a file-split follow-up warranted, out of this WI's write-set. Gate-4 codex 2 rounds ship-as-is (R1 block on the TXT EOF clamp, fixed). Feeds WI-8 backup-restored jump + WI-9 acceptance.** **WI-8 (2026-07-12): merged — backup-restored bookmark jump + AZW3 nav connected tests (TEST-ONLY, no production change). BookmarkBackupRestoreJumpTest adapts #132's AnnotationBackupRoundTripConnectedTest live-WebDAV pattern for bookmarks: create bookmark -> back up -> wipe -> restore -> ORIGINAL-UUID preserved + canonical position intact -> canonical reconstruction via ReadiumLocatorReconstructor.toReadium resolves to the bookmarked resource + carries progression 0.25 (the fresh-process jump precondition; navigator.go landing rides WI-9) -> re-restore does NOT duplicate on the UUID PK AND a same-position different-UUID local bookmark keeps exactly one row (WI-3 (bookKey,profileKey) unique index via insertBookmarkIfAbsent IGNORE) -> renamed/unresolvable resource reconstructs to null (sheet stays open, rule 51). Azw3BookmarkNavTest: repository toggle create/remove one-row-per-position + presence, the created/listed bookmark threaded through azw3JumpDecision (jumpable->dismiss, un-jumpable->sheet-open) + azw3JumpResult awaited-landing map, render-death carry-across (takePendingGoTo/run re-issue against a real WebView, replacement reaches book-ready) + dead-bundle goTo->Timeout->JumpResult.Failed. androidTest source set compiles + JVM suite green; the LIVE emulator runs ride WI-9 acceptance. Fixtures: bundled minimal.epub (CI-appropriate synthetic, androidTest cannot read gitignored test-books/) + the local real book.azw3 (skips in CI). Gate-4 codex 2 rounds ship-as-is. Feeds WI-9 acceptance (all 5 formats end-to-end + live WebDAV bookmark round-trip).** **WI-8b (2026-07-12): merged — Gate-5-surfaced test-hardening (TEST-ONLY, no production change). A real-emulator Gate-5 acceptance run found the bookmark PRODUCT behavior correct (live-WebDAV backup->restore->jump PASS, EPUB/TXT toggle/list/jump PASS, TocBookmarksSheet 14/0, real-book toggle->filled + per-position presence corroborated) but 3 connected-test defects/gaps blocked a truthful VERIFIED; all fixed: (1) BookmarkToggleButtonTest.contentDescription_flipsWithState called setContent TWICE (the #134 IllegalStateException class the connected run catches, compile/JVM do not) -> single setContent driving a hoisted mutableStateOf flag, asserting the a11y content-desc flips Add<->Remove on the same node; (2) Azw3BookmarkNavTest.toggleAtAzw3Position never seeded the parent BookEntity -> insertBookmarkIfAbsent hit the bookmarks.bookKey->books.fingerprintKey FK (in-memory Room enforces FKs), aborting before assertions -> now seeds a BookEntity so the AZW3 repository create->one-row/remove->zero/same-position-different-UUID->one path ACTUALLY runs; (3) TxtPdfBookmarkTest covered only TXT despite its name -> added PDF-host coverage (render toggle + real top-bar create seam + host jump-decision pdfBookmarkPageTarget in/out-of-range) over the existing synthetic sample-3page.pdf (#115 fixture, no new asset). Live re-run confirmed GREEN: BookmarkToggleButtonTest 6/0, Azw3BookmarkNavTest 5 tests/0 failures (1 render test skipped = gitignored real book.azw3 absent in worktree; the target FK-fix toggle test PASSES), TxtPdfBookmarkTest 3/0. Gate-4 codex 2 rounds ship-as-is. Closes the AZW3-create + PDF verification gaps; feeds WI-9 finalize.** **WI-9 / VERIFIED (2026-07-12): Gate-5 acceptance PASS on emulator-5554 (v0.17.2, build 123, HEAD c7dd97b6). Evidence `dev-docs/verification/feature-135-20260712.md` (result: pass). Headline live-WebDAV bookmark backup->restore->jump round-trip UUID-preserving (BookmarkBackupRestoreJumpTest 1/0/0/0 over a throwaway rclone WebDAV); toggle/list/jump across all 5 formats (EPUB/TXT/MD/AZW3/PDF); TocBookmarksSheet 14/0; BookmarkToggleButtonTest 6/0; Azw3BookmarkNavTest 5/0-fail; TxtPdfBookmarkTest 3/0; real 19MB CJK EPUB + 14MB CJK TXT toggle->filled + per-position presence corroborated. All acceptance criteria met. Row -> VERIFIED; box B (annotations review sheet #132 + bookmark creation #135) COMPLETE; box F "Contents + bookmarks" half done (find-in-book #133 remains). GH #1927 closed.** GH: #1927 |
docs/parity/android-checklist.md:58:  review sheet (#132) + bookmark creation/list (#135); all VERIFIED. Box B COMPLETE.
docs/parity/android-checklist.md:69:  **Box B complete**: the annotations review sheet landed with **#132 VERIFIED 2026-07-11** (`android/v0.15.3`,
docs/parity/android-checklist.md:94:  **IN PROGRESS — split (Gate-2 decision): #129 (GH #1879, PLANNED — Gate-2 clean 3 Codex rounds) is the
docs/parity/android-checklist.md:98:  Box E checks when BOTH #129 AND the layout follow-up are VERIFIED.**
docs/parity/android-checklist.md:106:  Status: **IN PROGRESS** — the chrome shell + Contents/TOC (**#132 VERIFIED 2026-07-11**, `android/v0.15.3`,
docs/parity/android-checklist.md:107:  GH #1924), the More menu + Book Details + Share (**#134 VERIFIED 2026-07-11**, `android/v0.16.1`, GH #1926),
// Purpose: feature #118 WI-2 (#110 Phase 3) — the AI client value types + typed errors, mirroring
// iOS AITypes (AIRequest/AIResponse/AIStreamChunk/AIError). Provider-neutral; the OpenAI vs
// Anthropic wire differences live in the providers.
package com.vreader.app.ai

enum class AiRole { system, user, assistant }

data class AiMessage(val role: AiRole, val content: String)

/** A chat request. `system` is the system prompt (Anthropic carries it top-level; the OpenAI
 *  provider prepends it as a system message). */
data class AiRequest(
    val model: String,
    val messages: List<AiMessage>,
    val temperature: Double,
    val maxTokens: Int,
    val system: String? = null,
)

/** One streamed delta (the incremental assistant text). */
data class AiChunk(val deltaText: String)

/** A one-shot (non-streamed) response. */
data class AiResponse(val text: String)

/** Typed AI failures (HTTP + transport + protocol). */
sealed class AiError(message: String) : Exception(message) {
    object Auth401 : AiError("authentication failed (401) — check the API key")
    object RateLimited429 : AiError("rate limited (429) — try again shortly")
    object Offline : AiError("the provider couldn't be reached")
    object Timeout : AiError("the provider took too long to respond")
    class Http(val code: Int) : AiError("HTTP $code from the provider")
    class Decode(detail: String) : AiError("couldn't parse the provider response: $detail")
    class Stream(detail: String) : AiError("the stream ended abnormally: $detail")
    /** Refused to send the API key over cleartext http:// to a non-local host. */
    object InsecureUrl : AiError("the provider URL must be https:// (won't send the key over cleartext)")
    class Config(detail: String) : AiError("provider misconfigured: $detail")
}

/** Test-connection outcome (the editor's Connection section). */
sealed interface AiTestResult {
    object Ok : AiTestResult
    data class Fail(val error: AiError, val message: String) : AiTestResult
}
// Purpose: Addressable, range-based model of a decoded .txt — feature #111 WI-1.
// Holds ONE backing decoded String and an array of chunk START offsets (UTF-16 code
// units against the RAW text — NO line-ending normalization, so charOffsetUTF16 stays
// exact for resume). Splits at line boundaries (CRLF/CR/LF kept inside the chunk);
// hard-splits a runaway line at maxChunkChars (never mid-surrogate-pair). Visible
// chunk text is materialized on demand (no per-chunk substrings retained). Pure JVM.
package com.vreader.app.reader

class TxtDocument private constructor(
    val text: String,
    private val starts: IntArray,
) {
    /** Number of chunks (0 for empty text). */
    val chunkCount: Int get() = starts.size

    /** The UTF-16 start offset of chunk [index] (clamped to a valid chunk). */
    fun offsetForChunk(index: Int): Int {
        if (starts.isEmpty()) return 0
        return starts[index.coerceIn(0, starts.size - 1)]
    }

    /** The chunk index containing [offsetUtf16] (EOF-clamped); 0 for empty text. */
    fun chunkForOffset(offsetUtf16: Int): Int {
        if (starts.isEmpty()) return 0
        val offset = offsetUtf16.coerceIn(0, text.length)
        // Largest start <= offset (binary search).
        var lo = 0; var hi = starts.size - 1; var ans = 0
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            if (starts[mid] <= offset) { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return ans
    }

    /** The text of chunk [index], materialized on demand from the backing string. */
    fun textForChunk(index: Int): CharSequence {
        if (starts.isEmpty()) return ""
        val i = index.coerceIn(0, starts.size - 1)
        val end = if (i + 1 < starts.size) starts[i + 1] else text.length
        return text.subSequence(starts[i], end)
    }

    companion object {
        const val DEFAULT_MAX_CHUNK_CHARS = 4000

        /**
         * Build a document from already-decoded [text]. Chunk boundaries fall after a
         * line terminator (`\n`, `\r`, or `\r\n` — preserved in the chunk); a line longer
         * than [maxChunkChars] is hard-split, but never between a surrogate pair.
         */
        fun of(text: String, maxChunkChars: Int = DEFAULT_MAX_CHUNK_CHARS): TxtDocument {
            if (text.isEmpty()) return TxtDocument(text, IntArray(0))
            // Primitive growable IntArray (no Int boxing) — a newline-dense 14MB file
            // would otherwise spike tens of MB of boxed Integers + a duplicating copy.
            var starts = IntArray(64)
            var count = 0
            fun push(v: Int) {
                if (count == starts.size) starts = starts.copyOf(starts.size * 2)
                starts[count++] = v
            }
            push(0)
            var i = 0
            var chunkStart = 0
            val n = text.length
            while (i < n) {
                val c = text[i]
                when {
                    c == '\n' -> {
                        i++
                        if (i < n) { push(i); chunkStart = i }
                    }
                    c == '\r' -> {
                        i++
                        if (i < n && text[i] == '\n') i++   // CRLF stays one terminator
                        if (i < n) { push(i); chunkStart = i }
                    }
                    else -> {
                        i++
                        // Hard-split a runaway line, but not mid-surrogate-pair (don't
                        // split right after a high surrogate — its low half follows at i).
                        if (i - chunkStart >= maxChunkChars && i < n && !text[i - 1].isHighSurrogate()) {
                            push(i); chunkStart = i
                        }
                    }
                }
            }
            return TxtDocument(text, starts.copyOf(count))
        }
    }
}
// Purpose: Extract TXT/MD text for the library search index, streaming each TxtDocument chunk to the
// SectionSink — feature #128 WI-3. Serves both `txt` and `md` (raw markdown text; marker-stripping is
// a nice-to-have deferred). Reuses the shipped reader decode/chunk path (TxtDecoder + TxtDocument).
//
// Memory note (Gate-2 round-3 HIGH): this path holds the whole decoded book String (via
// TxtDecoder/TxtDocument) — O(book-size), the ACCEPTED EXISTING reader bound (indexing loads exactly
// what the TXT/MD reader already loads to display the book). It is NOT O(batch). The sink still emits
// chunks incrementally so the DB-write side stays batched.
package com.vreader.app.search

import com.vreader.app.data.Book
import com.vreader.app.reader.TxtDecoder
import com.vreader.app.reader.TxtDocument
import kotlinx.coroutines.CancellationException
import java.io.File

/** Streams a TXT/MD book's TxtDocument chunks to a [SectionSink]; author is always null on Success. */
class TxtMdTextExtractor : BookTextExtractor {

    override suspend fun extract(book: Book, sink: SectionSink): ExtractResult {
        val path = book.localFilePath ?: return ExtractResult.Unsupported
        val file = File(path)
        if (!file.exists()) return ExtractResult.Failed("file not found: $path")
        return try {
            val decoded = TxtDecoder.decode(file)
            val document = TxtDocument.of(decoded.text)
            // Emit one section per chunk; sectionIndex == chunkOrdinal == chunk index (TXT has no
            // sub-resource grouping). Empty text → chunkCount 0 → zero emissions (still Success).
            for (i in 0 until document.chunkCount) {
                sink.emit(
                    BookTextSection(
                        sectionIndex = i,
                        chunkOrdinal = i,
                        title = null,
                        text = document.textForChunk(i).toString(),
                    ),
                )
            }
            ExtractResult.Success(null)
        } catch (e: CancellationException) {
            throw e   // never swallow structured cancellation as a per-book failure
        } catch (e: Exception) {
            ExtractResult.Failed(e.message ?: e.javaClass.simpleName)
        }
    }
}
// Purpose: Extract EPUB text for the library search index via Readium's Publication content service,
// streaming each finished section chunk to the SectionSink — feature #128 WI-3. Genuinely
// bounded-memory (O(batch)): `content.iterator()` yields elements incrementally and only the current
// section's in-progress buffer (+ one ~4 KB chunk) is resident — never `content.elements()` (which
// materializes the whole publication) and never a growing List of all sections.
//
// Key decisions:
// - `publication.content(locator = null)` is NULLABLE (no content service → protected/malformed EPUB)
//   → typed ExtractResult.Unsupported.
// - Section boundary = a change of reading-order resource (Locator.href) OR a Heading-role element
//   (which starts a new titled section). Title = the element Locator's `title`, or the normalized-href
//   TOC lookup (strip fragment + normalize percent-encoding before matching).
// - A long section is chunked at ~4 KB with a UNIQUE monotonic `chunkOrdinal` across the WHOLE book so
//   multiple chunks of one resource never collide on sectionIndex (deterministic first hit — WI-5 SQL).
// - `finally { publication.close() }` on EVERY path (success, unsupported after open, exception) — the
//   sink spans the open publication, so the close must be guaranteed.
package com.vreader.app.search

import com.vreader.app.data.Book
import com.vreader.app.reader.BookOpener
import kotlinx.coroutines.CancellationException
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.content.Content
import org.readium.r2.shared.publication.services.content.content
import java.io.File

/** Extracts EPUB text via Readium's content service, streaming section chunks to a [SectionSink]. */
@OptIn(ExperimentalReadiumApi::class)
class EpubTextExtractor(
    private val bookOpener: BookOpener,
    /** Approx max chunk size in UTF-16 chars before a section is split (deterministic ordinal). */
    private val maxChunkChars: Int = DEFAULT_MAX_CHUNK_CHARS,
) : BookTextExtractor {

    init {
        // A non-positive chunk size would make drainRemaining()/emitFullChunks() make no progress
        // (cut == 0) and loop forever — reject it at construction.
        require(maxChunkChars > 0) { "maxChunkChars must be > 0, was $maxChunkChars" }
    }

    override suspend fun extract(book: Book, sink: SectionSink): ExtractResult {
        val path = book.localFilePath ?: return ExtractResult.Unsupported
        val file = File(path)
        if (!file.exists()) return ExtractResult.Failed("file not found: $path")

        val publication = try {
            bookOpener.open(file)
        } catch (e: CancellationException) {
            throw e   // never swallow structured cancellation as a per-book failure
        } catch (e: Exception) {
            return ExtractResult.Failed(e.message ?: e.javaClass.simpleName)
        }
        try {
            val author = publication.metadata.authors.firstOrNull()?.name
            val content = publication.content(null)
                ?: return ExtractResult.Unsupported   // no content service → metadata-only book
            val tocTitles = tocTitlesByHref(publication)
            streamSections(content, tocTitles, sink)
            return ExtractResult.Success(author)
        } catch (e: CancellationException) {
            throw e   // rethrow cancellation; the finally still closes the publication
        } catch (e: Exception) {
            return ExtractResult.Failed(e.message ?: e.javaClass.simpleName)
        } finally {
            publication.close()
        }
    }

    /**
     * Streams the publication's text via the content iterator, emitting each finished chunk. Groups
     * text by reading-order resource (href) into `sectionIndex`; a Heading role starts a new titled
     * section; a running `chunkOrdinal` is unique across the whole book.
     */
    private suspend fun streamSections(
        content: Content,
        tocTitles: Map<String, String>,
        sink: SectionSink,
    ) {
        val iterator = content.iterator()
        // Mutable extraction state carried across boundaries; the running chunkOrdinal is unique
        // across the whole book, sectionIndex groups a resource's chunks for chapter attribution.
        val state = StreamState()

        while (iterator.hasNext()) {
            val element = iterator.next()
            if (element !is Content.TextElement) continue
            val href = normalizeHref(element.locator.href.toString())
            val isHeading = element.role is Content.TextElement.Role.Heading
            // A resource change OR a heading starts a new section: drain the prior buffer first.
            if (href != state.currentHref || isHeading) {
                drainRemaining(state, sink)
                state.sectionIndex++
                state.currentHref = href
                state.currentTitle = element.locator.title
                    ?: tocTitles[href]
                    ?: if (isHeading) element.text.trim().ifEmpty { null } else null
            }
            val text = element.text
            if (text.isNotEmpty()) {
                if (state.buffer.isNotEmpty()) state.buffer.append('\n')
                state.buffer.append(text)
                // Emit completed chunks from the FRONT as soon as the buffer crosses the threshold,
                // retaining only a short (< maxChunkChars) tail — so at most ~one chunk + tail is
                // resident regardless of the resource size (bounded-memory / O(batch), not O(book)).
                emitFullChunks(state, sink)
            }
        }
        drainRemaining(state, sink)
    }

    /** Emits every completed leading chunk (buffer ≥ maxChunkChars), keeping only the sub-chunk tail. */
    private suspend fun emitFullChunks(state: StreamState, sink: SectionSink) {
        while (state.buffer.length >= maxChunkChars) {
            val end = splitBoundary(state.buffer, maxChunkChars)
            if (end <= 0 || end >= state.buffer.length) break
            emitChunk(state, sink, state.buffer.substring(0, end))
            state.buffer.delete(0, end)
        }
    }

    /** Drains any remaining buffered text for the current section (the partial tail). */
    private suspend fun drainRemaining(state: StreamState, sink: SectionSink) {
        while (state.buffer.length >= maxChunkChars) {
            val end = splitBoundary(state.buffer, maxChunkChars)
            val cut = if (end in 1 until state.buffer.length) end else state.buffer.length
            emitChunk(state, sink, state.buffer.substring(0, cut))
            state.buffer.delete(0, cut)
        }
        if (state.buffer.isNotEmpty()) {
            emitChunk(state, sink, state.buffer.toString())
            state.buffer.setLength(0)
        }
    }

    private suspend fun emitChunk(state: StreamState, sink: SectionSink, chunk: String) {
        if (chunk.isBlank()) return
        sink.emit(
            BookTextSection(
                sectionIndex = state.sectionIndex,
                chunkOrdinal = state.chunkOrdinal++,
                title = state.currentTitle,
                text = chunk,
            ),
        )
    }

    /** The split length for the FIRST chunk of [buffer] (≥ [target]), preferring a newline, never
     *  mid-surrogate-pair. Returns the exclusive end index within `buffer`. */
    private fun splitBoundary(buffer: CharSequence, target: Int): Int {
        val n = buffer.length
        if (n <= target) return n
        var end = target.coerceAtMost(n)
        // Prefer a newline boundary within the last quarter of the chunk for readable snippets.
        val minNl = target * 3 / 4
        val nl = lastNewline(buffer, minNl, end)
        if (nl in 1 until end) end = nl + 1
        // Never split between a high and low surrogate.
        if (end < n && Character.isHighSurrogate(buffer[end - 1])) end++
        return end.coerceAtMost(n)
    }

    private fun lastNewline(buffer: CharSequence, from: Int, to: Int): Int {
        var i = to - 1
        while (i >= from) {
            if (buffer[i] == '\n') return i
            i--
        }
        return -1
    }

    /** Mutable per-book extraction state carried across section boundaries. */
    private class StreamState {
        var chunkOrdinal = 0
        var sectionIndex = -1
        var currentHref: String? = null
        var currentTitle: String? = null
        val buffer = StringBuilder()
    }

    /** Builds an href → TOC title map, normalizing each TOC entry's href the same way. */
    private fun tocTitlesByHref(publication: Publication): Map<String, String> {
        val map = mutableMapOf<String, String>()
        fun walk(links: List<Link>) {
            for (link in links) {
                val title = link.title
                if (!title.isNullOrBlank()) {
                    val href = normalizeHref(link.href.toString())
                    map.putIfAbsent(href, title)
                }
                if (link.children.isNotEmpty()) walk(link.children)
            }
        }
        walk(publication.tableOfContents)
        return map
    }

    /** Strip the fragment and normalize percent-encoding so `chapter1.xhtml#a` matches `chapter1.xhtml`. */
    private fun normalizeHref(href: String): String {
        val noFragment = href.substringBefore('#')
        return try {
            java.net.URLDecoder.decode(noFragment, Charsets.UTF_8.name())
        } catch (e: Exception) {
            noFragment
        }
    }

    companion object {
        const val DEFAULT_MAX_CHUNK_CHARS = 4000
    }
}
vreader/Services/AI/MockAIProvider.swift:103:            // Feature #56 chapter-translation (`TranslationChunkContract`) asks
vreader/Services/AI/MockAIProvider.swift:128:    /// If `prompt` is a `TranslationChunkContract.userPrompt` (N numbered source
vreader/Services/AI/ChapterPrefetching.swift:2:// `BilingualReadingViewModel` depends on. The VM's unit-aware prefetch trigger
vreader/Services/AI/ChapterPrefetching.swift:20:// @coordinates-with: BilingualReadingViewModel.swift,
vreader/Services/AI/ChapterTranslationPrefetcher.swift:29://   BilingualReadingViewModel.swift,
vreader/Services/AI/ChapterTranslationPrefetcher.swift:84:    /// level (TXT/MD: both sides segment through `ChapterSegmenter`, so the
vreader/Services/AI/ChapterTranslationPrefetcher.swift:113:        // through `ChapterSegmenter` (TXT/MD) hold the 1:1 contract at
vreader/Services/AI/ChapterTranslationPrefetcher.swift:196:    /// then `ChapterTranslationService.translatePreSegmented` (no disk cache).
vreader/Services/AI/ChapterTranslationPrefetcher.swift:220:            let out = try await translationService.translatePreSegmented(
vreader/Services/AI/ChapterTranslationPrefetcher.swift:231:            Self.log.error("prefetchDirect translatePreSegmented failed: \(String(describing: error), privacy: .private)")
vreader/Services/AI/ChapterTranslationChunker.swift:15:// @coordinates-with: ChapterSegmenter.swift, ChapterTranslationService.swift,
vreader/Services/AI/ChapterTranslationChunker.swift:21:enum ChapterTranslationChunker {
vreader/Services/Reader/EPUBChapterTextProvider.swift:50:            // service's `ChapterSegmenter.paragraphs` produces one
vreader/Services/AI/TranslationChunkContract.swift:17:// @coordinates-with: ChapterSegmenter.swift, ChapterTranslationChunker.swift,
vreader/Services/AI/TranslationChunkContract.swift:24:enum TranslationChunkContract {
vreaderTests/Services/AI/ChapterTranslationServiceTests.swift:415:    // MARK: - translatePreSegmented (Bug #268 — block-text-direct translation)
vreaderTests/Services/AI/ChapterTranslationServiceTests.swift:417:    @Test func translatePreSegmented_translatesGivenSegments1to1() async throws {
vreaderTests/Services/AI/ChapterTranslationServiceTests.swift:425:        let result = try await service.translatePreSegmented(
vreaderTests/Services/AI/ChapterTranslationServiceTests.swift:438:        _ = try await service.translatePreSegmented(
vreaderTests/Services/AI/ChapterTranslationServiceTests.swift:446:    @Test func translatePreSegmented_emptyInput_returnsEmpty_withNoRequest() async throws {
vreaderTests/Services/AI/ChapterTranslationServiceTests.swift:450:        let result = try await service.translatePreSegmented(
vreaderTests/Services/AI/ChapterTranslationServiceTests.swift:458:    @Test func translatePreSegmented_malformedChunkDecode_fallsBackPerSegment_stays1to1() async throws {
vreaderTests/Services/AI/ChapterTranslationServiceTests.swift:469:        let result = try await service.translatePreSegmented(
vreaderTests/Services/AI/ChapterTranslationServiceTests.swift:726:    /// Bug #343 mechanism (1): `translatePreSegmented` was cache-FREE, so
vreaderTests/Services/AI/ChapterTranslationServiceTests.swift:737:        let out = try await service.translatePreSegmented(
vreaderTests/Services/AI/ChapterTranslationServiceTests.swift:777:        let out = try await service.translatePreSegmented(
vreader/Services/Search/EPUBTextExtractor.swift:82:    /// `ChapterSegmenter.paragraphs` (blank-line-separated). Without
vreaderTests/Services/AI/MockAIProviderTests.swift:95:        let prompt = TranslationChunkContract.userPrompt(
vreaderTests/Services/AI/MockAIProviderTests.swift:100:        let decoded = try TranslationChunkContract.decode(reply, expectedCount: segments.count)
vreaderTests/Services/AI/MockAIProviderTests.swift:112:        let prompt = TranslationChunkContract.userPrompt(
vreaderTests/Services/AI/MockAIProviderTests.swift:115:        let decoded = try TranslationChunkContract.decode(reply, expectedCount: 2)
vreaderTests/Services/AI/MockAIProviderTests.swift:124:        let prompt = TranslationChunkContract.userPrompt(
vreaderTests/Services/AI/MockAIProviderTests.swift:127:        let decoded = try TranslationChunkContract.decode(reply, expectedCount: 3)
vreader/Services/Foliate/JS/foliate-host.js:26:// `ChapterSegmenter.paragraphs`) MUST equal the enumerate path's block count
vreader/Services/Foliate/JS/foliate-host.js:457:            // `ChapterSegmenter.paragraphs` splits on blank lines, so this makes
vreaderTests/Services/AI/TranslationChunkContractTests.swift:1:// Purpose: Tests for TranslationChunkContract — the strict JSON-array prompt +
vreaderTests/Services/AI/TranslationChunkContractTests.swift:6:// @coordinates-with: TranslationChunkContract.swift,
vreaderTests/Services/AI/TranslationChunkContractTests.swift:13:@Suite("TranslationChunkContract")
vreaderTests/Services/AI/TranslationChunkContractTests.swift:14:struct TranslationChunkContractTests {
vreaderTests/Services/AI/TranslationChunkContractTests.swift:19:        let prompt = TranslationChunkContract.userPrompt(
vreaderTests/Services/AI/TranslationChunkContractTests.swift:26:        let prompt = TranslationChunkContract.userPrompt(
vreaderTests/Services/AI/TranslationChunkContractTests.swift:34:        let prompt = TranslationChunkContract.userPrompt(
vreaderTests/Services/AI/TranslationChunkContractTests.swift:44:        let literal = TranslationChunkContract.userPrompt(
vreaderTests/Services/AI/TranslationChunkContractTests.swift:46:        let literary = TranslationChunkContract.userPrompt(
vreaderTests/Services/AI/TranslationChunkContractTests.swift:57:        let result = try TranslationChunkContract.decode(json, expectedCount: 3)
vreaderTests/Services/AI/TranslationChunkContractTests.swift:63:        let result = try TranslationChunkContract.decode(json, expectedCount: 2)
vreaderTests/Services/AI/TranslationChunkContractTests.swift:70:        let result = try TranslationChunkContract.decode(json, expectedCount: 2)
vreaderTests/Services/AI/TranslationChunkContractTests.swift:75:        #expect(throws: TranslationChunkContract.DecodeError.countMismatch(expected: 3, actual: 1)) {
vreaderTests/Services/AI/TranslationChunkContractTests.swift:76:            _ = try TranslationChunkContract.decode(#"["only one"]"#, expectedCount: 3)
vreaderTests/Services/AI/TranslationChunkContractTests.swift:81:        #expect(throws: TranslationChunkContract.DecodeError.countMismatch(expected: 2, actual: 4)) {
vreaderTests/Services/AI/TranslationChunkContractTests.swift:82:            _ = try TranslationChunkContract.decode(#"["a","b","c","d"]"#, expectedCount: 2)
vreaderTests/Services/AI/TranslationChunkContractTests.swift:88:        #expect(throws: TranslationChunkContract.DecodeError.notAStringArray) {
vreaderTests/Services/AI/TranslationChunkContractTests.swift:89:            _ = try TranslationChunkContract.decode(#"["ok", 42]"#, expectedCount: 2)
vreaderTests/Services/AI/TranslationChunkContractTests.swift:94:        #expect(throws: TranslationChunkContract.DecodeError.notAStringArray) {
vreaderTests/Services/AI/TranslationChunkContractTests.swift:95:            _ = try TranslationChunkContract.decode(#"[["nested"], "b"]"#, expectedCount: 2)
vreaderTests/Services/AI/TranslationChunkContractTests.swift:100:        #expect(throws: TranslationChunkContract.DecodeError.notAStringArray) {
vreaderTests/Services/AI/TranslationChunkContractTests.swift:101:            _ = try TranslationChunkContract.decode(#"{"text": "not an array"}"#, expectedCount: 1)
vreaderTests/Services/AI/TranslationChunkContractTests.swift:106:        #expect(throws: TranslationChunkContract.DecodeError.notAStringArray) {
vreaderTests/Services/AI/TranslationChunkContractTests.swift:107:            _ = try TranslationChunkContract.decode("this is not json at all", expectedCount: 1)
vreaderTests/Services/AI/TranslationChunkContractTests.swift:112:        let result = try TranslationChunkContract.decode("[]", expectedCount: 0)
vreaderTests/Services/AI/TranslationChunkContractTests.swift:119:        let result = try TranslationChunkContract.decode(#"["", "real", ""]"#, expectedCount: 3)
vreaderTests/Services/AI/TranslationChunkContractTests.swift:127:        let result = try TranslationChunkContract.decode(json, expectedCount: 2)
vreaderTests/Services/AI/TranslationChunkContractTests.swift:135:        let result = try TranslationChunkContract.decode(json, expectedCount: 2)
vreader/Services/AI/ChapterSegmenter.swift:14:// @coordinates-with: ChapterTranslationChunker.swift,
vreader/Services/AI/ChapterSegmenter.swift:21:enum ChapterSegmenter {
vreader/Services/AI/BilingualAIReadiness.swift:9:// (`BilingualReadingViewModel.aiConfigured`) so its `configured` descriptor
vreader/Services/AI/BilingualAIReadiness.swift:14://   AIConsentManager.swift, BilingualReadingViewModel.swift
vreader/Services/AI/TranslationStyle.swift:3:// folded into the translation chunk prompt by `TranslationChunkContract`, and
vreader/Services/AI/TranslationStyle.swift:7:// @coordinates-with: TranslationChunkContract.swift,
vreader/Services/AI/ResolvedAIProviderConfig.swift:16://   prompt-construction input consumed only by `TranslationChunkContract`
vreader/Services/AI/ChapterTranslationService.swift:14:// - On any chunk decode failure (`TranslationChunkContract.DecodeError`) the
vreader/Services/AI/ChapterTranslationService.swift:20:// @coordinates-with: ChapterTranslationStore.swift, ChapterSegmenter.swift,
vreader/Services/AI/ChapterTranslationService.swift:21://   ChapterTranslationChunker.swift, TranslationChunkContract.swift,
vreader/Services/AI/ChapterTranslationService.swift:134:        case .paragraph: segments = ChapterSegmenter.paragraphs(in: sourceText)
vreader/Services/AI/ChapterTranslationService.swift:135:        case .sentence:  segments = ChapterSegmenter.sentences(in: sourceText)
vreader/Services/AI/ChapterTranslationService.swift:202:        case .paragraph: segments = ChapterSegmenter.paragraphs(in: sourceText)
vreader/Services/AI/ChapterTranslationService.swift:203:        case .sentence:  segments = ChapterSegmenter.sentences(in: sourceText)
vreader/Services/AI/ChapterTranslationService.swift:232:        let chunks = ChapterTranslationChunker.chunk(
vreader/Services/AI/ChapterTranslationService.swift:311:    /// bypassing `ChapterSegmenter`. Used by the bilingual EPUB
vreader/Services/AI/ChapterTranslationService.swift:327:    func translatePreSegmented(
vreader/Services/AI/ChapterTranslationService.swift:337:        let chunks = ChapterTranslationChunker.chunk(
vreader/Services/AI/ChapterTranslationService.swift:412:            let pieces = ChapterTranslationChunker.subSplit(
vreader/Services/AI/ChapterTranslationService.swift:418:                    let piecePrompt = TranslationChunkContract.userPrompt(
vreader/Services/AI/ChapterTranslationService.swift:421:                    if let decoded = try? TranslationChunkContract.decode(
vreader/Services/AI/ChapterTranslationService.swift:433:        let prompt = TranslationChunkContract.userPrompt(
vreader/Services/AI/ChapterTranslationService.swift:436:        if let decoded = try? TranslationChunkContract.decode(
vreader/Services/AI/ChapterTranslationService.swift:447:            let onePrompt = TranslationChunkContract.userPrompt(
vreader/Services/AI/ChapterTranslationService.swift:450:            if let oneDecoded = try? TranslationChunkContract.decode(
vreaderTests/Services/AI/ChapterSegmenterTests.swift:1:// Purpose: Tests for ChapterSegmenter — paragraph + CJK-aware sentence
vreaderTests/Services/AI/ChapterSegmenterTests.swift:4:// @coordinates-with: ChapterSegmenter.swift,
vreaderTests/Services/AI/ChapterSegmenterTests.swift:29:@Suite("ChapterSegmenter")
vreaderTests/Services/AI/ChapterSegmenterTests.swift:30:struct ChapterSegmenterTests {
vreaderTests/Services/AI/ChapterSegmenterTests.swift:35:        #expect(ChapterSegmenter.paragraphs(in: "").isEmpty)
vreaderTests/Services/AI/ChapterSegmenterTests.swift:39:        #expect(ChapterSegmenter.paragraphs(in: "   \n\n  \t ").isEmpty)
vreaderTests/Services/AI/ChapterSegmenterTests.swift:43:        let result = ChapterSegmenter.paragraphs(in: "Just one paragraph here.")
vreaderTests/Services/AI/ChapterSegmenterTests.swift:49:        let result = ChapterSegmenter.paragraphs(in: text)
vreaderTests/Services/AI/ChapterSegmenterTests.swift:55:        let result = ChapterSegmenter.paragraphs(in: text)
vreaderTests/Services/AI/ChapterSegmenterTests.swift:61:        let result = ChapterSegmenter.paragraphs(in: text)
vreaderTests/Services/AI/ChapterSegmenterTests.swift:67:        let result = ChapterSegmenter.paragraphs(in: text)
vreaderTests/Services/AI/ChapterSegmenterTests.swift:75:        let result = ChapterSegmenter.paragraphs(in: text)
vreaderTests/Services/AI/ChapterSegmenterTests.swift:83:        #expect(ChapterSegmenter.sentences(in: "").isEmpty)
vreaderTests/Services/AI/ChapterSegmenterTests.swift:88:        let result = ChapterSegmenter.sentences(in: text)
vreaderTests/Services/AI/ChapterSegmenterTests.swift:99:        let result = ChapterSegmenter.sentences(in: text)
vreaderTests/Services/AI/ChapterSegmenterTests.swift:107:        let result = ChapterSegmenter.sentences(in: text)
vreaderTests/Services/AI/ChapterSegmenterTests.swift:114:        let result = ChapterSegmenter.sentences(in: text)
vreaderTests/Services/AI/ChapterSegmenterTests.swift:121:        let result = ChapterSegmenter.sentences(in: text)
vreaderTests/Services/AI/ChapterSegmenterTests.swift:127:        let result = ChapterSegmenter.sentences(in: text)
vreaderTests/Services/AI/ChapterSegmenterTests.swift:148:        let sentences = ChapterSegmenter.sentences(in: text)
vreaderTests/Services/AI/ChapterSegmenterTests.swift:149:        let ranges = ChapterSegmenter.sentenceRanges(in: text)
vreaderTests/Services/AI/ChapterSegmenterTests.swift:178:        let paragraphs = ChapterSegmenter.paragraphs(in: text)
vreaderTests/Services/AI/ChapterSegmenterTests.swift:186:        #expect(ChapterSegmenter.paragraphs(in: text) == ["第一段。", "第二段。"])
vreaderTests/Services/AI/ChapterSegmenterTests.swift:192:        #expect(ChapterSegmenter.paragraphs(in: "a\r\nb") == ["a\nb"])
vreaderTests/Services/AI/ChapterSegmenterTests.swift:193:        #expect(ChapterSegmenter.paragraphs(in: "a\rb\r\n\r\nc") == ["a\nb", "c"])
vreaderTests/Services/AI/ChapterSegmenterTests.swift:198:        let ranges = ChapterSegmenter.sentenceRanges(in: text)
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:1:// Purpose: Tests for ChapterTranslationChunker — groups translation segment
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:4:// @coordinates-with: ChapterTranslationChunker.swift,
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:11:@Suite("ChapterTranslationChunker")
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:12:struct ChapterTranslationChunkerTests {
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:15:        let chunks = ChapterTranslationChunker.chunk(segments: [], maxCharsPerChunk: 100)
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:20:        let chunks = ChapterTranslationChunker.chunk(segments: ["hello"], maxCharsPerChunk: 100)
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:27:        let chunks = ChapterTranslationChunker.chunk(segments: segments, maxCharsPerChunk: 25)
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:34:        let chunks = ChapterTranslationChunker.chunk(segments: segments, maxCharsPerChunk: 12)
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:43:        let chunks = ChapterTranslationChunker.chunk(segments: segments, maxCharsPerChunk: 100)
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:53:        let chunks = ChapterTranslationChunker.chunk(segments: segments, maxCharsPerChunk: 100)
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:60:        let chunks = ChapterTranslationChunker.chunk(segments: segments, maxCharsPerChunk: 100)
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:67:        let chunks = ChapterTranslationChunker.chunk(segments: segments, maxCharsPerChunk: 100)
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:75:        let chunks = ChapterTranslationChunker.chunk(segments: segments, maxCharsPerChunk: 8)
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:82:        let chunks = ChapterTranslationChunker.chunk(segments: segments, maxCharsPerChunk: 10)
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:92:        let chunks = ChapterTranslationChunker.chunk(segments: segments, maxCharsPerChunk: 0)
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:98:        let chunks = ChapterTranslationChunker.chunk(segments: ["x", "y"], maxCharsPerChunk: -5)
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:105:        #expect(ChapterTranslationChunker.subSplit("hello", maxChars: 10) == ["hello"])
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:106:        #expect(ChapterTranslationChunker.subSplit("", maxChars: 10) == [""])
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:111:        let pieces = ChapterTranslationChunker.subSplit(text, maxChars: 10)
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:119:        let pieces = ChapterTranslationChunker.subSplit("alpha beta gamma", maxChars: 10)
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:126:        let pieces = ChapterTranslationChunker.subSplit(text, maxChars: 10)
vreaderTests/Services/AI/ChapterTranslationChunkerTests.swift:134:        let pieces = ChapterTranslationChunker.subSplit(text, maxChars: 3)
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:1:// Purpose: Tests for BilingualReadingViewModel's WI-7a persistence/state core
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:6:// @coordinates-with: BilingualReadingViewModel.swift,
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:14:@Suite("BilingualReadingViewModel — persistence/state core (WI-7a)")
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:15:struct BilingualReadingViewModelCoreTests {
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:31:        let vm = BilingualReadingViewModel(
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:51:        let vm = BilingualReadingViewModel(
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:65:        let vm = BilingualReadingViewModel(
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:75:        let vm = BilingualReadingViewModel(
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:80:        let reloaded = BilingualReadingViewModel(
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:91:        let vm = BilingualReadingViewModel(
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:95:        let reloaded = BilingualReadingViewModel(
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:107:        let vm = BilingualReadingViewModel(
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:121:        let vm = BilingualReadingViewModel(
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:124:        let reloaded = BilingualReadingViewModel(
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:132:        let vm = BilingualReadingViewModel(
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:135:        let reloaded = BilingualReadingViewModel(
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:145:        let vm = BilingualReadingViewModel(
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:155:        let vm = BilingualReadingViewModel(
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:171:        let vm = BilingualReadingViewModel(
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:180:        let vm = BilingualReadingViewModel(
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:199:        let vm = BilingualReadingViewModel(
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:216:        let vm = BilingualReadingViewModel(
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:226:        let vm = BilingualReadingViewModel(
vreaderTests/ViewModels/BilingualReadingViewModelCoreTests.swift:237:        let vm = BilingualReadingViewModel(

exec
/bin/zsh -lc "rg -n '"'^'"\\| 13[2345]\\|' docs/features.md
rg -n \"bilingualEnabled|bilingualTargetLanguage|bilingualGranularity|PerBookSettingsOverride\" android vreader contracts
rg -n \"readium-navigator|readium.*3\\.3\\.0|readiumVersion\" android gradle* buildSrc settings.gradle.kts -g '*.kts' -g '*.toml' -g '*.gradle' -g '*.properties'
find \""'$HOME/.gradle/caches" -type f '"\\( -name 'readium-navigator-3.3.0.aar' -o -name '*navigator*3.3.0*.aar' \\) 2>/dev/null | head -20" in /Users/ll/workspace/vreader
 succeeded in 1112ms:
/Users/ll/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-navigator/3.3.0/162dd7fdee9e61a10441e5262792ec0d76b6011e/readium-navigator-3.3.0.aar

exec
/bin/zsh -lc "rg -n \"readium-navigator|3\\.3\\.0\" android -g '*.toml' -g '*.kts' -g '*.gradle' -g '*.properties'
find \""'$HOME/.gradle/caches" -type f -path '"'*readium-navigator*3.3.0*' | head -40
AAR=\""'$HOME/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-navigator/3.3.0/162dd7fdee9e61a10441e5262792ec0d76b6011e/readium-navigator-3.3.0.aar"; unzip -l "$AAR" | head -30
find "$HOME/.gradle/caches/transforms-*" -type f -name '"'*.jar' 2>/dev/null | rg 'readium|jetified' | head -30" in /Users/ll/workspace/vreader
 succeeded in 609ms:
/Users/ll/.gradle/caches/modules-2/metadata-2.107/descriptors/org.readium.kotlin-toolkit/readium-navigator/3.3.0/26c913274550a0b2221f47a0fe2d2358/descriptor.bin
/Users/ll/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-navigator/3.3.0/fa9ca42cd2606f432a5843df9cc4953fe808d696/readium-navigator-3.3.0.module
/Users/ll/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-navigator/3.3.0/ec205146a3401ca43792b37bfb4b9b2d51fa6a35/readium-navigator-3.3.0.pom
/Users/ll/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-navigator/3.3.0/162dd7fdee9e61a10441e5262792ec0d76b6011e/readium-navigator-3.3.0.aar
/Users/ll/.gradle/caches/8.14.4/transforms/87fd454872d62994fa2f156d672a8156/transformed/readium-navigator-3.3.0-runtime.jar
/Users/ll/.gradle/caches/8.14.4/transforms/1701b51ad5c53162237bb3eb7c18fd66/transformed/readium-navigator-3.3.0-runtime/readium-navigator-3.3.0-runtime_dex/classes.dex
/Users/ll/.gradle/caches/8.14.4/transforms/20a535398e2b06999431a36d9970924d/transformed/readium-navigator-3.3.0-api.jar
/Users/ll/.gradle/caches/8.14.4/transforms/13046fd0a3da406b28f8af209bcd07d2/transformed/readium-navigator-3.3.0-runtime
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/jars/classes.jar
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/jars/libs/PhotoView-2.3.0.jar
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/res/drawable/readium_media_notification_rewind.xml
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/res/drawable/readium_media_notification_fastforward.xml
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/res/layout/readium_navigator_fragment_fxllayout_single.xml
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/res/layout/readium_navigator_viewpager.xml
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/res/layout/readium_navigator_viewpager_fragment_epub.xml
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/res/layout/readium_navigator_viewpager_fragment_cbz.xml
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/res/layout/readium_navigator_fragment_fxllayout_double.xml
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/res/values-land/values-land.xml
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/res/values/values.xml
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/AndroidManifest.xml
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/META-INF/com/android/build/gradle/aar-metadata.properties
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/R.txt
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/assets/readium/readium-css/ReadiumCSS-before.css
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/assets/readium/readium-css/ReadiumCSS-default.css
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/assets/readium/readium-css/ReadiumCSS-ebpaj_fonts_patch.css
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/assets/readium/readium-css/cjk-vertical/ReadiumCSS-before.css
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/assets/readium/readium-css/cjk-vertical/ReadiumCSS-default.css
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/assets/readium/readium-css/cjk-vertical/ReadiumCSS-after.css
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/assets/readium/readium-css/ReadiumCSS-after.css
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/assets/readium/readium-css/ReadMe.md
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/assets/readium/readium-css/rtl/ReadiumCSS-before.css
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/assets/readium/readium-css/rtl/ReadiumCSS-default.css
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/assets/readium/readium-css/rtl/ReadiumCSS-after.css
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/assets/readium/readium-css/cjk-horizontal/ReadiumCSS-before.css
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/assets/readium/readium-css/cjk-horizontal/ReadiumCSS-default.css
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/assets/readium/readium-css/cjk-horizontal/ReadiumCSS-after.css
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/assets/readium/readium-css/fonts/AccessibleDfA.otf
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/assets/readium/readium-css/fonts/LICENSE-AccessibleDfa
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/assets/readium/readium-css/fonts/iAWriterDuospace-Regular.ttf
/Users/ll/.gradle/caches/8.14.4/transforms/2762df196b77e1470ec8fa1ab436d4ad/transformed/readium-navigator-3.3.0/assets/readium/readium-css/fonts/LICENSE-IaWriterDuospace.md
Archive:  /Users/ll/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-navigator/3.3.0/162dd7fdee9e61a10441e5262792ec0d76b6011e/readium-navigator-3.3.0.aar
  Length      Date    Time    Name
---------  ---------- -----   ----
      798  02-01-1980 00:00   R.txt
      394  02-01-1980 00:00   AndroidManifest.xml
   833856  02-01-1980 00:00   classes.jar
        0  02-01-1980 00:00   res/
        0  02-01-1980 00:00   res/drawable/
     1224  02-01-1980 00:00   res/drawable/readium_media_notification_fastforward.xml
     2416  02-01-1980 00:00   res/drawable/readium_media_notification_rewind.xml
        0  02-01-1980 00:00   res/layout/
     2186  02-01-1980 00:00   res/layout/readium_navigator_fragment_fxllayout_double.xml
     1757  02-01-1980 00:00   res/layout/readium_navigator_fragment_fxllayout_single.xml
      937  02-01-1980 00:00   res/layout/readium_navigator_viewpager.xml
     1035  02-01-1980 00:00   res/layout/readium_navigator_viewpager_fragment_cbz.xml
      708  02-01-1980 00:00   res/layout/readium_navigator_viewpager_fragment_epub.xml
        0  02-01-1980 00:00   res/values/
      371  02-01-1980 00:00   res/values/values.xml
        0  02-01-1980 00:00   res/values-land/
      134  02-01-1980 00:00   res/values-land/values-land.xml
        0  02-01-1980 00:00   libs/
    28195  02-01-1980 00:00   libs/PhotoView-2.3.0.jar
        0  02-01-1980 00:00   assets/
        0  02-01-1980 00:00   assets/readium/
      693  02-01-1980 00:00   assets/readium/error.xhtml
        0  02-01-1980 00:00   assets/readium/divina/
      604  02-01-1980 00:00   assets/readium/divina/divinaPlayer.html
   424586  02-01-1980 00:00   assets/readium/divina/divinaPlayer.js
     2260  02-01-1980 00:00   assets/readium/divina/divinaTouchHandling.js
        0  02-01-1980 00:00   assets/readium/fonts/

exec
/bin/zsh -lc 'JAR="$HOME/.gradle/caches/8.14.4/transforms/20a535398e2b06999431a36d9970924d/transformed/readium-navigator-3.3.0-api.jar"; javap -classpath "$JAR" -public org.readium.r2.navigator.epub.EpubNavigatorFragment | rg -n "evaluateJavascript|currentLocator|firstVisibleElementLocator|submitPreferences|public class|public final"
JAR="$HOME/.gradle/caches/8.14.4/transforms/87fd454872d62994fa2f156d672a8156/transformed/readium-navigator-3.3.0-runtime.jar"; javap -classpath "$JAR" -public org.readium.r2.navigator.epub.EpubNavigatorFragment | rg -n "evaluateJavascript|currentLocator|firstVisibleElementLocator|submitPreferences|public class|public final"' in /Users/ll/workspace/vreader
 exited 1 in 0ms:
The operation couldn’t be completed. Unable to locate a Java Runtime.
Please visit http://www.java.com for information on installing Java.

The operation couldn’t be completed. Unable to locate a Java Runtime.
Please visit http://www.java.com for information on installing Java.


exec
/bin/zsh -lc 'find /Applications "$HOME/Library" -path '"'*/bin/javap' -type f 2>/dev/null | head -20" in /Users/ll/workspace/vreader
codex
The exact Readium AAR and Gradle-transformed API/runtime JARs are present locally at version 3.3.0. The system `javap` lacks a configured Java runtime, so I’m locating the Android Studio JBR toolchain to independently inspect the public bytecode signature.
 succeeded in 18110ms:
exec
/bin/zsh -lc "ls -l '/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/javap' '/Applications/Android Studio.app/Contents/jbr/bin/javap' 2>/dev/null || true
rg -a -n \"evaluateJavascript|firstVisibleElementLocator|getCurrentLocator\" \""'$HOME/.gradle/caches/8.14.4/transforms/20a535398e2b06999431a36d9970924d/transformed/readium-navigator-3.3.0-api.jar" | head -30' in /Users/ll/workspace/vreader
 succeeded in 0ms:
661:SourceFile RuntimeVisibleAnnotations            9   K     +	� ,� �    :      8 ;                         <                9   ;     +� �    :      D ;                  <       	    9   E     *+,� �    :      3 ;                        	   !  9   :     *+� #�    :      3 ;                   =      3 4	 6  7  >    8 ?   O  $  %[ I &I 'I ( )I * +I , -[ s . /[ s s 0s s 0s s s s s s s s 1PK      !!J{X|  |  (   org/readium/r2/navigator/Navigator.class����   7 A "org/readium/r2/navigator/Navigator  java/lang/Object  getCurrentLocator %()Lkotlinx/coroutines/flow/StateFlow; R()Lkotlinx/coroutines/flow/StateFlow<Lorg/readium/r2/shared/publication/Locator;>; #Lorg/jetbrains/annotations/NotNull; go /(Lorg/readium/r2/shared/publication/Locator;Z)Z 
733:  	   goBackward$default  	   firstVisibleElementLocator d(Lorg/readium/r2/navigator/OverflowableNavigator;Lkotlin/coroutines/Continuation;)Ljava/lang/Object; �(Lorg/readium/r2/navigator/OverflowableNavigator;Lkotlin/coroutines/Continuation<-Lorg/readium/r2/shared/publication/Locator;>;)Ljava/lang/Object; Ljava/lang/Deprecated; $Lorg/jetbrains/annotations/Nullable; #Lorg/jetbrains/annotations/NotNull; $access$firstVisibleElementLocator$jd     $this 0Lorg/readium/r2/navigator/OverflowableNavigator; $completion  Lkotlin/coroutines/Continuation; Lkotlin/Metadata; mv           k xi   0 DefaultImpls VisualNavigator.kt Code 
766:goBackward goBackward$default USuper calls with default arguments not supported in this target, function: goBackward      $access$firstVisibleElementLocator$jd d(Lorg/readium/r2/navigator/OverflowableNavigator;Lkotlin/coroutines/Continuation;)Ljava/lang/Object; firstVisibleElementLocator 4(Lkotlin/coroutines/Continuation;)Ljava/lang/Object; ! "  # $this 0Lorg/readium/r2/navigator/OverflowableNavigator; $completion  Lkotlin/coroutines/Continuation; .Lorg/readium/r2/shared/ExperimentalReadiumApi; Lkotlin/Metadata; mv           k    xi   0 d1 ���
1629: onReceiveValue @(Lkotlin/jvm/functions/Function1;)Landroid/webkit/ValueCallback; 	 evaluateJavascript 3(Ljava/lang/String;Landroid/webkit/ValueCallback;)V
2458:s s s es s s s s #s $s %s &s 's (s )s *s +s ,s Rs Us es Bs es 4s es f k     W   t     >  7PK      !!����  �  ;   org/readium/r2/navigator/VisualNavigator$DefaultImpls.class����   7 ) 5org/readium/r2/navigator/VisualNavigator$DefaultImpls  java/lang/Object  firstVisibleElementLocator ^(Lorg/readium/r2/navigator/VisualNavigator;Lkotlin/coroutines/Continuation;)Ljava/lang/Object; �(Lorg/readium/r2/navigator/VisualNavigator;Lkotlin/coroutines/Continuation<-Lorg/readium/r2/shared/publication/Locator;>;)Ljava/lang/Object; Ljava/lang/Deprecated; .Lorg/readium/r2/shared/ExperimentalReadiumApi; $Lorg/jetbrains/annotations/Nullable; #Lorg/jetbrains/annotations/NotNull; (org/readium/r2/navigator/VisualNavigator  $access$firstVisibleElementLocator$jd     $this *Lorg/readium/r2/navigator/VisualNavigator; $completion  Lkotlin/coroutines/Continuation; Lkotlin/Metadata; mv           k xi   0 DefaultImpls VisualNavigator.kt Code LineNumberTable LocalVariableTable 	Signature 
2488:s s PK      !!|B��	  �	  .   org/readium/r2/navigator/VisualNavigator.class����   7 P (org/readium/r2/navigator/VisualNavigator  java/lang/Object  "org/readium/r2/navigator/Navigator  getPublicationView ()Landroid/view/View; #Lorg/jetbrains/annotations/NotNull; firstVisibleElementLocator 4(Lkotlin/coroutines/Continuation;)Ljava/lang/Object; b(Lkotlin/coroutines/Continuation<-Lorg/readium/r2/shared/publication/Locator;>;)Ljava/lang/Object; .Lorg/readium/r2/shared/ExperimentalReadiumApi; $Lorg/jetbrains/annotations/Nullable; &firstVisibleElementLocator$suspendImpl ^(Lorg/readium/r2/navigator/VisualNavigator;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;     this *Lorg/readium/r2/navigator/VisualNavigator; $completion  Lkotlin/coroutines/Continuation; �(Lorg/readium/r2/navigator/VisualNavigator;Lkotlin/coroutines/Continuation<-Lorg/readium/r2/shared/publication/Locator;>;)Ljava/lang/Object; getCurrentLocator %()Lkotlinx/coroutines/flow/StateFlow;     !kotlinx/coroutines/flow/StateFlow  getValue ()Ljava/lang/Object;      $this addInputListener 1(Lorg/readium/r2/navigator/input/InputListener;)V removeInputListener $access$firstVisibleElementLocator$jd 
3455:[ I  [ I  [ I  [ s  [ s  s  s  I  ;  <[ I I =I  >I = ?I @PK      !!�j0�  �  N   org/readium/r2/navigator/epub/EpubNavigatorFragment$evaluateJavascript$1.class����   7 N Horg/readium/r2/navigator/epub/EpubNavigatorFragment$evaluateJavascript$1  /kotlin/coroutines/jvm/internal/ContinuationImpl  L$0 Ljava/lang/Object; L$1 .Lkotlin/coroutines/jvm/internal/DebugMetadata; f EpubNavigatorFragment.kt l  .  / nl���� i        s n script page m evaluateJavascript c 3org.readium.r2.navigator.epub.EpubNavigatorFragment v    <init> X(Lorg/readium/r2/navigator/epub/EpubNavigatorFragment;Lkotlin/coroutines/Continuation;)V �(Lorg/readium/r2/navigator/epub/EpubNavigatorFragment;Lkotlin/coroutines/Continuation<-Lorg/readium/r2/navigator/epub/EpubNavigatorFragment$evaluateJavascript$1;>;)V this$0 5Lorg/readium/r2/navigator/epub/EpubNavigatorFragment;   !	  " #(Lkotlin/coroutines/Continuation;)V  $
3456:  % this JLorg/readium/r2/navigator/epub/EpubNavigatorFragment$evaluateJavascript$1; $completion  Lkotlin/coroutines/Continuation; invokeSuspend &(Ljava/lang/Object;)Ljava/lang/Object; $Lorg/jetbrains/annotations/Nullable; #Lorg/jetbrains/annotations/NotNull; result / 	  0 label I 2 3	  4�    kotlin/coroutines/Continuation 7 3org/readium/r2/navigator/epub/EpubNavigatorFragment 9 F(Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;  ;
3461: [ I I  [ I I  [ I I I I  [ s s s s  [ s s s s  s  s  I  ?  @[ I I AI  BI A CI DPK      !!�C\`  `  V   org/readium/r2/navigator/epub/EpubNavigatorFragment$firstVisibleElementLocator$1.class����   7 J Porg/readium/r2/navigator/epub/EpubNavigatorFragment$firstVisibleElementLocator$1  /kotlin/coroutines/jvm/internal/ContinuationImpl  L$0 Ljava/lang/Object; .Lkotlin/coroutines/jvm/internal/DebugMetadata; f EpubNavigatorFragment.kt l  � nl  � i     s n resource m firstVisibleElementLocator c 3org.readium.r2.navigator.epub.EpubNavigatorFragment v    <init> X(Lorg/readium/r2/navigator/epub/EpubNavigatorFragment;Lkotlin/coroutines/Continuation;)V �(Lorg/readium/r2/navigator/epub/EpubNavigatorFragment;Lkotlin/coroutines/Continuation<-Lorg/readium/r2/navigator/epub/EpubNavigatorFragment$firstVisibleElementLocator$1;>;)V this$0 5Lorg/readium/r2/navigator/epub/EpubNavigatorFragment;  	   #(Lkotlin/coroutines/Continuation;)V   
3462:  ! this RLorg/readium/r2/navigator/epub/EpubNavigatorFragment$firstVisibleElementLocator$1; $completion  Lkotlin/coroutines/Continuation; invokeSuspend &(Ljava/lang/Object;)Ljava/lang/Object; $Lorg/jetbrains/annotations/Nullable; #Lorg/jetbrains/annotations/NotNull; result + 	  , label I . /	  0�    kotlin/coroutines/Continuation 3 3org/readium/r2/navigator/epub/EpubNavigatorFragment 5 4(Lkotlin/coroutines/Continuation;)Ljava/lang/Object;  7
3951: �a evaluateJavascript F(Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object; [(Ljava/lang/String;Lkotlin/coroutines/Continuation<-Ljava/lang/String;>;)Ljava/lang/Object; Horg/readium/r2/navigator/epub/EpubNavigatorFragment$evaluateJavascript$1f labelh/	gi�    X(Lorg/readium/r2/navigator/epub/EpubNavigatorFragment;Lkotlin/coroutines/Continuation;)V l
4032: c event <Lorg/readium/r2/navigator/epub/EpubNavigatorViewModel$Event; :org/readium/r2/navigator/epub/EpubNavigatorViewModel$Eventg getCurrentLocatoriT
4116:; ;$i$a$-forEach-EpubNavigatorFragment$loadedFragmentForHref$1 pageFragment R()Lkotlinx/coroutines/flow/StateFlow<Lorg/readium/r2/shared/publication/Locator;>; firstVisibleElementLocator b(Lkotlin/coroutines/Continuation<-Lorg/readium/r2/shared/publication/Locator;>;)Ljava/lang/Object; .Lorg/readium/r2/shared/ExperimentalReadiumApi; Porg/readium/r2/navigator/epub/EpubNavigatorFragment$firstVisibleElementLocator$1C	Di
11599: � � getAdapter$readium_navigator 1()Lorg/readium/r2/navigator/pager/R2PagerAdapter; adapter /Lorg/readium/r2/navigator/pager/R2PagerAdapter; � �	  � � -org/readium/r2/navigator/pager/R2PagerAdapter � setAdapter$readium_navigator 2(Lorg/readium/r2/navigator/pager/R2PagerAdapter;)V getCurrentLocator %()Lkotlinx/coroutines/flow/StateFlow; R()Lkotlinx/coroutines/flow/StateFlow<Lorg/readium/r2/shared/publication/Locator;>; !kotlinx/coroutines/flow/StateFlow � getResources$readium_navigator &()Ljava/util/List<Ljava/lang/String;>; setResources$readium_navigator '(Ljava/util/List<Ljava/lang/String;>;)V 
11652:  firstVisibleElementLocator 4(Lkotlin/coroutines/Continuation;)Ljava/lang/Object; b(Lkotlin/coroutines/Continuation<-Lorg/readium/r2/shared/publication/Locator;>;)Ljava/lang/Object;  $completion  Lkotlin/coroutines/Continuation; onCreate$lambda$0$0 H(Lorg/readium/r2/navigator/image/ImageNavigatorFragment;FF)Lkotlin/Unit; 'org/readium/r2/navigator/input/TapEvent$ android/graphics/PointF& (FF)V (
13708: cd� onReceiveValue X(Landroid/webkit/WebView;Lkotlin/jvm/functions/Function0;)Landroid/webkit/ValueCallback;gh i android/webkit/WebViewk evaluateJavascript 3(Ljava/lang/String;Landroid/webkit/ValueCallback;)Vmn
15440: �� getCurrentLocator R()Lkotlinx/coroutines/flow/StateFlow<Lorg/readium/r2/shared/publication/Locator;>;��
15459: u firstVisibleElementLocator 4(Lkotlin/coroutines/Continuation;)Ljava/lang/Object; b(Lkotlin/coroutines/Continuation<-Lorg/readium/r2/shared/publication/Locator;>;)Ljava/lang/Object;  $completion  Lkotlin/coroutines/Continuation; >Lorg/readium/r2/navigator/pdf/PdfNavigatorViewModel$Companion; e	 � requireActivity *()Landroidx/fragment/app/FragmentActivity;
15766:  b 	_settings d S	  e settings g ]	  h this 4Lorg/readium/r2/navigator/pdf/PdfNavigatorViewModel; Landroid/app/Application; initialLocations 5Lorg/readium/r2/shared/publication/Locator$Locations; ?Lorg/readium/r2/navigator/preferences/Configurable$Preferences; android/app/Application p =org/readium/r2/navigator/preferences/Configurable$Preferences r .org/readium/r2/navigator/pdf/PdfEngineProvider t getCurrentLocator %()Lkotlinx/coroutines/flow/StateFlow; R()Lkotlinx/coroutines/flow/StateFlow<Lorg/readium/r2/shared/publication/Locator;>; getSettings *()Lkotlinx/coroutines/flow/StateFlow<TS;>; submitPreferences Y(Lorg/readium/r2/navigator/preferences/Configurable$Preferences;)Lkotlinx/coroutines/Job; (TP;)Lkotlinx/coroutines/Job; preferences ~ androidx/lifecycle/ViewModel � androidx/lifecycle/ViewModelKt � getViewModelScope C(Landroidx/lifecycle/ViewModel;)Lkotlinx/coroutines/CoroutineScope; � �
18327:�  �  L           ��� org/readium/r2/navigator/epub/EpubNavigatorFragment$applyDecorations$1.classPK       !!�V)�8  8  L           ��� org/readium/r2/navigator/epub/EpubNavigatorFragment$currentSelection$1.classPK       !!�j0�  �  N           ��k' org/readium/r2/navigator/epub/EpubNavigatorFragment$evaluateJavascript$1.classPK       !!�C\`  `  V           ��h/ org/readium/r2/navigator/epub/EpubNavigatorFragment$firstVisibleElementLocator$1.classPK       !!�7��D)  D)  Q           ��<7 org/readium/r2/navigator/epub/EpubNavigatorFragment$notifyCurrentLocation$1.classPK       !!?g~��	  �	  M           ���` org/readium/r2/navigator/epub/EpubNavigatorFragment$onViewCreated$1$1$1.classPK       !!�xvK�  �  M           ��#k org/readium/r2/navigator/epub/EpubNavigatorFragment$onViewCreated$1$1$2.classPK       !!m�S��  �  K           ��`{ org/readium/r2/navigator/epub/EpubNavigatorFragment$onViewCreated$1$1.classPK       !!�<��  �  I           ���� org/readium/r2/navigator/epub/EpubNavigatorFragment$onViewCreated$1.classPK       !!f��=�  �  n           ���� org/readium/r2/navigator/epub/EpubNavigatorFragment$onViewCreated$2$invokeSuspend$$inlined$withStarted$1.classPK       !!Xj[��  �  I           ��� org/readium/r2/navigator/epub/EpubNavigatorFragment$onViewCreated$2.classPK       !!�J��d  d  S           ��,� org/readium/r2/navigator/epub/EpubNavigatorFragment$positionsByReadingOrder$1.classPK       !!����	  �	  _           ��� org/readium/r2/navigator/epub/EpubNavigatorFragment$special$$inlined$viewModels$default$1.classPK       !!P�5S

exec
/bin/zsh -lc "nl -ba android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt | sed -n '1,150p'
nl -ba android/app/src/main/kotlin/com/vreader/app/search/TxtMdTextExtractor.kt | sed -n '1,180p'
nl -ba android/app/src/main/kotlin/com/vreader/app/search/BookTextExtractor.kt | sed -n '1,100p'
nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt | sed -n '1,80p'
nl -ba android/identity/src/main/kotlin/vreader/contracts/backup/BackupSectionsExtended.kt | sed -n '55,78p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
     1	// Purpose: Addressable, range-based model of a decoded .txt — feature #111 WI-1.
     2	// Holds ONE backing decoded String and an array of chunk START offsets (UTF-16 code
     3	// units against the RAW text — NO line-ending normalization, so charOffsetUTF16 stays
     4	// exact for resume). Splits at line boundaries (CRLF/CR/LF kept inside the chunk);
     5	// hard-splits a runaway line at maxChunkChars (never mid-surrogate-pair). Visible
     6	// chunk text is materialized on demand (no per-chunk substrings retained). Pure JVM.
     7	package com.vreader.app.reader
     8	
     9	class TxtDocument private constructor(
    10	    val text: String,
    11	    private val starts: IntArray,
    12	) {
    13	    /** Number of chunks (0 for empty text). */
    14	    val chunkCount: Int get() = starts.size
    15	
    16	    /** The UTF-16 start offset of chunk [index] (clamped to a valid chunk). */
    17	    fun offsetForChunk(index: Int): Int {
    18	        if (starts.isEmpty()) return 0
    19	        return starts[index.coerceIn(0, starts.size - 1)]
    20	    }
    21	
    22	    /** The chunk index containing [offsetUtf16] (EOF-clamped); 0 for empty text. */
    23	    fun chunkForOffset(offsetUtf16: Int): Int {
    24	        if (starts.isEmpty()) return 0
    25	        val offset = offsetUtf16.coerceIn(0, text.length)
    26	        // Largest start <= offset (binary search).
    27	        var lo = 0; var hi = starts.size - 1; var ans = 0
    28	        while (lo <= hi) {
    29	            val mid = (lo + hi) ushr 1
    30	            if (starts[mid] <= offset) { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
    31	        }
    32	        return ans
    33	    }
    34	
    35	    /** The text of chunk [index], materialized on demand from the backing string. */
    36	    fun textForChunk(index: Int): CharSequence {
    37	        if (starts.isEmpty()) return ""
    38	        val i = index.coerceIn(0, starts.size - 1)
    39	        val end = if (i + 1 < starts.size) starts[i + 1] else text.length
    40	        return text.subSequence(starts[i], end)
    41	    }
    42	
    43	    companion object {
    44	        const val DEFAULT_MAX_CHUNK_CHARS = 4000
    45	
    46	        /**
    47	         * Build a document from already-decoded [text]. Chunk boundaries fall after a
    48	         * line terminator (`\n`, `\r`, or `\r\n` — preserved in the chunk); a line longer
    49	         * than [maxChunkChars] is hard-split, but never between a surrogate pair.
    50	         */
    51	        fun of(text: String, maxChunkChars: Int = DEFAULT_MAX_CHUNK_CHARS): TxtDocument {
    52	            if (text.isEmpty()) return TxtDocument(text, IntArray(0))
    53	            // Primitive growable IntArray (no Int boxing) — a newline-dense 14MB file
    54	            // would otherwise spike tens of MB of boxed Integers + a duplicating copy.
    55	            var starts = IntArray(64)
    56	            var count = 0
    57	            fun push(v: Int) {
    58	                if (count == starts.size) starts = starts.copyOf(starts.size * 2)
    59	                starts[count++] = v
    60	            }
    61	            push(0)
    62	            var i = 0
    63	            var chunkStart = 0
    64	            val n = text.length
    65	            while (i < n) {
    66	                val c = text[i]
    67	                when {
    68	                    c == '\n' -> {
    69	                        i++
    70	                        if (i < n) { push(i); chunkStart = i }
    71	                    }
    72	                    c == '\r' -> {
    73	                        i++
    74	                        if (i < n && text[i] == '\n') i++   // CRLF stays one terminator
    75	                        if (i < n) { push(i); chunkStart = i }
    76	                    }
    77	                    else -> {
    78	                        i++
    79	                        // Hard-split a runaway line, but not mid-surrogate-pair (don't
    80	                        // split right after a high surrogate — its low half follows at i).
    81	                        if (i - chunkStart >= maxChunkChars && i < n && !text[i - 1].isHighSurrogate()) {
    82	                            push(i); chunkStart = i
    83	                        }
    84	                    }
    85	                }
    86	            }
    87	            return TxtDocument(text, starts.copyOf(count))
    88	        }
    89	    }
    90	}
     1	// Purpose: Extract TXT/MD text for the library search index, streaming each TxtDocument chunk to the
     2	// SectionSink — feature #128 WI-3. Serves both `txt` and `md` (raw markdown text; marker-stripping is
     3	// a nice-to-have deferred). Reuses the shipped reader decode/chunk path (TxtDecoder + TxtDocument).
     4	//
     5	// Memory note (Gate-2 round-3 HIGH): this path holds the whole decoded book String (via
     6	// TxtDecoder/TxtDocument) — O(book-size), the ACCEPTED EXISTING reader bound (indexing loads exactly
     7	// what the TXT/MD reader already loads to display the book). It is NOT O(batch). The sink still emits
     8	// chunks incrementally so the DB-write side stays batched.
     9	package com.vreader.app.search
    10	
    11	import com.vreader.app.data.Book
    12	import com.vreader.app.reader.TxtDecoder
    13	import com.vreader.app.reader.TxtDocument
    14	import kotlinx.coroutines.CancellationException
    15	import java.io.File
    16	
    17	/** Streams a TXT/MD book's TxtDocument chunks to a [SectionSink]; author is always null on Success. */
    18	class TxtMdTextExtractor : BookTextExtractor {
    19	
    20	    override suspend fun extract(book: Book, sink: SectionSink): ExtractResult {
    21	        val path = book.localFilePath ?: return ExtractResult.Unsupported
    22	        val file = File(path)
    23	        if (!file.exists()) return ExtractResult.Failed("file not found: $path")
    24	        return try {
    25	            val decoded = TxtDecoder.decode(file)
    26	            val document = TxtDocument.of(decoded.text)
    27	            // Emit one section per chunk; sectionIndex == chunkOrdinal == chunk index (TXT has no
    28	            // sub-resource grouping). Empty text → chunkCount 0 → zero emissions (still Success).
    29	            for (i in 0 until document.chunkCount) {
    30	                sink.emit(
    31	                    BookTextSection(
    32	                        sectionIndex = i,
    33	                        chunkOrdinal = i,
    34	                        title = null,
    35	                        text = document.textForChunk(i).toString(),
    36	                    ),
    37	                )
    38	            }
    39	            ExtractResult.Success(null)
    40	        } catch (e: CancellationException) {
    41	            throw e   // never swallow structured cancellation as a per-book failure
    42	        } catch (e: Exception) {
    43	            ExtractResult.Failed(e.message ?: e.javaClass.simpleName)
    44	        }
    45	    }
    46	}
     1	// Purpose: The book text-extraction seam for library search indexing — feature #128 WI-3.
     2	// Extraction STREAMS each finished section to a SectionSink (never returns a materialized List), so
     3	// EPUB extraction is bounded-memory (O(batch)): the coordinator's sink flushes batches to the
     4	// staging table and drops them, keeping at most one batch resident. The whole-book author is the one
     5	// datum that cannot stream (book-level metadata read up front), so it rides on Success. A typed
     6	// Unsupported / Failed result (not an exception or an empty stream) lets the coordinator record the
     7	// right search_index_state.status (WI-5).
     8	package com.vreader.app.search
     9	
    10	import com.vreader.app.data.Book
    11	
    12	/** One extracted, chunk-sized section streamed to a [SectionSink]. */
    13	data class BookTextSection(
    14	    /** Per-book reading-order/section index — chapter attribution + first-hit tie-break. */
    15	    val sectionIndex: Int,
    16	    /** UNIQUE monotonic ordinal within a book (a running per-chunk counter) — deterministic first hit. */
    17	    val chunkOrdinal: Int,
    18	    /** Chapter label for the snippet attribution; null for TXT/MD (and no-TOC EPUB sections). */
    19	    val title: String?,
    20	    /** RAW display text of this chunk (the snippet source). */
    21	    val text: String,
    22	)
    23	
    24	/**
    25	 * The streaming sink the extractor emits each finished section to. The coordinator's implementation
    26	 * writes to the staging table in batches; tests use a collecting fake.
    27	 */
    28	interface SectionSink {
    29	    /** Emit one finished section. The sink may buffer into a batch. */
    30	    suspend fun emit(section: BookTextSection)
    31	
    32	    /**
    33	     * Flush any buffered-but-unwritten sections. The coordinator calls this exactly once after
    34	     * `extract()` returns [ExtractResult.Success] and BEFORE publish, so a book with fewer sections
    35	     * than one batch (or a non-multiple tail) still persists every section.
    36	     */
    37	    suspend fun flushRemaining()
    38	}
    39	
    40	/** The typed outcome of an extract — distinguishes streamed success, unsupported, and failure. */
    41	sealed interface ExtractResult {
    42	    /** All sections were streamed to the sink; [author] is the only whole-book datum (for backfill). */
    43	    data class Success(val author: String?) : ExtractResult
    44	
    45	    /** No text is extractable (e.g. EPUB with no content service, no local file). Metadata-only book. */
    46	    data object Unsupported : ExtractResult
    47	
    48	    /** A transient/retryable failure ([reason] for logging); the coordinator records a `failed` state. */
    49	    data class Failed(val reason: String) : ExtractResult
    50	}
    51	
    52	/** Extracts a book's text, streaming each section to a [SectionSink]. NEVER accumulates the whole book. */
    53	interface BookTextExtractor {
    54	    /**
    55	     * Streams each finished section to [sink] as it is produced. Returns [ExtractResult.Success] after
    56	     * the last section, or [ExtractResult.Unsupported] / [ExtractResult.Failed] without emitting.
    57	     */
    58	    suspend fun extract(book: Book, sink: SectionSink): ExtractResult
    59	}
     1	// Purpose: feature #118 WI-2 (#110 Phase 3) — the AI client value types + typed errors, mirroring
     2	// iOS AITypes (AIRequest/AIResponse/AIStreamChunk/AIError). Provider-neutral; the OpenAI vs
     3	// Anthropic wire differences live in the providers.
     4	package com.vreader.app.ai
     5	
     6	enum class AiRole { system, user, assistant }
     7	
     8	data class AiMessage(val role: AiRole, val content: String)
     9	
    10	/** A chat request. `system` is the system prompt (Anthropic carries it top-level; the OpenAI
    11	 *  provider prepends it as a system message). */
    12	data class AiRequest(
    13	    val model: String,
    14	    val messages: List<AiMessage>,
    15	    val temperature: Double,
    16	    val maxTokens: Int,
    17	    val system: String? = null,
    18	)
    19	
    20	/** One streamed delta (the incremental assistant text). */
    21	data class AiChunk(val deltaText: String)
    22	
    23	/** A one-shot (non-streamed) response. */
    24	data class AiResponse(val text: String)
    25	
    26	/** Typed AI failures (HTTP + transport + protocol). */
    27	sealed class AiError(message: String) : Exception(message) {
    28	    object Auth401 : AiError("authentication failed (401) — check the API key")
    29	    object RateLimited429 : AiError("rate limited (429) — try again shortly")
    30	    object Offline : AiError("the provider couldn't be reached")
    31	    object Timeout : AiError("the provider took too long to respond")
    32	    class Http(val code: Int) : AiError("HTTP $code from the provider")
    33	    class Decode(detail: String) : AiError("couldn't parse the provider response: $detail")
    34	    class Stream(detail: String) : AiError("the stream ended abnormally: $detail")
    35	    /** Refused to send the API key over cleartext http:// to a non-local host. */
    36	    object InsecureUrl : AiError("the provider URL must be https:// (won't send the key over cleartext)")
    37	    class Config(detail: String) : AiError("provider misconfigured: $detail")
    38	}
    39	
    40	/** Test-connection outcome (the editor's Connection section). */
    41	sealed interface AiTestResult {
    42	    object Ok : AiTestResult
    43	    data class Fail(val error: AiError, val message: String) : AiTestResult
    44	}
    55	data class BackupPerBookSettingsEntry(
    56	    val bookFingerprintKey: String,
    57	    val override: PerBookSettingsOverride,
    58	)
    59	
    60	/** Per-book reader overrides — mirrors Swift `PerBookSettingsOverride` (CGFloat ⇒ Double).
    61	 *  All fields optional; a nil inherits the global default. */
    62	@Serializable
    63	data class PerBookSettingsOverride(
    64	    val fontSize: Double? = null,
    65	    val fontName: String? = null,
    66	    val lineSpacing: Double? = null,
    67	    val letterSpacing: Double? = null,
    68	    val themeName: String? = null,
    69	    val bilingualEnabled: Boolean? = null,
    70	    val bilingualTargetLanguage: String? = null,
    71	    val bilingualGranularity: String? = null,
    72	    val metricsReadout: String? = null,
    73	)
    74	
    75	// MARK: - Replacement Rules
    76	
    77	@Serializable
    78	data class BackupReplacementRulesEnvelope(

exec
/bin/zsh -lc "nl -ba vreader/Services/AI/ChapterTranslationService.swift | sed -n '110,280p'
nl -ba vreader/Views/Reader/Bilingual/BilingualPageContent.swift 2>/dev/null | sed -n '1,220p'
rg -n \"translatedParagraphs|translation ==|source-only|original-always|translations\\[|zip\\(\" vreader/Views/Reader/Bilingual vreader/Services/AI | head -160
nl -ba vreader/Services/AI/ChapterTranslationStore.swift | sed -n '1,180p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
   110	    /// Bug #342: profile-agnostic — the canonical row is shared across provider
   111	    /// profiles, so no profile is needed for a read at all.
   112	    /// Bug #343 `acceptCountMismatch`: self-healing consumers (the EPUB hosts
   113	    /// with the divergence fallback) may opt in to receive a fresh row whose
   114	    /// stored count differs from the live re-derived segmenter count — the
   115	    /// row may carry the DOM-enumerate contract (written by the divergence
   116	    /// fallback), which pairs 1:1 at inject time; on a true source change the
   117	    /// fallback re-translates and replaces the row. Default-off callers keep
   118	    /// the strict staleness guard.
   119	    func cachedTranslation(
   120	        bookFingerprintKey: String,
   121	        unit: TranslationUnitID,
   122	        sourceText: String,
   123	        targetLanguage: String,
   124	        granularity: TranslationGranularity = .paragraph,
   125	        acceptCountMismatch: Bool = false
   126	    ) async -> ChapterTranslationResult? {
   127	        let lookupKey = ChapterTranslationRecord.lookupKey(
   128	            bookFingerprintKey: bookFingerprintKey,
   129	            unitStorageKey: unit.storageKey,
   130	            targetLanguage: targetLanguage,
   131	            promptVersion: promptVersion)
   132	        let segments: [String]
   133	        switch granularity {
   134	        case .paragraph: segments = ChapterSegmenter.paragraphs(in: sourceText)
   135	        case .sentence:  segments = ChapterSegmenter.sentences(in: sourceText)
   136	        }
   137	        guard let cached = await store.translation(forKey: lookupKey) else { return nil }
   138	        guard cached.sourceParagraphCount == segments.count || acceptCountMismatch else {
   139	            return nil
   140	        }
   141	        return ChapterTranslationResult(segments: cached.translatedSegments, fromCache: true)
   142	    }
   143	
   144	    /// Bug #343: the divergence-fallback restore — serves the canonical row
   145	    /// only when its STORED count matches the caller's own structure (the DOM
   146	    /// enumerate's block count), so blocks↔segments pair 1:1 by contract.
   147	    /// Needs no provider config and no source text.
   148	    func cachedTranslation(
   149	        bookFingerprintKey: String,
   150	        unit: TranslationUnitID,
   151	        expectedSegmentCount: Int,
   152	        targetLanguage: String
   153	    ) async -> ChapterTranslationResult? {
   154	        let lookupKey = ChapterTranslationRecord.lookupKey(
   155	            bookFingerprintKey: bookFingerprintKey,
   156	            unitStorageKey: unit.storageKey,
   157	            targetLanguage: targetLanguage,
   158	            promptVersion: promptVersion)
   159	        guard let cached = await store.translation(forKey: lookupKey),
   160	              cached.sourceParagraphCount == expectedSegmentCount else { return nil }
   161	        return ChapterTranslationResult(segments: cached.translatedSegments, fromCache: true)
   162	    }
   163	
   164	    /// Translates `unit`'s source text into `targetLanguage`. Serves from the
   165	    /// disk cache on a hit; on a miss segments → chunks → requests → decodes →
   166	    /// caches. Throws `ChapterTranslationError` on a provider failure or
   167	    /// cancellation.
   168	    func translate(
   169	        bookFingerprintKey: String,
   170	        unit: TranslationUnitID,
   171	        sourceText: String,
   172	        targetLanguage: String,
   173	        providerProfileID: UUID,
   174	        config: ResolvedAIProviderConfig,
   175	        style: TranslationStyle,
   176	        granularity: TranslationGranularity = .paragraph,
   177	        // Bug #341: when true, the cache READ is skipped — a fresh cached row
   178	        // must not short-circuit an explicit re-translate into a stale no-op.
   179	        // The cache WRITE still runs: the upsert replaces the row by lookupKey
   180	        // in place, which is the atomic swap (the old translation survives
   181	        // until the new one durably lands; a failure leaves it untouched).
   182	        bypassCacheRead: Bool = false,
   183	        // Bug #311: optional real progress source. Fired after each chunk
   184	        // completes with `(completedChunks, totalChunks)` so a caller (the
   185	        // re-translate VM) can drive an honest N-of-M progress bar instead of
   186	        // a faked 0.5 pin during the opaque per-chunk network phase. nil by
   187	        // default — the whole-book coordinator + bilingual paths don't use it.
   188	        onChunkProgress: (@Sendable (Int, Int) -> Void)? = nil
   189	    ) async throws -> ChapterTranslationResult {
   190	        // Bug #342: the canonical key has no profile component —
   191	        // `providerProfileID` is written as row provenance metadata only.
   192	        let lookupKey = ChapterTranslationRecord.lookupKey(
   193	            bookFingerprintKey: bookFingerprintKey,
   194	            unitStorageKey: unit.storageKey,
   195	            targetLanguage: targetLanguage,
   196	            promptVersion: promptVersion)
   197	
   198	        // Segment the source per the requested granularity FIRST — the
   199	        // segment count is needed to detect a stale cache row.
   200	        let segments: [String]
   201	        switch granularity {
   202	        case .paragraph: segments = ChapterSegmenter.paragraphs(in: sourceText)
   203	        case .sentence:  segments = ChapterSegmenter.sentences(in: sourceText)
   204	        }
   205	
   206	        // Cache lookup. A row is served only when its `sourceParagraphCount`
   207	        // still matches the live chapter — a chapter whose source has since
   208	        // changed (content-replacement rule edit, re-import) produces a
   209	        // mismatch, which is treated as STALE: the row is dropped and the
   210	        // chapter re-translated (plan audit-driven addition).
   211	        if !bypassCacheRead, let cached = await store.translation(forKey: lookupKey) {
   212	            if cached.sourceParagraphCount == segments.count {
   213	                return ChapterTranslationResult(
   214	                    segments: cached.translatedSegments, fromCache: true)
   215	            }
   216	            log.info("Stale cache row (count \(cached.sourceParagraphCount) != live \(segments.count)); re-translating")
   217	            // A delete failure does not block re-translation — the later
   218	            // upsert refreshes the same lookupKey regardless. Logged so the
   219	            // swallow is visible (rule 50 §6).
   220	            do {
   221	                try await store.deleteTranslation(forKey: lookupKey)
   222	            } catch {
   223	                log.error("Stale-row delete failed (upsert will still refresh it): \(String(describing: error), privacy: .public)")
   224	            }
   225	        }
   226	
   227	        guard !segments.isEmpty else {
   228	            return ChapterTranslationResult(segments: [], fromCache: false)
   229	        }
   230	
   231	        // Chunk → translate each chunk → recombine in source order.
   232	        let chunks = ChapterTranslationChunker.chunk(
   233	            segments: segments, maxCharsPerChunk: maxCharsPerChunk)
   234	        var translated = [String](repeating: "", count: segments.count)
   235	
   236	        // Bug #330: a single chunk's provider failure must NOT abort the whole
   237	        // chapter — leave that chunk's segments source-only (empty translation)
   238	        // and continue. But if EVERY chunk fails (a genuine outage, not just one
   239	        // over-budget chunk), surface the error rather than silently returning an
   240	        // all-source-only result.
   241	        var completedChunks = 0
   242	        var anyChunkSucceeded = false
   243	        var lastChunkError: Error?
   244	        for chunk in chunks {
   245	            do {
   246	                try Task.checkCancellation()
   247	            } catch {
   248	                throw ChapterTranslationError.cancelled
   249	            }
   250	            let chunkSegments = chunk.map { segments[$0] }
   251	            do {
   252	                let chunkResult = try await translateChunk(
   253	                    chunkSegments, targetLanguage: targetLanguage, config: config, style: style)
   254	                for (offset, segmentIndex) in chunk.enumerated() {
   255	                    translated[segmentIndex] = chunkResult[offset]
   256	                }
   257	                anyChunkSucceeded = true
   258	            } catch is CancellationError {
   259	                // The between-chunk / per-piece Task.checkCancellation() throws a
   260	                // raw CancellationError — surface it as the typed .cancelled.
   261	                throw ChapterTranslationError.cancelled
   262	            } catch ChapterTranslationError.cancelled {
   263	                // Bug #330 (Codex): `send()` maps a provider-side cancellation to
   264	                // the TYPED `.cancelled`. It must NOT be degraded-and-continued —
   265	                // a cancel aborts the whole translation. Rethrow before the
   266	                // generic degradation catch below.
   267	                throw ChapterTranslationError.cancelled
   268	            } catch {
   269	                // Bug #330: degrade this chunk to source-only and keep going.
   270	                log.error("Chunk failed (segments \(chunk) left source-only): \(String(describing: error), privacy: .public)")
   271	                lastChunkError = error
   272	            }
   273	            // Bug #311: real N-of-M progress — fire AFTER the chunk resolves
   274	            // (success or graceful-degrade) so the count reflects committed work.
   275	            completedChunks += 1
   276	            onChunkProgress?(completedChunks, chunks.count)
   277	        }
   278	        if !anyChunkSucceeded, let err = lastChunkError {
   279	            throw err
   280	        }
vreader/Services/AI/ChapterPrefetching.swift:67:    /// source-only (never worse than the current behavior).
vreader/Views/Reader/Bilingual/EPUBBilingualOrchestrator.swift:164:    /// as source-only (silent-source-fallback semantics — plan
vreader/Views/Reader/Bilingual/EPUBBilingualOrchestrator.swift:252:    /// source-only fallback) — the others still inject. Returns `nil` when no
vreader/Views/Reader/Bilingual/EPUBBilingualOrchestrator.swift:263:            // empty map for that section → it stays source-only, the rest still
vreader/Views/Reader/Bilingual/FoliateBilingualOrchestrator.swift:154:    /// as source-only (silent-source-fallback semantics — plan
vreader/Views/Reader/Bilingual/BilingualSetupSheet+Sections.swift:158:        let sample = Self.translations[resolved.key] ?? Self.translations["Chinese"] ?? ""
vreader/Views/Reader/Bilingual/BilingualPairing.swift:18:// paints source-only. The primary defense against the mismatch is making the
vreader/Views/Reader/Bilingual/BilingualPairing.swift:31:    /// empty map (source-only) when there is no cached translation or the
vreader/Views/Reader/Bilingual/FoliateBilingualPipeline.swift:166:    /// empty map → source-only — fail-safe (never a wrong pairing).
vreader/Views/Reader/Bilingual/BilingualDisplayPipeline.swift:87:        // surviving a granularity switch) must paint source-only here —
vreader/Services/AI/ChapterSegmenter.swift:34:        // source-only. Each scan range contains at least one
vreader/Views/Reader/Bilingual/EPUBBilingualPipeline.swift:175:    /// empty map → the renderer paints source-only. A partial (min-count)
vreader/Views/Reader/Bilingual/EPUBBilingualPipeline.swift:182:        // Bug #266: pair only on a 1:1 count match (source-only otherwise) via
vreader/Views/Reader/Bilingual/BilingualTextRenderer.swift:38://   gets injected and the tail paragraphs render source-only (no
vreader/Views/Reader/Bilingual/BilingualTextRenderer.swift:154:                let translationText = translations[index]
vreader/Views/Reader/Bilingual/BilingualAttributedStringComposer.swift:113:                let translationText = translations[index]
vreader/Views/Reader/Bilingual/EPUBBilingualJS.swift:498:                    existing.textContent = translations[bid];
vreader/Views/Reader/Bilingual/EPUBBilingualJS.swift:501:                var node = makeBlock(translations[bid], block);
vreader/Services/AI/ChapterTranslationService.swift:237:        // chapter — leave that chunk's segments source-only (empty translation)
vreader/Services/AI/ChapterTranslationService.swift:240:        // all-source-only result.
vreader/Services/AI/ChapterTranslationService.swift:269:                // Bug #330: degrade this chunk to source-only and keep going.
vreader/Services/AI/ChapterTranslationService.swift:270:                log.error("Chunk failed (segments \(chunk) left source-only): \(String(describing: error), privacy: .public)")
vreader/Services/AI/ChapterTranslationService.swift:288:        // (its segments are source-only ""), caching would make the gap permanent
vreader/Services/AI/ChapterTranslationService.swift:316:    /// whole-chapter source-only fallback. The returned array is always the same
vreader/Services/AI/ChapterTranslationService.swift:341:        // failure leaves its segments source-only; an all-chunks failure surfaces
vreader/Services/AI/ChapterTranslationService.swift:366:                log.error("Pre-segmented chunk failed (segments \(chunk) source-only): \(String(describing: error), privacy: .public)")
vreader/Services/AI/ChapterTranslationService.swift:493:    /// source-only per edge case (c)) from a generic provider failure.
vreader/Services/AI/ChapterTranslationService.swift:499:    /// the source-only fallback on a provider/config fault (Gate-4 round-2).
nl: vreader/Services/AI/ChapterTranslationStore.swift: No such file or directory

exec
/bin/zsh -lc 'find "$HOME/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-navigator/3.3.0" -type f -maxdepth 2 -print
find "$HOME/.gradle/caches" -type f -name '"'*readium-navigator*source*.jar' -o -name '*readium-navigator*source*.aar' 2>/dev/null | head -20
rg -n \"fun evaluateJavascript|suspend fun evaluateJavascript\" \""'$HOME/.gradle/caches" 2>/dev/null | head -20' in /Users/ll/workspace/vreader
 succeeded in 1514ms:
exec
/bin/zsh -lc 'command -v java; command -v javap; /usr/libexec/java_home 2>/dev/null || true; ls -d "$HOME/Library/Java/JavaVirtualMachines"/*/Contents/Home 2>/dev/null || true; ls -d /opt/homebrew/opt/openjdk*/libexec/openjdk.jdk/Contents/Home 2>/dev/null || true; ls -d /Library/Java/JavaVirtualMachines/*/Contents/Home 2>/dev/null || true; ls -d "$HOME/.gradle/jdks"/* 2>/dev/null || true' in /Users/ll/workspace/vreader
 succeeded in 0ms:
/usr/bin/java
/usr/bin/javap
zsh:1: no matches found: /Users/ll/Library/Java/JavaVirtualMachines/*/Contents/Home
/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home
/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
/opt/homebrew/opt/openjdk@25/libexec/openjdk.jdk/Contents/Home
/opt/homebrew/opt/openjdk@26/libexec/openjdk.jdk/Contents/Home
zsh:1: no matches found: /Library/Java/JavaVirtualMachines/*/Contents/Home
zsh:1: no matches found: /Users/ll/.gradle/jdks/*

exec
/bin/zsh -lc "JAVAP='/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home/bin/javap'; JAR=\""'$HOME/.gradle/caches/8.14.4/transforms/20a535398e2b06999431a36d9970924d/transformed/readium-navigator-3.3.0-api.jar"; "$JAVAP" -classpath "$JAR" -public org.readium.r2.navigator.epub.EpubNavigatorFragment | rg -n "class EpubNavigatorFragment|evaluateJavascript|getCurrentLocator|firstVisibleElementLocator|submitPreferences"' in /Users/ll/workspace/vreader
 succeeded in 0ms:
12:  public void submitPreferences(org.readium.r2.navigator.epub.EpubPreferences);
13:  public final java.lang.Object evaluateJavascript(java.lang.String, kotlin.coroutines.Continuation<? super java.lang.String>);
41:  public kotlinx.coroutines.flow.StateFlow<org.readium.r2.shared.publication.Locator> getCurrentLocator();
42:  public java.lang.Object firstVisibleElementLocator(kotlin.coroutines.Continuation<? super org.readium.r2.shared.publication.Locator>);
43:  public void submitPreferences(org.readium.r2.navigator.preferences.Configurable$Preferences);

exec
/bin/zsh -lc "awk -F'|' '"'$2 ~ /''^ 13[2345]$/ {print $2 " status=" $6 " notes-prefix=" substr($7,1,240)}'"' docs/features.md
rg -n \"class KeystoreSecretCipher|fun preferencesDataStore|DataStore<Preferences>|readerSettingsStore\" android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt android/app/src/main/kotlin/com/vreader/app -g '*.kt' | head -120
sed -n '1,180p' android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt" in /Users/ll/workspace/vreader
 succeeded in 0ms:
 132 status= VERIFIED  notes-prefix= (root of box F — no deps; chrome files one-writer-coordinate with #129/#131 via nullable-default params). Plan `dev-docs/plans/20260710-feature-132-android-reader-nav-chrome-toc-bookmarks.md` (Gate-1 v4, ~51 WIs). Design authority (lande
 133 status= VERIFIED  notes-prefix= Deps:[feat:#128, feat:#132] (#128 search index MERGED/VERIFIED; #132 reader top-bar Search entry). Plan `dev-docs/plans/20260710-feature-133-android-find-in-book.md` (Gate-1 draft, ~11 WIs). Design authority (landed): vreader-search.jsx 'T
 134 status= VERIFIED  notes-prefix= Deps:[feat:#132] (HARD — ReaderTopChrome/ReaderChromeScaffold/ReaderChromeState land in #132; author line soft-deps #128 DONE). Plan `dev-docs/plans/20260710-feature-134-android-more-menu-book-details-share.md` (Gate-1 v3). Design author
 135 status= VERIFIED  notes-prefix= Deps:[feat:#132] (#132 wires the annotations.json bookmark backup already; #135 needs no backup change). Plan `dev-docs/plans/20260710-feature-135-android-bookmarks.md` (Gate-1 v2, ~21 WIs). Design authority (landed): vreader-reader.jsx to
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:73:    val readerSettingsStore: com.vreader.app.reader.settings.ReaderSettingsStore by lazy {
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:110:    // device-local DataStore under noBackupFilesDir (the readerSettingsStore precedent — recents are
android/app/src/main/kotlin/com/vreader/app/opds/OpdsSourceStore.kt:33:    private val dataStore: DataStore<Preferences>,
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:73:    val readerSettingsStore: com.vreader.app.reader.settings.ReaderSettingsStore by lazy {
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:110:    // device-local DataStore under noBackupFilesDir (the readerSettingsStore precedent — recents are
android/app/src/main/kotlin/com/vreader/app/search/RecentSearchesStore.kt:21:    private val dataStore: DataStore<Preferences>,
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:42:    private val dataStore: DataStore<Preferences>,
android/app/src/main/kotlin/com/vreader/app/backup/net/WebDavServerStore.kt:30:    private val dataStore: DataStore<Preferences>,
android/app/src/main/kotlin/com/vreader/app/backup/net/SecretCipher.kt:29:class KeystoreSecretCipher(private val alias: String = DEFAULT_ALIAS) : SecretCipher {
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:32:    private val dataStore: DataStore<Preferences>,
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:115:            val settingsOrNull by container.readerSettingsStore.settings.collectAsStateWithLifecycle(initialValue = null)
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:180:            container.readerSettingsStore.settings.collect { chromeTheme.value = it.theme }
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:200:            val initialPrefs = EpubPreferences(scroll = true) + container.readerSettingsStore.current().toEpubPreferences()
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:484:            container.readerSettingsStore.settings.collect { settings ->
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:755:            val settings = container.readerSettingsStore.settings.collectAsStateWithLifecycle(initialValue = null).value
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:757:                val store = container.readerSettingsStore
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:127:                    val displayTheme by container.readerSettingsStore.settings
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:216:                                settings = container.readerSettingsStore.settings,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:211:                val settingsOrNull by container.readerSettingsStore.settings
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:570:                            val store = container.readerSettingsStore
// Purpose: Application + manual DI container — feature #106 WI-8. Holds the
// process-singleton Room database, repository, and importer so the Library
// ViewModel gets shared instances (a Hilt module is a Phase-3 follow-on; manual
// wiring at the app edge keeps the foundation bar dependency-light — rule 50 §5).
package com.vreader.app

import android.app.Application
import android.content.Context
import com.vreader.app.data.BookImporter
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import com.vreader.app.reader.BookOpener
import com.vreader.app.search.BookTextExtractor
import com.vreader.app.search.EpubTextExtractor
import com.vreader.app.search.asSearcher
import com.vreader.app.search.SearchIndexCoordinator
import com.vreader.app.search.TxtMdTextExtractor
import com.vreader.app.annotations.AnnotationsRepository
import com.vreader.app.stats.ReadingStatsRepository
import com.vreader.app.stats.ReadingTimeTracker
import com.vreader.app.stats.clock.SystemDateClock
import com.vreader.app.stats.clock.SystemElapsedClock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.map
import vreader.contracts.BookFormat
import java.io.File

/** Process-wide singletons, lazily built. */
class AppContainer(context: Context) {
    private val appContext = context.applicationContext

    val database: VReaderDatabase by lazy { VReaderDatabase.build(appContext) }
    val repository: LibraryRepository by lazy {
        LibraryRepository(database.bookDao(), database.readingPositionDao())
    }
    val importer: BookImporter by lazy {
        BookImporter(File(appContext.filesDir, "books"), repository)
    }

    // feature #122 — reading-stats. The repository + the time tracker are process-singletons so a
    // reading session survives the (shorter-lived) reader ViewModel / rotation. ONE shared DateClock
    // so the dashboard's "today" and the tracker's bucket dates can't drift apart.
    private val dateClock: SystemDateClock by lazy { SystemDateClock() }
    val statsRepository: ReadingStatsRepository by lazy {
        ReadingStatsRepository(database.readingStatsDao(), repository, dateClock)
    }
    val readingTimeTracker: ReadingTimeTracker by lazy {
        ReadingTimeTracker(statsRepository, SystemElapsedClock(), dateClock)
    }

    // feature #123 — annotations (EPUB highlights & notes). Process-singleton so the reader VM /
    // rotation share one instance (the statsRepository precedent).
    val annotationsRepository: AnnotationsRepository by lazy {
        AnnotationsRepository(database.annotationDao())
    }

    // feature #127 — library collections. Process-singleton (the annotationsRepository precedent).
    val collectionRepository: com.vreader.app.data.CollectionRepository by lazy {
        com.vreader.app.data.CollectionRepository(database.collectionDao())
    }

    // feature #129 — reader display settings. A device-local DataStore (the OpdsSourceStore /
    // AiProviderStore precedent), global (not per-book), process-singleton so a settings change
    // propagates to whatever reader is open. Stored under noBackupFilesDir — display prefs are
    // per-device (NOT in the backup contract), so they must be excluded from Android Auto Backup.
    private val readerSettingsDataStore: androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences> by lazy {
        androidx.datastore.preferences.core.PreferenceDataStoreFactory.create {
            File(appContext.noBackupFilesDir, "reader_settings.preferences_pb")
        }
    }
    val readerSettingsStore: com.vreader.app.reader.settings.ReaderSettingsStore by lazy {
        com.vreader.app.reader.settings.ReaderSettingsStore(readerSettingsDataStore)
    }

    /** Process-lifetime scope for fire-and-forget writes that must outlive a screen
     *  (e.g. the reader's onStop position flush — it must finish even as the activity
     *  is being torn down). */
    val appScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    // feature #128 WI-5 — cross-book search index. The coordinator observes the library and
    // streams each indexable book (epub/txt/md) through the WI-3 extractors into WI-4's staging →
    // atomic publish. Eagerly started once from onCreate; pdf/azw3 map to null (never indexable).
    private val bookOpener: BookOpener by lazy { BookOpener(appContext) }
    private val epubTextExtractor: EpubTextExtractor by lazy { EpubTextExtractor(bookOpener) }
    private val txtMdTextExtractor: TxtMdTextExtractor by lazy { TxtMdTextExtractor() }
    val searchIndexCoordinator: SearchIndexCoordinator by lazy {
        SearchIndexCoordinator(
            repository = repository,
            searchDao = database.searchDao(),
            extractorFor = { fmt: BookFormat ->
                when (fmt) {
                    BookFormat.epub -> epubTextExtractor
                    BookFormat.txt, BookFormat.md -> txtMdTextExtractor
                    BookFormat.pdf, BookFormat.azw3 -> null   // metadata-only — never indexed
                }
            },
            scope = appScope,
            ioDispatcher = Dispatchers.IO,
        )
    }

    /** Idempotent — starts the single search-index collector (the coordinator's own AtomicBoolean
     *  makes a repeat call a no-op). Called once from [VReaderApp.onCreate]. */
    fun startSearchIndexing() = searchIndexCoordinator.startSearchIndexing()

    // feature #128 WI-6 — the query pipeline. SearchRepository turns a raw query into an observable
    // Flow of first-hit-per-book text hits (grows as indexing completes); RecentSearchesStore is a
    // device-local DataStore under noBackupFilesDir (the readerSettingsStore precedent — recents are
    // per-device, NOT in the backup contract). The SearchViewModel factory wires the metadata filter,
    // the text-hit Flow, the completeness gate, and recent-recording for the WI-7 screen.
    val searchRepository: com.vreader.app.search.SearchRepository by lazy {
        com.vreader.app.search.SearchRepository(database.searchDao())
    }
    private val recentSearchesDataStore: androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences> by lazy {
        androidx.datastore.preferences.core.PreferenceDataStoreFactory.create {
            File(appContext.noBackupFilesDir, "recent_searches.preferences_pb")
        }
    }
    val recentSearchesStore: com.vreader.app.search.RecentSearchesStore by lazy {
        com.vreader.app.search.RecentSearchesStore(recentSearchesDataStore)
    }

    /**
     * feature #133 WI-10 — the per-reader-session in-book-search ViewModel for a TXT/MD host. Wires the
     * WI-6 [InBookSearchRepository] (FTS DAO page/count/resume + the WI-4 [TxtMdInBookHitResolver] over the
     * already-decoded [decodedText]) behind the WI-8 [InBookSearchViewModel], gated by the WI-7
     * [IndexStateGate] over the DAO's `observeIndexState` Flow and fed the GLOBAL recents store.
     *
     * The EPUB engine seam is NEVER invoked for a TXT/MD host (the repository dispatches only the TXT/MD
     * branch for `txt`/`md`), so `epubEngineFor` is an error-throwing guard — a call would be a wiring bug.
     * ONE [InBookSearchRepository] per session (the VM's `closeAllEpubCursors` lifecycle contract holds
     * uniformly even though TXT has no cursors). [coroutineScope] is the VM's `viewModelScope` in production
     * (the VM cancels its child collectors on `onCleared`).
     */
    fun inBookSearchViewModel(
        bookKey: String,
        format: BookFormat,
        decodedText: String,
        contentSHA256: String,
        fileByteCount: Long,
        coroutineScope: CoroutineScope,
    ): com.vreader.app.search.InBookSearchViewModel {
        val searchDao = database.searchDao()
        val repository = com.vreader.app.search.InBookSearchRepository(
            dispatcher = Dispatchers.Default,
            fts = com.vreader.app.search.InBookFtsDeps(
                matchingChunksPage = { ftsQuery, afterSectionIndex, afterChunkOrdinal, afterId, limit ->
                    searchDao.matchingChunksPage(bookKey, ftsQuery, afterSectionIndex, afterChunkOrdinal, afterId, limit)
                },
                chunkAtOrAfter = { ftsQuery, atSectionIndex, atChunkOrdinal, atId ->
                    searchDao.chunkAtOrAfter(bookKey, ftsQuery, atSectionIndex, atChunkOrdinal, atId)
                },
                // The resolver re-derives the chunk boundaries from the ALREADY-decoded reader text (no I/O);
                // memoized per session inside the resolver (built once).
                resolverFor = {
                    com.vreader.app.search.TxtMdInBookHitResolver(
                        contentSHA256 = contentSHA256,
                        fileByteCount = fileByteCount,
                        format = format.name,
                        decodedText = decodedText,
                    )
                },
            ),
            // TXT/MD never reaches the EPUB branch — a call here is a dispatch bug, fail fast.
            epubEngineFor = { error("EPUB in-book search engine requested on a TXT/MD host") },
        )
        return com.vreader.app.search.InBookSearchViewModel(
            bookKey = bookKey,
            format = format,
            searcher = repository.asSearcher(),
            indexStateGate = com.vreader.app.search.IndexStateGate(Dispatchers.Default),
            indexStateFlow = searchDao.observeIndexState(bookKey),
            // For a settled-`indexed` TXT/MD row the gate consults this to decide Ready vs definitive
            // NoResults. `hasOccurrence` carries no query, so we report Ready (true) and let the actual
            // `page(...)` be the source of truth: a settled book with zero matches runs one fast FTS query
            // and the repository returns NoResults — the SAME UI outcome the gate's occurrence short-circuit
            // would give, without threading the live query through a shared mutable seam (no race). The gate
            // is only consulted on a settled-indexed row, so this never fires while Indexing/missing/failed.

exec
/bin/zsh -lc "nl -ba vreader/Services/AI/ChapterTranslationService.swift | sed -n '300,395p'
nl -ba vreader/Services/AI/ChapterTranslationPrefetcher.swift | sed -n '175,250p'
nl -ba vreader/Views/Reader/Bilingual/EPUBBilingualOrchestrator.swift | sed -n '130,290p'
rg -n \"BilingualInterlinearBody|BilingualPageContent\" dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md android/app/src/main" in /Users/ll/workspace/vreader
 succeeded in 0ms:
   300	                    translatedSegments: translated,
   301	                    sourceParagraphCount: segments.count))
   302	            } catch {
   303	                log.error("Cache-write failed (translation still returned): \(String(describing: error), privacy: .public)")
   304	            }
   305	        }
   306	
   307	        return ChapterTranslationResult(segments: translated, fromCache: false)
   308	    }
   309	
   310	    /// Bug #268: translates a PRE-SEGMENTED list of source segments directly,
   311	    /// bypassing `ChapterSegmenter`. Used by the bilingual EPUB
   312	    /// divergence-fallback: when the DOM leaf-enumerate's block count
   313	    /// diverges from the plain-text paragraph segmentation (nested `<pre>` /
   314	    /// mixed-content `<blockquote>`), translating the enumerate's OWN block
   315	    /// `text[]` makes blocks↔segments 1:1 BY CONSTRUCTION — eliminating the
   316	    /// whole-chapter source-only fallback. The returned array is always the same
   317	    /// length as `segments`.
   318	    ///
   319	    /// Bug #343: the result IS cached now — the canonical row stores the
   320	    /// ENUMERATE's count as its contract, so a toggle/reopen restores via
   321	    /// `cachedTranslation(expectedSegmentCount:)` with zero provider calls.
   322	    /// (#268 originally skipped the cache to avoid thrashing the plain-text
   323	    /// path's differently-counted row; post-#342 there is ONE canonical row
   324	    /// and the divergence fallback is its self-healing writer of last resort.)
   325	    /// A partially-degraded result (Bug #330) is NOT cached, mirroring
   326	    /// `translate`.
   327	    func translatePreSegmented(
   328	        bookFingerprintKey: String,
   329	        unit: TranslationUnitID,
   330	        segments: [String],
   331	        targetLanguage: String,
   332	        providerProfileID: UUID,
   333	        config: ResolvedAIProviderConfig,
   334	        style: TranslationStyle
   335	    ) async throws -> [String] {
   336	        guard !segments.isEmpty else { return [] }
   337	        let chunks = ChapterTranslationChunker.chunk(
   338	            segments: segments, maxCharsPerChunk: maxCharsPerChunk)
   339	        var translated = [String](repeating: "", count: segments.count)
   340	        // Bug #330: same graceful degradation as `translate` — a single chunk's
   341	        // failure leaves its segments source-only; an all-chunks failure surfaces
   342	        // the error.
   343	        var anyChunkSucceeded = false
   344	        var lastChunkError: Error?
   345	        for chunk in chunks {
   346	            do {
   347	                try Task.checkCancellation()
   348	            } catch {
   349	                throw ChapterTranslationError.cancelled
   350	            }
   351	            let chunkSegments = chunk.map { segments[$0] }
   352	            do {
   353	                let chunkResult = try await translateChunk(
   354	                    chunkSegments, targetLanguage: targetLanguage, config: config, style: style)
   355	                for (offset, segmentIndex) in chunk.enumerated() {
   356	                    translated[segmentIndex] = chunkResult[offset]
   357	                }
   358	                anyChunkSucceeded = true
   359	            } catch is CancellationError {
   360	                throw ChapterTranslationError.cancelled
   361	            } catch ChapterTranslationError.cancelled {
   362	                // Bug #330 (Codex): typed cancellation from `send()` must abort,
   363	                // not degrade.
   364	                throw ChapterTranslationError.cancelled
   365	            } catch {
   366	                log.error("Pre-segmented chunk failed (segments \(chunk) source-only): \(String(describing: error), privacy: .public)")
   367	                lastChunkError = error
   368	            }
   369	        }
   370	        if !anyChunkSucceeded, let err = lastChunkError {
   371	            throw err
   372	        }
   373	
   374	        // Bug #343: cache the fully-successful result under the canonical key
   375	        // with the ENUMERATE's count as the stored contract. Mirrors
   376	        // `translate`: a partial degrade is never cached (Bug #330), and a
   377	        // store-write failure does not fail the translation (rule 50 §6).
   378	        if lastChunkError == nil {
   379	            do {
   380	                try await store.upsert(ChapterTranslationRecord(
   381	                    bookFingerprintKey: bookFingerprintKey,
   382	                    unitStorageKey: unit.storageKey,
   383	                    targetLanguage: targetLanguage,
   384	                    providerProfileID: providerProfileID,
   385	                    promptVersion: promptVersion,
   386	                    translatedSegments: translated,
   387	                    sourceParagraphCount: segments.count))
   388	            } catch {
   389	                log.error("Pre-segmented cache-write failed (translation still returned): \(String(describing: error), privacy: .public)")
   390	            }
   391	        }
   392	        return translated
   393	    }
   394	
   395	    // MARK: - Private
   175	        do {
   176	            let result = try await translationService.translate(
   177	                bookFingerprintKey: bookFingerprintKey,
   178	                unit: unit,
   179	                sourceText: sourceText,
   180	                targetLanguage: targetLanguage,
   181	                providerProfileID: providerProfileID,
   182	                config: config,
   183	                style: style,
   184	                granularity: effectiveGranularity
   185	            )
   186	            return result.segments
   187	        } catch {
   188	            Self.log.error("prefetch translate call failed for unit \(String(describing: unit), privacy: .public): \(String(describing: error), privacy: .private)")
   189	            throw error
   190	        }
   191	    }
   192	
   193	    /// Bug #268: translate the render's OWN enumerated block texts directly
   194	    /// (1:1 by construction), bypassing the unit's plain-text segmentation.
   195	    /// Same provider snapshot + resolve + error contract as `translatedSegments`,
   196	    /// then `ChapterTranslationService.translatePreSegmented` (no disk cache).
   197	    func translatedSegmentsDirect(
   198	        for unit: TranslationUnitID,
   199	        sourceSegments: [String],
   200	        targetLanguage: String
   201	    ) async throws -> [String] {
   202	        guard !sourceSegments.isEmpty else { return [] }
   203	        Self.log.debug("prefetchDirect start: unit \(String(describing: unit), privacy: .public), \(sourceSegments.count) segments")
   204	        // Snapshot the active profile + resolve its config (mirrors
   205	        // `translatedSegments` so a provider switch can't straddle).
   206	        guard let activeProfile = await ProviderProfileStore.shared
   207	            .activeProfileSnapshot() else {
   208	            Self.log.error("prefetchDirect: no active provider profile")
   209	            throw ChapterTranslationError.providerFailed("no active provider profile")
   210	        }
   211	        let config: ResolvedAIProviderConfig
   212	        do {
   213	            config = try await aiService.resolveProviderConfig(
   214	                profileID: activeProfile.id, modelOverride: nil)
   215	        } catch {
   216	            Self.log.error("prefetchDirect resolveProviderConfig failed: \(String(describing: error), privacy: .private)")
   217	            throw ChapterTranslationError.providerFailed("provider config unavailable")
   218	        }
   219	        do {
   220	            let out = try await translationService.translatePreSegmented(
   221	                bookFingerprintKey: bookFingerprintKey,
   222	                unit: unit,
   223	                segments: sourceSegments,
   224	                targetLanguage: targetLanguage,
   225	                providerProfileID: activeProfile.id,
   226	                config: config,
   227	                style: style)
   228	            Self.log.debug("prefetchDirect ok: \(out.count) translated segments")
   229	            return out
   230	        } catch {
   231	            Self.log.error("prefetchDirect translatePreSegmented failed: \(String(describing: error), privacy: .private)")
   232	            throw error
   233	        }
   234	    }
   235	
   236	    /// Bug #343: cache-only restore for the divergence fallback — serves the
   237	    /// canonical row when its stored contract matches the enumerate's own
   238	    /// block count. Needs no provider config (the #306 pre-gate precedent).
   239	    func cachedSegmentsDirect(
   240	        for unit: TranslationUnitID,
   241	        expectedCount: Int,
   242	        targetLanguage: String
   243	    ) async -> [String]? {
   244	        await translationService.cachedTranslation(
   245	            bookFingerprintKey: bookFingerprintKey,
   246	            unit: unit,
   247	            expectedSegmentCount: expectedCount,
   248	            targetLanguage: targetLanguage)?.segments
   249	    }
   250	}
   130	    ) {
   131	        // Drop empty bucketing so `blocksBySection[sectionIndex]` is
   132	        // either present-and-non-empty or absent.
   133	        if blocks.isEmpty {
   134	            blocksBySection[sectionIndex] = nil
   135	        } else {
   136	            blocksBySection[sectionIndex] = blocks
   137	        }
   138	    }
   139	
   140	    /// Clear the cached blocks for one stitched section (e.g. after the
   141	    /// section is evicted from the continuous-scroll window). Idempotent.
   142	    func clearBlocks(forSection sectionIndex: Int) {
   143	        blocksBySection[sectionIndex] = nil
   144	    }
   145	
   146	    /// Feature #71 WI-7 (Gate-4 round-2): the section keys currently cached,
   147	    /// ascending (render order). The container iterates these to reinject every
   148	    /// MATERIALIZED stitched section whose translation unit just resolved — a
   149	    /// `.readerBilingualDidChange` (prefetch lands) for one section must
   150	    /// reinject only the sections that have blocks, not assume the current
   151	    /// visible locator's section. The paged path's single `-1` bucket appears
   152	    /// here too, so an unscoped caller is unaffected.
   153	    var materializedSections: [Int] {
   154	        blocksBySection.keys.sorted()
   155	    }
   156	
   157	    /// Builds inject JS for the current blocks given an ordered
   158	    /// `[String]` of translated segments (the VM's cache for the
   159	    /// current unit). Returns `nil` when there is nothing to inject
   160	    /// — either no enumerate has run yet or no translations are
   161	    /// available.
   162	    ///
   163	    /// A short translation array maps the prefix and leaves the rest
   164	    /// as source-only (silent-source-fallback semantics — plan
   165	    /// Decision 2).
   166	    ///
   167	    /// Feature #71 WI-7: when `sectionIndex` is provided, only that
   168	    /// section's blocks are paired + injected so one stitched
   169	    /// chapter's translation never spills into an adjacent section.
   170	    /// `sectionIndex == nil` keeps the original semantics (the
   171	    /// flattened `currentBlocks`) for the paged path + bulk callers.
   172	    func buildInjectJS(
   173	        translatedSegments: [String]?,
   174	        forSection sectionIndex: Int? = nil
   175	    ) -> String? {
   176	        guard let segments = translatedSegments, !segments.isEmpty else {
   177	            return nil
   178	        }
   179	        let scoped: [BilingualBlock]
   180	        if let sectionIndex {
   181	            scoped = blocksBySection[sectionIndex] ?? []
   182	        } else {
   183	            scoped = currentBlocks
   184	        }
   185	        guard !scoped.isEmpty else { return nil }
   186	        let map = EPUBBilingualPipeline.translationsByBid(
   187	            blocks: scoped,
   188	            translatedSegments: segments
   189	        )
   190	        guard !map.isEmpty else { return nil }
   191	        return EPUBBilingualJS.bilingualInjectJS(
   192	            translationsByBid: map,
   193	            spineIndex: sectionIndex,
   194	            targetIsCJK: targetIsCJK
   195	        )
   196	    }
   197	
   198	    /// Feature #77: builds the LOADING-shimmer inject JS for a section's enumerated
   199	    /// bids (section/unit-scoped — all the in-flight unit's bids get the shimmer
   200	    /// until each translation lands and replaces it in place). `sectionIndex == nil`
   201	    /// uses the flattened `currentBlocks` (paged path). Returns `nil` when there are
   202	    /// no enumerated blocks for the scope. The loading-inject JS itself skips any bid
   203	    /// that already has a decoration, so it never downgrades a landed translation.
   204	    func buildLoadingJS(forSection sectionIndex: Int? = nil) -> String? {
   205	        let scoped: [BilingualBlock]
   206	        if let sectionIndex {
   207	            scoped = blocksBySection[sectionIndex] ?? []
   208	        } else {
   209	            scoped = currentBlocks
   210	        }
   211	        guard !scoped.isEmpty else { return nil }
   212	        return EPUBBilingualJS.bilingualInjectLoadingJS(
   213	            loadingBids: scoped.map(\.bid),
   214	            spineIndex: sectionIndex,
   215	            targetIsCJK: targetIsCJK
   216	        )
   217	    }
   218	
   219	    /// Feature #77: JS that removes ONLY the loading-shimmer decoration nodes (a
   220	    /// failed / cancelled prefetch), leaving landed translations intact. The
   221	    /// translation-landed path replaces a shimmer in place, so the shimmer must
   222	    /// NOT be removed there — only here, for the no-translation outcome.
   223	    ///
   224	    /// Feature #77 WI-5: `spineIndex` scopes the clear to one stitched
   225	    /// continuous-scroll section (a global clear would remove OTHER still-fetching
   226	    /// sections' shimmers). `nil` (the paged default) clears the whole document.
   227	    func clearLoadingJS(spineIndex: Int? = nil) -> String {
   228	        EPUBBilingualJS.bilingualClearLoadingJS(spineIndex: spineIndex)
   229	    }
   230	
   231	    /// Feature #71 WI-7 (Gate-4 round-2 HIGH 2): build ONE inject JS payload
   232	    /// covering MULTIPLE stitched sections at once, pairing each section's
   233	    /// ordered segments against ONLY that section's bids.
   234	    ///
   235	    /// This is the continuous-scroll reinject path. Two problems the
   236	    /// per-section single-payload approach solved would otherwise recur:
   237	    ///   1. **Single-slot overwrite (MEDIUM 1 sibling).** Pushing one
   238	    ///      per-section inject through the bridge's single `pendingHighlightJS`
   239	    ///      slot means a second section's inject overwrites the first before
   240	    ///      the bridge evaluates it. A combined payload injects every section's
   241	    ///      blocks in one eval.
   242	    ///   2. **Cross-section flatten (the HIGH 2 bug).** Pairing the VM's
   243	    ///      per-unit segments against the FLATTENED `currentBlocks`
   244	    ///      (multi-section) would either no-op the Bug #266 1:1 count guard or
   245	    ///      pair section A's segments against section B's blocks. Scoping each
   246	    ///      section's segments to its own bucket keeps the 1:1 pairing per
   247	    ///      section.
   248	    ///
   249	    /// `translationsBySection` maps `sectionIndex → ordered translated
   250	    /// segments` (the VM's cache for that section's unit). A section whose
   251	    /// segment count does not match its block count is dropped (Bug #266
   252	    /// source-only fallback) — the others still inject. Returns `nil` when no
   253	    /// section produced a non-empty 1:1 map.
   254	    func buildInjectJS(translationsBySection: [Int: [String]]) -> String? {
   255	        var combined: [String: String] = [:]
   256	        for sectionIndex in translationsBySection.keys.sorted() {
   257	            guard let segments = translationsBySection[sectionIndex],
   258	                  !segments.isEmpty,
   259	                  let blocks = blocksBySection[sectionIndex], !blocks.isEmpty else {
   260	                continue
   261	            }
   262	            // Per-section 1:1 pairing (Bug #266): a count mismatch yields an
   263	            // empty map for that section → it stays source-only, the rest still
   264	            // inject. Bids are section-namespaced (`s{N}b…`) so the merge across
   265	            // sections cannot collide keys.
   266	            let map = EPUBBilingualPipeline.translationsByBid(
   267	                blocks: blocks, translatedSegments: segments)
   268	            for (bid, translation) in map { combined[bid] = translation }
   269	        }
   270	        guard !combined.isEmpty else { return nil }
   271	        // bids are already globally unique (section-namespaced), so the global
   272	        // bid-keyed inject resolves each block in its own section.
   273	        return EPUBBilingualJS.bilingualInjectJS(
   274	            translationsByBid: combined, targetIsCJK: targetIsCJK)
   275	    }
   276	}
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:5:**Design authority (rule 51):** the **authoritative** bilingual surfaces are in `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx` (`BilingualSetupSheet` / `BilingualPageContent` / `BilingualPill` / `BILINGUAL_LANGS`) and `.../vreader-reader.jsx` (`ReaderTopChrome` renders `BilingualPill`; the bilingual toggle is a More-menu row via `onMoreAction`) and `.../vreader-more.jsx` (the "Bilingual mode" More-menu Row toggle). `.../vreader-ai-android.jsx` contains a SECOND, differently-shaped `BilingualSetupSheet` — see §3's setup-sheet resolution for why this plan reproduces the `vreader-bilingual.jsx` sheet and design-gates the divergence. Where a surface is NOT depicted it is scoped out and flagged.
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:71:- `bilingual/BilingualInterlinearBody.kt` — per source chunk/paragraph: source `Text` then translation `Text` muted with accent left-border, `fontSize*0.88`, CJK font for cjk scripts, RTL handling for Arabic script. Consumes `translationsByUnit`. Loading state ("Translating chapter… N%" + per-paragraph dim — matches the design's chapter-level "38%"). Error state ("Couldn't translate" + Retry). Partial/offline (`unavailableUnits`): source-only silent fallback (design's original-always-kept guarantee — iOS Decision 2). This is the render surface for BOTH the TXT/MD Compose loop and (via the WI-0 adapter) the EPUB injection payload's Kotlin-side state.
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:77:- `reader/TxtReaderActivity.kt` — own a `BilingualViewModel`; collect state; pass into `TxtBody`; on position change call `vm.onPositionChanged(...)`; render `BilingualInterlinearBody` output in the `items(count = document.chunkCount)` loop when bilingual is on and a translation exists (the confirmed injection point — verified it already interleaves highlight washes + TTS spans per chunk). Strictly gated to `originalFormat ∈ {txt, md}`; disabled = body byte-unchanged. **This file overlaps #129's TXT/MD WIs → gated on #129's FINAL merge (§4).**
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:136:v1 merged both into a **third layout** — a rule-51 violation (self-designed UI). **Resolution:** this plan reproduces the **`vreader-bilingual.jsx` sheet EXACTLY** as the authoritative Android-native bilingual sheet (its language grid + granularity + preview + engine strip + CTA is the coherent bilingual-config surface, and its `BilingualPill`/`BilingualPageContent` are the matching reader surfaces). **Style is dropped from v1** (it is not in the authoritative sheet, and — verified — `bilingualStyle` is not a persisted contract field on either platform). Consequently the store/VM carry no `style`, and `promptVersion`'s `s=` component is a constant (§2 cache-identity correction).
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:173:**WI-7b (behavioral): EPUB render adapter** (only if WI-0 = go). The JS enumerate/inject adapter + `EpubChapterTextProvider`, wired into `ReaderActivity`, driving `BilingualInterlinearBody` state from injected content. Deps: **WI-0, WI-3, WI-4, WI-7a**. Connected test on a real EPUB (seeded cache): enable → interlinear injects; disable → nodes cleared; reflow/href-change re-applies. (If WI-0 = no-go, this WI is dropped and box D ships TXT/MD-only, tracked.)
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:185:Compose UI (`androidTest/...bilingual/`): `BilingualSetupSheetUiTest` (language grid, granularity, preview, engine configured vs unconfigured; **no Style control present**; light+dark); `BilingualInterlinearBodyUiTest` (translated incl. CJK font + RTL Arabic; loading N%+dimmed; error+Retry; offline source-only; empty translation→source-only no crash); `BilingualPillUiTest`.

exec
/bin/zsh -lc "rg -n \"AiProviderListScreen|AiSettingsViewModel|AiProviderStore|Open.*AI|Settings|MoreAction|ReaderMore\" android/app/src/main/kotlin/com/vreader/app -g '*.kt' | head -240
rg -n \"Set up|No AI provider|Bilingual mode|Translation engine\" dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx dev-docs/designs/vreader-fidelity-v1/project/vreader-more.jsx" in /Users/ll/workspace/vreader
 succeeded in 0ms:
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:65:    // AiProviderStore precedent), global (not per-book), process-singleton so a settings change
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:68:    private val readerSettingsDataStore: androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences> by lazy {
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:73:    val readerSettingsStore: com.vreader.app.reader.settings.ReaderSettingsStore by lazy {
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:74:        com.vreader.app.reader.settings.ReaderSettingsStore(readerSettingsDataStore)
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:110:    // device-local DataStore under noBackupFilesDir (the readerSettingsStore precedent — recents are
android/app/src/main/kotlin/com/vreader/app/stats/StatsDashboard.kt:4:// table (Time + Hl/Nt + a per-row time hairline). Reuses the backup AppSheet/SettingsCard +
android/app/src/main/kotlin/com/vreader/app/stats/StatsDashboard.kt:35:import com.vreader.app.backup.SettingsCard
android/app/src/main/kotlin/com/vreader/app/stats/StatsDashboard.kt:84:    SettingsCard {
android/app/src/main/kotlin/com/vreader/app/stats/StatsDashboard.kt:116:    SettingsCard {
android/app/src/main/kotlin/com/vreader/app/stats/StatsDashboard.kt:140:    SettingsCard {
android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsSourceListScreen.kt:4:// vocabulary (NavScreen / SettingsCard / GroupHeader / GroupFooter / StatusDot / tokens). Stateless:
android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsSourceListScreen.kt:42:import com.vreader.app.backup.SettingsCard
android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsSourceListScreen.kt:75:                SettingsCard {
android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsSourceListScreen.kt:103:    SettingsCard {
android/app/src/main/kotlin/com/vreader/app/backup/ServerEditSheet.kt:73:                SettingsCard {
android/app/src/main/kotlin/com/vreader/app/backup/ServerEditSheet.kt:84:                SettingsCard {
android/app/src/main/kotlin/com/vreader/app/backup/ServerEditSheet.kt:91:                SettingsCard {
android/app/src/main/kotlin/com/vreader/app/backup/ServerEditSheet.kt:104:                SettingsCard {
android/app/src/main/kotlin/com/vreader/app/backup/ServerEditSheet.kt:115:                    SettingsCard {
android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsAddSheet.kt:43:import com.vreader.app.backup.SettingsCard
android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsAddSheet.kt:76:                SettingsCard {
android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsAddSheet.kt:85:                SettingsCard {
android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsAddSheet.kt:103:                SettingsCard {
android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsAddSheet.kt:114:                    SettingsCard {
android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsSourcesViewModel.kt:4:// #118 AiSettingsViewModel test path), and saves/deletes. The password is never logged.
android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsSourcesViewModel.kt:50:    // closed form). Mirrors AiSettingsViewModel.testGen.
android/app/src/main/kotlin/com/vreader/app/tts/TtsVoiceSheet.kt:3:// not-installed → Download). Reuses the backup AppSheet/SettingsCard + BackupTokens. Stateless.
android/app/src/main/kotlin/com/vreader/app/tts/TtsVoiceSheet.kt:36:import com.vreader.app.backup.SettingsCard
android/app/src/main/kotlin/com/vreader/app/tts/TtsVoiceSheet.kt:60:                SettingsCard {
android/app/src/main/kotlin/com/vreader/app/tts/TtsVoiceSheet.kt:76:            SettingsCard {
android/app/src/main/kotlin/com/vreader/app/backup/BackupRestoreScreen.kt:60:                    SettingsCard {
android/app/src/main/kotlin/com/vreader/app/backup/BackupRestoreScreen.kt:77:    SettingsCard {
android/app/src/main/kotlin/com/vreader/app/backup/BackupRestoreScreen.kt:144:    SettingsCard {
android/app/src/main/kotlin/com/vreader/app/backup/BackupRestoreScreen.kt:184:            "Open Server Settings",
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderFactory.kt:3:// AiProviderStore.snapshot(), decrypts via apiKey(profile), and calls this — so the client is built
android/app/src/main/kotlin/com/vreader/app/backup/BackupViewModel.kt:106:    fun openServerSettings() {
android/app/src/main/kotlin/com/vreader/app/backup/BackupViewModel.kt:107:        viewModelScope.launch { _events.send(BackupEvent.OpenServerSettings) }
android/app/src/main/kotlin/com/vreader/app/backup/BackupUiState.kt:30:    data object OpenServerSettings : BackupEvent
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:4:// Reuses the shared form vocabulary (NavScreen / SettingsCard / GroupHeader / StatusDot / tokens —
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:41:import com.vreader.app.backup.SettingsCard
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:46:fun AiProviderListScreen(
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:65:                SettingsCard {
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:96:        GroupFooter("Works with Anthropic, OpenAI-compatible endpoints, and local models.")
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:41:class AiProviderStore(
android/app/src/main/kotlin/com/vreader/app/backup/BackupScaffold.kt:55:/** Back ("Settings") + serif title (large title below, or centered compact), optional trailing. */
android/app/src/main/kotlin/com/vreader/app/backup/BackupScaffold.kt:74:                Text("Settings", color = t.tint, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.Medium)
android/app/src/main/kotlin/com/vreader/app/backup/BackupScaffold.kt:113:fun SettingsCard(content: @Composable ColumnScope.() -> Unit) {
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt:2:// iOS AITypes (AIRequest/AIResponse/AIStreamChunk/AIError). Provider-neutral; the OpenAI vs
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt:10:/** A chat request. `system` is the system prompt (Anthropic carries it top-level; the OpenAI
android/app/src/main/kotlin/com/vreader/app/ai/AiChatPanel.kt:49:    onOpenSettings: () -> Unit = {},
android/app/src/main/kotlin/com/vreader/app/ai/AiChatPanel.kt:78:                state.unconfigured -> UnconfiguredGate(onOpenSettings)
android/app/src/main/kotlin/com/vreader/app/ai/AiChatPanel.kt:89:private fun UnconfiguredGate(onOpenSettings: () -> Unit) {
android/app/src/main/kotlin/com/vreader/app/ai/AiChatPanel.kt:96:        Text("Chat and summaries need an AI provider. Add one in Settings — it takes a key and a minute.", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 13.5.sp, lineHeight = 20.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
android/app/src/main/kotlin/com/vreader/app/ai/AiChatPanel.kt:99:                .clickable(onClick = onOpenSettings).testTag("ai-open-settings").padding(horizontal = 20.dp, vertical = 11.dp),
android/app/src/main/kotlin/com/vreader/app/ai/AiChatPanel.kt:100:        ) { Text("Open AI settings", color = Color.White, fontFamily = BackupFonts.Sans, fontSize = 14.sp, fontWeight = FontWeight.SemiBold) }
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheet.kt:2:// (vreader-panels.jsx ReaderSettingsSheet): a Theme 5-swatch row, a Font serif/sans toggle, and
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheet.kt:4:// `theme={t}` surface), so Dark/OLED/Photo look right. Pure function of [ReaderSettings] + callbacks;
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheet.kt:5:// the content is extracted ([ReaderSettingsSheetContent]) for direct UI testing (the #127 precedent).
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheet.kt:41:fun ReaderSettingsSheet(
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheet.kt:42:    settings: ReaderSettings,
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheet.kt:57:        ReaderSettingsSheetContent(settings, onTheme, onFontFamily, onFontSize, onLineSpacing, onMargin)
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheet.kt:61:/** The sheet content (extracted for direct UI testing). Colors derive from the active [ReaderSettings.theme]. */
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheet.kt:63:fun ReaderSettingsSheetContent(
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheet.kt:64:    settings: ReaderSettings,
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheet.kt:98:            valueRange = ReaderSettings.MIN_FONT_SIZE..ReaderSettings.MAX_FONT_SIZE,
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheet.kt:107:            valueRange = ReaderSettings.MIN_LINE_SPACING..ReaderSettings.MAX_LINE_SPACING,
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheet.kt:116:            valueRange = ReaderSettings.MIN_MARGIN..ReaderSettings.MAX_MARGIN,
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderScreen.kt:4:// theme-derived viewer backdrop (feature #129 WI-7: the backdrop = the global ReaderSettingsStore
android/app/src/main/kotlin/com/vreader/app/search/RecentSearchesStore.kt:3:// noBackupFilesDir (recents are per-device, NOT in the backup contract — the ReaderSettingsStore /
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:178:        // value + live updates), mirroring how observeDisplaySettings feeds the navigator.
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:180:            container.readerSettingsStore.settings.collect { chromeTheme.value = it.theme }
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:200:            val initialPrefs = EpubPreferences(scroll = true) + container.readerSettingsStore.current().toEpubPreferences()
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:238:            observeDisplaySettings(nav)
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:482:    private fun observeDisplaySettings(nav: EpubNavigatorFragment) {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:484:            container.readerSettingsStore.settings.collect { settings ->
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:686:                DisplaySettingsHost {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:751:    private fun DisplaySettingsHost(content: @androidx.compose.runtime.Composable () -> Unit) {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:755:            val settings = container.readerSettingsStore.settings.collectAsStateWithLifecycle(initialValue = null).value
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:757:                val store = container.readerSettingsStore
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:758:                com.vreader.app.reader.settings.ReaderSettingsSheet(
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:896:     *  for its EpubSettings (the applied theme background), or null before the navigator/settings exist.
android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt:2:// ACTIVE provider from one AiProviderStore snapshot, streams a chat answer (accumulating deltas),
android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt:24:    private val store: AiProviderStore,
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettings.kt:2:// `TypographySettings` + `ReaderThemeV2`. Global (not per-book), device-local (not backed up). The
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettings.kt:4:// are the committed design's slider bounds (vreader-panels.jsx ReaderSettingsSheet).
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettings.kt:12: * (its background). A pure value type — the [ReaderSettingsStore] persists it, the hosts apply it.
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettings.kt:14:data class ReaderSettings(
android/app/src/main/kotlin/com/vreader/app/reader/Azw3DisplayCss.kt:1:// Purpose: feature #129 WI-6 (#110 Phase 3) — the pure `ReaderSettings → foliate CSS blob` the AZW3
android/app/src/main/kotlin/com/vreader/app/reader/Azw3DisplayCss.kt:12:// @coordinates-with: Azw3ReaderActivity.kt (collects ReaderSettings, injects the CSS through the
android/app/src/main/kotlin/com/vreader/app/reader/Azw3DisplayCss.kt:13://   FoliateBridge setStyles seam on change), FoliateBridge.kt (exposes setStyles), ReaderSettings.kt /
android/app/src/main/kotlin/com/vreader/app/reader/Azw3DisplayCss.kt:19:import com.vreader.app.reader.settings.ReaderSettings
android/app/src/main/kotlin/com/vreader/app/reader/Azw3DisplayCss.kt:29: * The deterministic foliate CSS blob for these display [ReaderSettings] — raw CSS (no `<style>` wrapper),
android/app/src/main/kotlin/com/vreader/app/reader/Azw3DisplayCss.kt:30: * as `readerAPI.setStyles(css)` expects. Assumes clamped inputs (the [ReaderSettingsStore] clamps on read
android/app/src/main/kotlin/com/vreader/app/reader/Azw3DisplayCss.kt:33:fun ReaderSettings.foliateDisplayCss(): String {
android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeScaffold.kt:50:import com.vreader.app.reader.more.MoreActionId
android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeScaffold.kt:256:    MoreRow.Action(id = MoreActionId.DETAILS, label = "Book details", icon = Icons.Filled.Info, onTap = onDetails),
android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeScaffold.kt:257:    MoreRow.Action(id = MoreActionId.SHARE, label = "Share book", icon = Icons.Filled.Share, onTap = onShare),
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderTextStyles.kt:1:// Purpose: feature #129 WI-4 (#110 Phase 3) — the pure `ReaderSettings → Compose TextStyle` mapping
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderTextStyles.kt:4:// (VReaderFonts design approximations). Pure value types (JVM-unit-testable, TxtDisplaySettingsTest).
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderTextStyles.kt:9://   ReaderSettings.kt (the value type + clamped ranges this maps from).
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderTextStyles.kt:27: * Assumes clamped inputs (the [ReaderSettingsStore] clamps on read AND write).
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderTextStyles.kt:29:fun ReaderSettings.bodyTextStyle(): TextStyle = TextStyle(
android/app/src/main/kotlin/com/vreader/app/reader/PdfDisplayBackdrop.kt:1:// Purpose: feature #129 WI-7 (#110 Phase 3) — the pure `ReaderSettings → PDF viewer backdrop Color`
android/app/src/main/kotlin/com/vreader/app/reader/PdfDisplayBackdrop.kt:3:// inherits ONLY the theme background from the global ReaderSettingsStore — font family/size/spacing/
android/app/src/main/kotlin/com/vreader/app/reader/PdfDisplayBackdrop.kt:9:// @coordinates-with: PdfReaderActivity.kt (collects ReaderSettings, applies pdfBackdrop() to the
android/app/src/main/kotlin/com/vreader/app/reader/PdfDisplayBackdrop.kt:10://   viewer backdrop live), ReaderSettings.kt / ReaderTheme.kt (the value type + theme colors).
android/app/src/main/kotlin/com/vreader/app/reader/PdfDisplayBackdrop.kt:14:import com.vreader.app.reader.settings.ReaderSettings
android/app/src/main/kotlin/com/vreader/app/reader/PdfDisplayBackdrop.kt:18: * [ReaderSettings]. PDF applies the theme background ONLY (it can't reflow, so typography is inert);
android/app/src/main/kotlin/com/vreader/app/reader/PdfDisplayBackdrop.kt:21:fun ReaderSettings.pdfBackdrop(): Color = theme.background
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:2:// AiProviderStore for the list, owns the editor form state, runs Test Connection against the LIVE
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:20:class AiSettingsViewModel(
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:21:    private val store: AiProviderStore,
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderKind.kt:32:            openAiCompatible -> "OpenAI-compatible"
android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderBottomChrome.kt:4:// "Display" (Aa) slot (opens the WI-2 ReaderSettingsSheet) plus an optional host-provided extraSlot
android/app/src/main/kotlin/com/vreader/app/ai/OpenAiCompatibleProvider.kt:1:// Purpose: feature #118 WI-2 (#110 Phase 3) — the OpenAI-compatible chat client (OpenAI, Azure,
android/app/src/main/kotlin/com/vreader/app/ai/OpenAiCompatibleProvider.kt:4:// `choices[0].message.content`. Mirrors iOS OpenAICompatibleProvider.
android/app/src/main/kotlin/com/vreader/app/ai/SseEventReader.kt:3:// interpret each event's data). Handles the SSE wire rules that both OpenAI and Anthropic streams
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:1:// Purpose: feature #129 WI-1 (#110 Phase 3) — persists the reader "Display" [ReaderSettings] in
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:2:// DataStore (the OpdsSourceStore / AiProviderStore JSON-in-Preferences precedent). Global, device-
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:23:private data class ReaderSettingsState(
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:26:    val fontSizeSp: Float = ReaderSettings.DEFAULT_FONT_SIZE,
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:27:    val lineSpacing: Float = ReaderSettings.DEFAULT_LINE_SPACING,
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:28:    val marginDp: Float = ReaderSettings.DEFAULT_MARGIN,
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:31:class ReaderSettingsStore(
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:62:    val settings: Flow<ReaderSettings> = dataStore.data.map { read(it).toSettings() }
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:65:    suspend fun current(): ReaderSettings = read(dataStore.data.first()).toSettings()
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:72:    suspend fun setFontSize(sp: Float, order: Long = nextSeq()) = update(Field.FONT_SIZE, order) { it.copy(fontSizeSp = ReaderSettings.clampFontSize(sp)) }
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:73:    suspend fun setLineSpacing(v: Float, order: Long = nextSeq()) = update(Field.LINE_SPACING, order) { it.copy(lineSpacing = ReaderSettings.clampLineSpacing(v)) }
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:74:    suspend fun setMargin(dp: Float, order: Long = nextSeq()) = update(Field.MARGIN, order) { it.copy(marginDp = ReaderSettings.clampMargin(dp)) }
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:76:    private suspend fun update(field: Field, order: Long, transform: (ReaderSettingsState) -> ReaderSettingsState) {
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:88:    private fun ReaderSettingsState.normalized() = copy(
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:89:        fontSizeSp = ReaderSettings.clampFontSize(fontSizeSp),
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:90:        lineSpacing = ReaderSettings.clampLineSpacing(lineSpacing),
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:91:        marginDp = ReaderSettings.clampMargin(marginDp),
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:94:    private fun read(prefs: Preferences): ReaderSettingsState {
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:95:        val raw = prefs[KEY] ?: return ReaderSettingsState()
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:96:        return runCatching { json.decodeFromString<ReaderSettingsState>(raw) }.getOrDefault(ReaderSettingsState())
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:101:    private fun ReaderSettingsState.toSettings() = ReaderSettings(
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:104:        fontSizeSp = ReaderSettings.clampFontSize(fontSizeSp),
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:105:        lineSpacing = ReaderSettings.clampLineSpacing(lineSpacing),
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:106:        marginDp = ReaderSettings.clampMargin(marginDp),
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt:51:import com.vreader.app.backup.SettingsCard
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt:90:                SettingsCard { Field("", state.name, "e.g. OpenRouter", onName) }
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt:94:                SettingsCard {
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt:103:                SettingsCard {
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt:111:                SettingsCard {
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt:129:                SettingsCard {
android/app/src/main/kotlin/com/vreader/app/reader/EpubPreferencesMapper.kt:1:// Purpose: feature #129 WI-5 (#110 Phase 3) — the pure `ReaderSettings → EpubPreferences` mapping the
android/app/src/main/kotlin/com/vreader/app/reader/EpubPreferencesMapper.kt:12://   ReaderSettings.kt / ReaderTheme.kt (the value type + theme colors this maps from).
android/app/src/main/kotlin/com/vreader/app/reader/EpubPreferencesMapper.kt:17:import com.vreader.app.reader.settings.ReaderSettings
android/app/src/main/kotlin/com/vreader/app/reader/EpubPreferencesMapper.kt:24: *  hardcoded body size and [ReaderSettings.DEFAULT_FONT_SIZE]. */
android/app/src/main/kotlin/com/vreader/app/reader/EpubPreferencesMapper.kt:32: * Map these display [ReaderSettings] to a Readium [EpubPreferences] for live submission. Assumes clamped
android/app/src/main/kotlin/com/vreader/app/reader/EpubPreferencesMapper.kt:33: * inputs (the [ReaderSettingsStore] clamps on read AND write). Only the typography/theme fields #129 owns
android/app/src/main/kotlin/com/vreader/app/reader/EpubPreferencesMapper.kt:37:fun ReaderSettings.toEpubPreferences(): EpubPreferences = EpubPreferences(
android/app/src/main/kotlin/com/vreader/app/ai/AiClient.kt:6:// parse (OpenAI vs Anthropic). The API key + auth headers are NEVER logged.
android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt:2:// rendered by [MorePopup]. A `sealed interface` so each row carries a stable [MoreActionId] + its own
android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt:19:enum class MoreActionId {
android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt:28:val MoreActionId.slug: String
android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt:42:    val id: MoreActionId
android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt:48:        override val id: MoreActionId,
android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt:57:        override val id: MoreActionId,
android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt:67:        override val id: MoreActionId,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:10:// feature #129 WI-4: the reader collects ReaderSettingsStore.settings live and applies them —
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:13:// slot, replacing the pre-chrome TtsEntryBar) which opens the ReaderSettingsSheet.
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:130:import com.vreader.app.reader.settings.ReaderSettings
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:131:import com.vreader.app.reader.settings.ReaderSettingsSheet
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:211:                val settingsOrNull by container.readerSettingsStore.settings
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:216:                    is TxtUiState.Loading -> TxtLoadingScaffold((settingsOrNull ?: ReaderSettings()).theme)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:219:                        val displaySettings = checkNotNull(settingsOrNull)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:387:                            theme = displaySettings.theme,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:432:                                        theme = displaySettings.theme,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:471:                                    theme = displaySettings.theme,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:492:                                            theme = displaySettings.theme,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:514:                                    textStyle = displaySettings.bodyTextStyle(),
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:515:                                    marginDp = displaySettings.marginDp,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:570:                            val store = container.readerSettingsStore
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:571:                            ReaderSettingsSheet(
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:572:                                settings = displaySettings,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:632:     *  (there is no public Settings.ACTION_TTS_SETTINGS — fall back to accessibility / settings). */
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:638:                android.content.Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS),
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:639:                android.content.Intent(android.provider.Settings.ACTION_SETTINGS),
android/app/src/main/kotlin/com/vreader/app/backup/WebDavServersScreen.kt:57:                SettingsCard {
android/app/src/main/kotlin/com/vreader/app/backup/WebDavServersScreen.kt:65:                SettingsCard {
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:10:// the global ReaderSettingsStore — no font/size/spacing, and NO Display sheet / NO Aa slot (a
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:13:// bright frame) and threads `ReaderSettings.pdfBackdrop()` (= theme.background) to the viewer backdrop.
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:23://   (the settings→backdrop mapping), ReaderSettingsStore (the live settings source), AnnotationsRepository
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:115:            val settingsOrNull by container.readerSettingsStore.settings.collectAsStateWithLifecycle(initialValue = null)
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:127:                    val displayTheme by container.readerSettingsStore.settings
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:128:                        .collectAsStateWithLifecycle(initialValue = com.vreader.app.reader.settings.ReaderSettings())
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:216:                                settings = container.readerSettingsStore.settings,
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:337:    settings: kotlinx.coroutines.flow.Flow<com.vreader.app.reader.settings.ReaderSettings>,
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:350:    val displaySettings by settings.collectAsStateWithLifecycle(initialValue = com.vreader.app.reader.settings.ReaderSettings())
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:391:    // render (reload / render-death recovery) re-records the CSS, and on `displaySettings` so a live
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:394:    LaunchedEffect(holder, displaySettings) { holder.document.setStyles(displaySettings.foliateDisplayCss()) }
dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx:1:// Bilingual mode — feature #60 follow-up (#790)
dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx:33:    <Sheet theme={t} onClose={onClose} title="Bilingual mode" height={620}>
dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx:105:          <SectionLabel theme={t}>Translation engine</SectionLabel>
dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx:126:                {aiConfigured ? 'Claude · with this book\'s context' : 'No AI provider configured'}
dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx:131:                  : 'Bilingual mode needs an AI provider to translate.'}
dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx:142:            }}>{aiConfigured ? 'Change…' : 'Set up'}</button>
dev-docs/designs/vreader-fidelity-v1/project/vreader-more.jsx:92:          <Row icon={Icons.Translate} label="Bilingual mode"
dev-docs/designs/vreader-fidelity-v1/project/vreader-more.jsx:97:          <Row icon={Icons.Translate} label="Bilingual mode"

exec
/bin/zsh -lc "rg -n \"box D|\\| D|Bilingual|bilingual\" docs/parity/android-checklist.md -C 4
nl -ba android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt | sed -n '1,100p'
nl -ba android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeScaffold.kt | sed -n '225,275p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
80-  proven end-to-end over live WebDAV; delete UI deferred to needs-design #1875) + #128 search (Android
81-  `Book` has no author field + no cross-format FTS → search design/data gap, filed separately — NOT yet
82-  done). Box C checks when BOTH #127 and #128 are VERIFIED — #127 ✓, #128 remains.**
83-
84:- [ ] **D. Bilingual interlinear reading** — interlinear original+translation rendering + the bilingual
85-  setup sheet (languages · provider · model · style), building on the #118 AI provider.
86:  Design: `vreader-ai-android.jsx` (BilingualReader/BilingualSetupSheet) + `vreader-bilingual.jsx`.
87-  Note: the pipeline + UI are buildable autonomously; LIVE translation verification is
88-  AI-credential-gated (a mock/integration path verifies the pipeline). iOS parity: #56/#100.
89-
90-- [ ] **E. Reader display settings** — the Aa sheet: theme (the 5 reader themes), font family/size,
     1	// Purpose: feature #134 WI-3 — the reader More-menu ROW model (`vreader-more.jsx` `MorePopover` rows),
     2	// rendered by [MorePopup]. A `sealed interface` so each row carries a stable [MoreActionId] + its own
     3	// callback + (for toggles) its own on/onToggle state. The row's OWNER supplies it: #134 owns only
     4	// DETAILS + SHARE (Action rows); TTS/AUTO_TURN/BILINGUAL ids exist so their owning features (#121/#131/
     5	// a future Auto-turn feature) can supply rows, but a row is NEVER invented here — an id with no supplied
     6	// row is simply absent from the popup (the plan's §more-row-ownership contract; the #129 no-dead-control
     7	// rule). Pure model: an ImageVector icon ref + strings + lambdas, no Compose UI in the type itself.
     8	package com.vreader.app.reader.more
     9	
    10	import androidx.compose.ui.graphics.vector.ImageVector
    11	
    12	/**
    13	 * A stable identifier for a More-menu row. Used for the row's testTag (`more-row-$id`) and to key row
    14	 * ownership. #134 owns [DETAILS] + [SHARE]; the others exist so their owning features can supply rows —
    15	 * #134 supplies none of them and omits any id it is not given a row for. There is deliberately NO
    16	 * `EXPORT` id: Android has no annotation-export subsystem, so the Export row is never rendered (the
    17	 * plan's scoped-out invariant), and absence-by-omission is enforced by there being no id to supply.
    18	 */
    19	enum class MoreActionId {
    20	    DETAILS,
    21	    SHARE,
    22	    TTS,
    23	    AUTO_TURN,
    24	    BILINGUAL,
    25	}
    26	
    27	/** The lowercase stable slug for this id — the testTag / route suffix (e.g. `AUTO_TURN` → `auto_turn`). */
    28	val MoreActionId.slug: String
    29	    get() = name.lowercase()
    30	
    31	/**
    32	 * A single More-menu row. Exactly one of three shapes, mirroring the design's three row treatments:
    33	 *  - [Action]   — a tap row with a trailing chevron (`vreader-more.jsx` `onAction`).
    34	 *  - [Toggle]   — a stateful row with a trailing switch reflecting [Toggle.on] (`onToggle`).
    35	 *  - [Disabled] — the design's disabled state (e.g. Bilingual "Configure AI provider first"):
    36	 *                 non-interactive, dimmed, shows its [Disabled.sub].
    37	 *
    38	 * Every row carries a stable [id] (its testTag key) and its own callback. The OWNER of a row's behavior
    39	 * is the feature that supplies it — never [MorePopup] itself.
    40	 */
    41	sealed interface MoreRow {
    42	    val id: MoreActionId
    43	    val label: String
    44	    val icon: ImageVector
    45	
    46	    /** A tap row: fires [onTap]; renders a trailing chevron accessory. */
    47	    data class Action(
    48	        override val id: MoreActionId,
    49	        override val label: String,
    50	        override val icon: ImageVector,
    51	        val sub: String? = null,
    52	        val onTap: () -> Unit,
    53	    ) : MoreRow
    54	
    55	    /** A toggle row: the trailing switch reflects [on]; tapping the row calls [onToggle] with `!on`. */
    56	    data class Toggle(
    57	        override val id: MoreActionId,
    58	        override val label: String,
    59	        override val icon: ImageVector,
    60	        val sub: String? = null,
    61	        val on: Boolean,
    62	        val onToggle: (Boolean) -> Unit,
    63	    ) : MoreRow
    64	
    65	    /** A disabled row: non-interactive, dimmed, shows [sub] (the design's "Configure AI provider first"). */
    66	    data class Disabled(
    67	        override val id: MoreActionId,
    68	        override val label: String,
    69	        override val icon: ImageVector,
    70	        val sub: String,
    71	        val onTap: () -> Unit,
    72	    ) : MoreRow
    73	}
   225	        ReaderSheet.Details -> if (bookDetails != null) BookDetailsSheet(
   226	            theme = theme,
   227	            model = bookDetails,
   228	            onCopyFingerprint = onCopyFingerprint,
   229	            onShare = onShareBook,
   230	            onDismiss = { openSheet(ReaderSheet.None) },
   231	        )
   232	        // feature #135 WI-6 — the Bookmarks route opens the SAME two-tab sheet with the Bookmarks tab
   233	        // pre-selected (the designed [TocBookmarksSheet]; rule 51 — no invented list surface).
   234	        ReaderSheet.Bookmarks -> TocBookmarksSheet(
   235	            theme = theme,
   236	            bookTitle = title,
   237	            entries = tocEntries,
   238	            currentTocIndex = currentTocIndex,
   239	            bookmarks = bookmarks,
   240	            onJumpToc = onJumpToc,
   241	            onJumpBookmark = onJumpBookmark,
   242	            onDismiss = { openSheet(ReaderSheet.None) },
   243	            initialTab = TocTab.Bookmarks,
   244	        )
   245	    }
   246	}
   247	
   248	/**
   249	 * feature #134 WI-5 — the reader More-menu rows the scaffold + the EPUB chrome feed to the WI-3
   250	 * [MorePopup]. #134 owns ONLY the Details + Share rows (the design's `vreader-more.jsx` `Book details` /
   251	 * `Share book` actions); TTS / Auto-turn / Bilingual / Export are OTHER features' rows and are never
   252	 * invented here (the §more-row-ownership contract + the #129 no-dead-control rule — the popup renders only
   253	 * the rows it is given). Pure function of its two callbacks (no Compose runtime beyond the icon refs).
   254	 */
   255	internal fun readerMoreRows(onDetails: () -> Unit, onShare: () -> Unit): List<MoreRow> = listOf(
   256	    MoreRow.Action(id = MoreActionId.DETAILS, label = "Book details", icon = Icons.Filled.Info, onTap = onDetails),
   257	    MoreRow.Action(id = MoreActionId.SHARE, label = "Share book", icon = Icons.Filled.Share, onTap = onShare),
   258	)

codex
The central parity check found a substantive gap: the plan invokes iOS’s `translatePreSegmented` divergence recovery, but no Android work item actually builds the corresponding service, cache-only restore, or prefetch API. I’m doing a final cross-check of work-item edges and acceptance criteria before issuing the severity-counted verdict.
exec
/bin/zsh -lc "nl -ba dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md | sed -n '28,90p'
nl -ba dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md | sed -n '148,217p'
nl -ba android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt | sed -n '1,45p'
nl -ba android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt | sed -n '100,120p'
nl -ba android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt | sed -n '25,85p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
    28	
    29	**Why both, not TXT/MD-only:** the honest thesis is that the *pipeline* (segment → chunk → translate → cache → interleave) is host-agnostic and fully built in v1; only the *render injection* is host-specific. EPUB is the format most users read, so shipping box D without it would under-deliver on the visible capability. TXT/MD are included because the Compose host is the cheapest, most testable place to prove the pipeline end-to-end (no WebView, deterministic tree assertions) — it de-risks the EPUB render adapter. This is not the box-B/E "one host and check the box" split; box D ships EPUB + TXT/MD together, with AZW3/PDF as tracked follow-ups. **Box D cannot be checked on the false "EPUB requires a fork" rationale** — that rationale is discarded.
    30	
    31	### New files
    32	
    33	**Pipeline / domain (host-agnostic, pure or coroutine — JVM-testable):**
    34	
    35	- `bilingual/TranslationUnitId.kt` — `data class TranslationUnitId(kind, value)` with `enum Kind { epubHref, foliateHref, txtChapterIndex, mdChapterIndex, pdfPageRange }`; `storageKey = "${kind.name}:$value"`. Mirrors iOS `TranslationUnitID.Kind` (verified: same five cases). v1 uses `epubHref` + `txtChapterIndex`/`mdChapterIndex`; others reserved so the cache-key format never breaks.
    36	- `bilingual/TranslationGranularity.kt` — `enum { paragraph, sentence }`. (Design's Granularity segment.)
    37	- `bilingual/BilingualLanguages.kt` — `BilingualLanguage(key, glyph, script)`; `BILINGUAL_LANGS` = the set from `vreader-bilingual.jsx` (`BILINGUAL_LANGS`) + `findOrDefault(key)`. Default `Chinese`.
    38	- `bilingual/ChapterSegmenter.kt` — `paragraphs(text)` / `sentences(text)`. Port of iOS `ChapterSegmenter.paragraphs(in:)`/`sentences(in:)` (verified exists, CJK-aware via sentence enumeration).
    39	- `bilingual/TranslationChunker.kt` — `chunk(segments, maxCharsPerChunk)` + `subSplit(text, maxChars)`. Port of iOS `ChapterTranslationChunker.chunk(...)` + `subSplit(...)` (verified: `chunk` returns `[[Int]]` index groups, oversize segment gets its own chunk; `subSplit` is the Bug #330 grapheme-safe over-budget splitter).
    40	- `bilingual/TranslationChunkContract.kt` — `userPrompt(segments, targetLanguage, style)`; `decode(raw, expectedCount)` (strict JSON-array + code-fence strip); `sealed class DecodeError { NotAStringArray; CountMismatch(expected, actual) }`. Port of iOS `TranslationChunkContract` (verified: same `userPrompt`/`decode` shape, same two DecodeError cases).
    41	- `bilingual/ChapterTextProvider.kt` — `interface { units(); sourceText(unit); unitContaining(locator); unitAfter(unit) }`. Resolution key is host-specific: TXT/MD key on `charOffsetUtf16` (Android `Locator` is offset-based there); EPUB keys on the current-resource `href` from `EpubNavigatorFragment.currentLocator`. Honest divergence from iOS's uniform Readium `Locator`, documented.
    42	- `bilingual/TxtChapterTextProvider.kt` — provider over `TxtDocument` + chapter model. MD source = raw markdown chapter (translation renders as plain muted text, not re-markdown-rendered — matches the muted-secondary design line).
    43	- `bilingual/EpubChapterTextProvider.kt` (WI-0-gated shape) — provider over the Readium `Publication` reading order; `units()` = spine hrefs, `unitContaining(locator)` = the locator's href. Its render-side collaborator (the JS enumerate/inject adapter) is defined by WI-0's findings, not pre-committed here.
    44	- `bilingual/ChapterTranslationError.kt` — `sealed { Offline; TimedOut; ProviderFailed(msg); Cancelled }`. Maps from `AiError` (verified cases: `Auth401`, `RateLimited429`, `Offline`, `Timeout`, `Http(code)`, `Decode`, `Stream`, `InsecureUrl`, `Config`).
    45	- `bilingual/ChapterTranslationService.kt` — `cachedTranslation(...)` (cache-only, no provider — #306 parity: a cached chapter renders even when AI is later unconfigured); `translate(...)` (segment → chunk → per-chunk `AiClient.chat` one-shot → `decode` → per-segment fallback → graceful per-chunk degrade (Bug #330 parity: a single failed chunk renders source-only and is NOT cached; all-chunks-fail throws) → cache-write only on full success). Uses `AiClient.chat(AiRequest)` (one-shot, NOT `streamChat`). Cancellation: `ensureActive()` between chunks AND immediately before the Room write (§6).
    46	- `bilingual/ChapterTranslationPrefetcher.kt` — resolves the active profile from one `AiProviderStore.snapshot()` (`snapshot.active`), decrypts via `store.apiKey(profile)` (snapshot-consistent), builds an `AiClient` via an **injected factory param** (see the DI correction below), cache-first then translate. Throws `ChapterTranslationError`. Mirrors iOS `ChapterTranslationPrefetcher` (verified: iOS snapshots the active profile after a cache miss and is a Sendable struct capturing its collaborators).
    47	- `bilingual/BilingualAiReadiness.kt` — `resolve(snapshot): Boolean` (active profile exists AND its decrypted key is non-empty). A cipher/decryption failure maps to **not-ready** (never crashes — §6), not to a thrown error. Drives the setup-sheet engine-strip configured/unconfigured state. Keep the gate to exactly what #118 enforces (no separate consent manager on Android — #118 has none; confirm during build).
    48	
    49	**State / persistence:**
    50	
    51	- `bilingual/PerBookBilingualStore.kt` — DataStore-Preferences, keyed by `bookFingerprintKey`, holding `{ enabled, targetLanguage, granularity }`. This is the Android `PerBookSettingsOverride` bilingual slice — the backup contract declares exactly `bilingualEnabled` / `bilingualTargetLanguage` / `bilingualGranularity` (verified in `PerBookSettings.swift` and the Android `BackupSectionsExtended.kt`), and **NO `bilingualStyle`** (verified — style is not a persisted per-book field on iOS either). So this store writes exactly those three fields. Wiring into backup collect/restore is scoped OUT (§7) — additive later, fields already in the contract; until then bilingual config is device-local.
    52	- `bilingual/BilingualViewModel.kt` — `StateFlow<BilingualUiState>` with `enabled`, `targetLanguage`, `granularity`, `needsSetupSheet`, `aiConfigured`, `translationsByUnit`, `inFlightUnits`, `unavailableUnits`, `errorUnit`. Setters + `dismissSetupSheet`, `onPositionChanged(locator)`, `retryUnit(unit)`. Generation/epoch-guarded prefetch (current + next unit), cancellation on disable / language / granularity change — port of iOS `BilingualReadingViewModel` + `+Prefetch` (verified both exist). Split to `BilingualPrefetchController.kt` if it nears ~300 lines. (No `style` field — the authoritative sheet has no Style control; see §3.)
    53	
    54	**Room (translation cache):**
    55	
    56	- `data/ChapterTranslationEntity.kt` — `@Entity(tableName="chapter_translations", indices=[Index("bookKey")], foreignKeys=[FK→books.fingerprintKey ON DELETE CASCADE])`. **`@PrimaryKey val lookupKey: String`** (Room REQUIRES a primary key; a "unique index without a PK" does not compile — verified against `HighlightEntity`, which pairs a `@PrimaryKey` with a separate unique index). `lookupKey` = `bookKey|unitStorageKey|targetLanguage|promptVersion` (see the cache-identity correction below). Other columns: `bookKey`, `unitStorageKey`, `targetLanguage`, `promptVersion`, `translatedJson`, `sourceParagraphCount`, `createdAt`. Mirrors iOS `ChapterTranslationRecord.lookupKey` (verified: iOS key is `book|unit|lang|prompt`, profile-agnostic — Bug #342).
    57	- `data/ChapterTranslationDao.kt` — `getByLookupKey(key)`, `@Upsert suspend fun upsert(row)` (Upsert identifies by PK = `lookupKey`, so it is a correct insert-or-replace by the cache identity), `deleteByLookupKey(key)`. The project's Room pattern is `@PrimaryKey` + `@Upsert` (verified: `BookDao.upsert`); making `lookupKey` the PK is exactly that pattern.
    58	- `bilingual/ChapterTranslationStore.kt` — coroutine wrapper returning a Sendable `CachedTranslation` (segments decoded from JSON), keeping Room entities off the boundary (the `AnnotationsRepository`/`HighlightRecord`/iOS `ChapterTranslationStore` precedent).
    59	
    60	**Cache-identity correction (audit HIGH — reconciled with iOS parity):** the audit asked to add granularity + style as key columns. iOS deliberately does the opposite — `ChapterTranslationRecord.lookupKey` is `book|unit|lang|promptVersion` and is profile-AGNOSTIC / granularity-AGNOSTIC / style-agnostic (Bug #342's fix was to *remove* dimensions from the key). Style is folded into the prompt content; granularity is a read-time count-check. **Resolution honoring both the audit's concern and iOS parity:** keep the 4-part key, but make `promptVersion` an **effective composite** that encodes the result-shaping inputs, e.g. `promptVersion = "bilingual-v1|g=${granularity}|s=${style}"` (iOS uses the literal `"bilingual-v1"` today because iOS forces `.paragraph` for bilingual and pins one style; Android carries granularity/style in the promptVersion string so a change re-keys correctly). Style is not a v1 user control (the authoritative sheet has none — §3), so `s=` is a constant this version; granularity IS user-selectable, so `g=` is load-bearing (a paragraph vs sentence translation is a different cache row — this also closes the iOS #344 "sentence silently ignored" class by construction). **Additionally** (audit's cancellation half): a granularity change must cancel in-flight jobs, bump the VM generation, clear shaped in-memory `translationsByUnit`, and force a correctly-keyed re-fetch — specified in WI-6.
    61	
    62	**DI / factory correction (audit HIGH):** the audit is right that `AiProviderFactory` is NOT a lambda — verified it is an `object` with `create(profile: AiProviderProfile, apiKey: String, dispatcher: CoroutineDispatcher = Dispatchers.IO): AiClient`. So `ChapterTranslationPrefetcher` takes its OWN injected `clientFactory: (AiProviderProfile, String) -> AiClient` param **defaulting to `AiProviderFactory::create`** (production) and overridden with a fake in tests. The prefetcher builds the exact `AiRequest(model = profile.model, messages = …, temperature = profile.temperature, maxTokens = profile.maxTokens, system = …)` from the resolved profile (verified `AiRequest` fields).
    63	
    64	**AppContainer / navigation correction (audit HIGH — genuine gap, NOT stale state):** verified against the real code — `AppContainer` does **NOT** provide `AiProviderStore` today, and there is **NO live navigation route to `AiProviderListScreen`** (MainActivity has no NavHost; the screen + store + `AiSettingsViewModel` exist from #118 but are only exercised by instrumented/round-trip tests — #118 was VERIFIED via component tests + a live SSE socket round-trip, not an in-app nav route). There is no `#119` row. Consequences for #131:
    65	- #131 **adds `AiProviderStore` to `AppContainer`** (lazy singleton: DataStore + `KeystoreSecretCipher`, the #116/#118 pattern) — the prefetcher + readiness need it and nothing provides it yet.
    66	- The setup-sheet unconfigured engine strip's **"Set up" CTA target does not exist in the running app.** #131 does NOT invent an AI-provider settings screen or its navigation (that is box-F chrome / a #118 follow-on, and inventing it violates rule 51). Until a live route to `AiProviderListScreen` ships, the "Set up" affordance is **design-gated** — see §3's design-gate list. #131 can ship the bilingual sheet's *configured* path (a provider already set via the tested path) end-to-end; the *unconfigured → Set up* nav is a stated dependency, not #131 scope.
    67	
    68	**UI (Compose — every state depicted, reproducing `vreader-bilingual.jsx`):**
    69	
    70	- `bilingual/BilingualSetupSheet.kt` — reproduces `vreader-bilingual.jsx`'s `BilingualSetupSheet` EXACTLY: header Cancel / Translate; a **preview strip**; a **language grid** over `BILINGUAL_LANGS` (glyph tiles, selected accent); a **Granularity** segmented control (Paragraph "Translate after each ¶" / Sentence "Translate after each sentence"); a **Translation engine** strip (configured: "Claude · with this book's context" + "Change…"; unconfigured: "No AI provider configured" + "Set up"). **No Style control, no provider/model card, no term-overrides toggle, no cost footer** — those belong to the *other* (`vreader-ai-android.jsx`) sheet, which this plan does not reproduce (§3).
    71	- `bilingual/BilingualInterlinearBody.kt` — per source chunk/paragraph: source `Text` then translation `Text` muted with accent left-border, `fontSize*0.88`, CJK font for cjk scripts, RTL handling for Arabic script. Consumes `translationsByUnit`. Loading state ("Translating chapter… N%" + per-paragraph dim — matches the design's chapter-level "38%"). Error state ("Couldn't translate" + Retry). Partial/offline (`unavailableUnits`): source-only silent fallback (design's original-always-kept guarantee — iOS Decision 2). This is the render surface for BOTH the TXT/MD Compose loop and (via the WI-0 adapter) the EPUB injection payload's Kotlin-side state.
    72	- `bilingual/BilingualPill.kt` — the `EN ↔ 中` reader-**top-chrome** pill (per `vreader-reader.jsx` `ReaderTopChrome` + `vreader-bilingual.jsx` `BilingualPill`). Rendered by box F's top chrome; #131 provides the composable, box F wires it in (§4).
    73	
    74	### Modified files
    75	
    76	- `data/VReaderDatabase.kt` — add `ChapterTranslationEntity`, bump `version` (allocated version-at-slot; **v5 today** — verified, so v5→v6, but the number is set at the merge slot, not pre-assigned), add `MIGRATION_5_6` (CREATE TABLE + `bookKey` index + FK CASCADE, DDL exactly matching Room's generated schema), append `ALL_MIGRATIONS`, add `abstract fun chapterTranslationDao()`.
    77	- `reader/TxtReaderActivity.kt` — own a `BilingualViewModel`; collect state; pass into `TxtBody`; on position change call `vm.onPositionChanged(...)`; render `BilingualInterlinearBody` output in the `items(count = document.chunkCount)` loop when bilingual is on and a translation exists (the confirmed injection point — verified it already interleaves highlight washes + TTS spans per chunk). Strictly gated to `originalFormat ∈ {txt, md}`; disabled = body byte-unchanged. **This file overlaps #129's TXT/MD WIs → gated on #129's FINAL merge (§4).**
    78	- `reader/ReaderActivity.kt` (Readium EPUB) — WI-0-gated: attach the JS enumerate/inject adapter to `navigator.evaluateJavascript`, re-apply on href change / reflow, clear on teardown. Concrete surface defined by WI-0's spike output.
    79	- `VReaderApp.kt` / `AppContainer` — **provide `AiProviderStore`** (new — see the AppContainer correction), `ChapterTranslationStore`, `PerBookBilingualStore`, and a `BilingualViewModel` factory. Mirrors #116/#118/#122 DI.
    80	
    81	**NOT modified (audit HIGH — Translate slot removed):** `reader/chrome/ReaderBottomChrome.kt` gets **no** bilingual/Translate slot. v1 wrongly added `onOpenBilingual` there; the design's entry is the More-menu toggle + the top-chrome pill (box F), NOT a bottom-chrome slot. `ReaderBottomChrome`'s existing `extraSlot` (the #129/#121 read-aloud entry) is untouched.
    82	
    83	### Files OUT of scope for v1
    84	
    85	- **`Azw3ReaderActivity.kt` / `reader/foliate/`** — foliate WebView interlinear IS feasible (JS enumerate+inject in the pinned bundle, mirroring iOS `FoliateBilingualOrchestrator`) but deferred to a follow-up (bundle-patch JS + secure-bridge additions touching the security-sensitive #126 surface). Once WI-0 proves the EPUB JS pipeline, the foliate host reuses it with a bundle adapter.
    86	- **`PdfReaderActivity.kt`** — no reflowable text layer. Out (the `pdfPageRange` Kind is reserved only).
    87	- **Live AI-provider settings navigation / the "Set up" destination screen** — box-F chrome / #118 follow-on; #131 does not invent it (rule 51). Design-gated dependency (§3).
    88	- **Backup collect/restore of `PerBookSettingsOverride` bilingual fields** — contract fields exist; wiring is a small additive follow-up (§7). Bilingual config is device-local until then.
    89	- **"Translate entire book…" batch, re-translate/style-swap picker, cost/token estimation, term-overrides** — iOS/`vreader-ai-android.jsx` extras not in the authoritative `vreader-bilingual.jsx` sheet. Out.
    90	- **Streaming translation progress** — the design's "38%" is chapter-level N-of-M chunk progress (from the chunker count), not token streaming. v1 shows N-of-M.
   148	## 4. Work-item sequencing
   149	
   150	Foundational WI-1..4 (no UI, JVM-testable); a spike WI-0 (EPUB); behavioral WI-5..9. Each WI = one PR.
   151	
   152	**Dependency notes (audit HIGH — v1's graph was wrong):**
   153	- WI-3 depends on WI-1 (+2). WI-4 depends on WI-1+WI-3. WI-6 depends on WI-5. So WI-1..4 are NOT all independent — the graph below states the real edges.
   154	- **`Deps: [feat:#134, feat:#132]`** (transitively #129, #118) — box F is not yet decomposed (per `docs/parity/android-checklist.md`, box F "likely splits into ≥2 features: TOC/bookmarks; find-in-book; more-menu/details/share"); **#132 = the top-chrome sub-feature, #134 = the More-menu sub-feature** are the prospective box-F IDs this plan reserves. **#131's UI entry-point WIs (the pill mount + the More-menu toggle wiring) cannot ship until box F provides those surfaces.** The pipeline + setup sheet + interlinear render (WI-0..7) are built ahead; only the entry wiring (part of WI-9) waits on box F.
   155	- **Host-integration WIs are gated on #129's FINAL merge** — #129 owns `TxtReaderActivity`/`ReaderBottomChrome`; #131's `TxtReaderActivity` edit must land on top of #129's TXT/MD typography WIs (rule 48 one-writer-per-file).
   156	
   157	**WI-0 (spike): Readium EPUB bilingual injection.** The harness in §3 (enumerate / inject+clear / re-apply on reflow / pagination + count-divergence measurement). Output: a go/no-go on EPUB-in-v1 + the concrete `EpubChapterTextProvider` + injection-adapter surface. Deps: none (uses the existing #106 Readium host). Not TDD-gated (throwaway spike); its findings feed WI-7b's plan.
   158	
   159	**WI-1 (foundational): value types + pure segmentation/chunk/contract.** `TranslationUnitId`, `TranslationGranularity`, `BilingualLanguages`, `ChapterSegmenter`, `TranslationChunker`, `TranslationChunkContract`, `ChapterTranslationError`. Pure; ported iOS vectors. No Android deps. Deps: none.
   160	
   161	**WI-2 (foundational): Room translation cache.** `ChapterTranslationEntity` (PK = `lookupKey`) + `Dao` (`@Upsert`) + `ChapterTranslationStore`; `VReaderDatabase` migration (number at slot). Robolectric migration round-trip + upsert/get/delete-by-lookupKey + FK-CASCADE + exact-DDL guard. Deps: none.
   162	
   163	**WI-3 (foundational): `ChapterTranslationService`** against a fake `AiClient`. `cachedTranslation` (cache-only) + `translate` (per-chunk `chat`, per-segment decode-fail fallback, per-chunk graceful degrade, cancellation between chunks + before write, cache-write only on full success). Deps: **WI-1, WI-2**. Tests: cache hit → zero client calls; miss → translate + write; decode fail → per-segment fallback; one-chunk fail → source-only that chunk (others translated, NOT cached); all-chunks fail → throw; cancellation → `Cancelled` (no write); `AiError` mapping incl. `Config`/`InsecureUrl` → `ProviderFailed`.
   164	
   165	**WI-4 (foundational): `ChapterTextProvider` (TXT/MD) + `ChapterTranslationPrefetcher` + `BilingualAiReadiness`.** Provider slices per chapter from `TxtDocument`; `unitContaining`/`unitAfter`. Prefetcher resolves active profile from `snapshot()`, decrypts snapshot-consistent, builds client via the **injected factory param** (default `AiProviderFactory::create`), constructs `AiRequest` from the profile, cache-first then translate. Readiness = active profile with non-empty decrypted key; **cipher failure → not-ready, never a crash.** Fake store + fake factory. Deps: **WI-1, WI-3**. Tests: unit resolution + clamp + empty; cache-hit-no-profile still returns (#306); no-profile miss → `ProviderFailed`; readiness true/false; cipher-throw → readiness false (no crash).
   166	
   167	**WI-5 (behavioral): `PerBookBilingualStore` + `BilingualViewModel` state core.** Store per book (enabled/targetLanguage/granularity — no style); VM setters (persist + first-enable `needsSetupSheet`), language/granularity change clears cache-shaped state + bumps generation, the state fields. Turbine tests: first-enable raises sheet; re-enable persisted does not; disable clears; language change resets; granularity change resets + re-keys; round-trip through store. Deps: **WI-1** (+ store).
   168	
   169	**WI-6 (behavioral): VM prefetch trigger + generation/cancellation.** `onPositionChanged` derives current unit, dedupes, prefetches current+next; a **monotonic position-request sequence** checked after every suspension; **per-unit generation tokens**; a **captured language/granularity/provider snapshot per launch**; generation bumps on disable/language/granularity/unit-change discard stale; `CancellationException` handled BEFORE generic error mapping; `Offline`→`unavailableUnits`; transient failure leaves unit unfetched + clears anchor to retry; `retryUnit`. Fake prefetcher. Deps: **WI-4, WI-5**. Tests: current+next on unit change; same-unit no-op; cancel-mid discards stale; offline→unavailable; failure→retry-able; `retryUnit` re-fetches; granularity change cancels + re-fetches under the new key.
   170	
   171	**WI-7a (behavioral): Compose UI — setup sheet + interlinear body + pill.** Reproduce `vreader-bilingual.jsx` (setup sheet: language grid / granularity / preview / engine strip configured+unconfigured; body: translated / loading N%+dimmed / error+Retry / offline source-only; pill). Light+dark. Compose UI tests each state. Deps: **WI-5** (state shape). NO Style control; the unconfigured "Set up" CTA renders but its nav target is design-gated (§3).
   172	
   173	**WI-7b (behavioral): EPUB render adapter** (only if WI-0 = go). The JS enumerate/inject adapter + `EpubChapterTextProvider`, wired into `ReaderActivity`, driving `BilingualInterlinearBody` state from injected content. Deps: **WI-0, WI-3, WI-4, WI-7a**. Connected test on a real EPUB (seeded cache): enable → interlinear injects; disable → nodes cleared; reflow/href-change re-applies. (If WI-0 = no-go, this WI is dropped and box D ships TXT/MD-only, tracked.)
   174	
   175	**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into `TxtBody` loop + position-change + setup-sheet + DI (incl. adding `AiProviderStore` to `AppContainer`). `originalFormat`-gated (TXT/MD). **Gated on #129's final merge.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; disable → source-only byte-parity; reopen persists enabled + renders from cache with zero client calls. Deps: **WI-6, WI-7a, #129 final**.
   176	
   177	**WI-9 (behavioral): entry wiring + acceptance.** Mount `BilingualPill` in box F's top chrome; wire the More-menu bilingual toggle (box F) to the VM. **Gated on `feat:#132` (top chrome) + `feat:#134` (More menu).** Full acceptance pass across EPUB (if WI-7b landed) + TXT/MD. Flip box D note; update `docs/architecture.md` (bilingual pipeline + the new `chapter_translations` schema + `AiProviderStore` now in `AppContainer`). → DONE. Deps: **WI-8, WI-7b (if go), feat:#132, feat:#134**.
   178	
   179	## 5. Test catalogue
   180	
   181	JVM/Robolectric (`android/app/src/test/...bilingual/`): `ChapterSegmenterTest` (paragraph blank-line; sentence CJK 。！？ vs Latin; empty→[]; single); `TranslationChunkerTest` (packs to budget; oversize→own chunk+subSplit; empty→[]); `TranslationChunkContractTest` (prompt per style-constant; strict JSON decode; code-fence strip; count mismatch→`CountMismatch`; non-array→`NotAStringArray`); `ChapterTranslationServiceTest` (cache hit 0 calls; miss→translate→write; decode-fail per-segment fallback; one-chunk-fail partial-not-cached; all-fail→throw; cancellation→Cancelled no write; ensureActive-before-write; offline/timeout/429/http/config/insecure→error mapping; very long chapter N-of-M; stale-cache count-mismatch re-translates); `ChapterTranslationErrorMappingTest`; `TxtChapterTextProviderTest` (resolution; clamp-past-end; empty; unitAfter end→null); `ChapterTranslationPrefetcherTest` (snapshot-consistent profile+key; injected-factory used; `AiRequest` built from profile; cache-hit-no-profile #306; no-profile miss→ProviderFailed; CJK↔English + Latin round-trip via fake; cipher-throw→ProviderFailed not crash); `BilingualAiReadinessTest` (active+key→true; no active→false; empty key→false; **cipher-throw→false, no crash**); `PerBookBilingualStoreTest` (enabled/lang/granularity round-trip; no style field); `BilingualViewModelTest` (Turbine: first-enable sheet; re-enable no-sheet; disable clears; language reset; **granularity reset + re-key**; prefetch current+next; same-unit no-op; cancel-mid discards; offline→unavailable; error→errorUnit+retry; `retryUnit`; generation bump on style-N/A—granularity change).
   182	
   183	Room migration: `VReaderDatabaseMigrationTest` (extend) vPrev→vNext + full-chain + FK-CASCADE + `lookupKey`-as-PK; `ChapterTranslationDaoTest` (upsert-by-PK replaces; get/delete-by-lookupKey).
   184	
   185	Compose UI (`androidTest/...bilingual/`): `BilingualSetupSheetUiTest` (language grid, granularity, preview, engine configured vs unconfigured; **no Style control present**; light+dark); `BilingualInterlinearBodyUiTest` (translated incl. CJK font + RTL Arabic; loading N%+dimmed; error+Retry; offline source-only; empty translation→source-only no crash); `BilingualPillUiTest`.
   186	
   187	Connected (`androidTest/...reader/`): `TxtReaderBilingualConnectedTest` (API 35, fake `AiClient` via injected factory): enable→setup→confirm→interlinear from seeded Room cache; disable→source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; TXT/MD gated (PDF inert); very long chapter scroll responsive; cancellation leaves no partial cache row. `EpubReaderBilingualConnectedTest` (only if WI-0=go): enable→inject on a real EPUB; disable→clear; href-change→re-apply; count-divergence handled.
   188	
   189	Edge cases: empty translation, failed, partial per-chunk, CJK↔English + Latin + RTL, provider error/timeout/429/config/insecure, cancellation mid-translation + before-write, very long chapters, offline (cache-first + silent source-only), cipher-decrypt failure → not-ready (no crash).
   190	
   191	## 6. Risks + mitigations
   192	
   193	- **Live-translation verification is AI-credential-gated (the box-D caveat).** The whole pipeline is verified without live creds via a deterministic **fake `AiClient`** injected through the prefetcher's `clientFactory` param (default `AiProviderFactory::create`; tests override). WI-3/4/8 prove segment→chunk→decode→cache→interleave end-to-end incl. every error/edge path. The connected test seeds the Room cache directly and asserts render-from-cache with zero client calls (render path proven offline). **This mock/integration path is the box-D-required verification path** (the checklist states live translation is credential-gated); an optional live smoke confirms wire format but is NOT a gate.
   194	- **Acceptance proves BOTH cache-render AND the live pipeline path (via the fake).** WI-8's connected test drives the full enable→translate(fake)→cache→render→reopen cycle, not just cache rendering — the fake stands in only for the network leaf.
   195	- **EPUB JS-injection unknowns.** WI-0 de-risks before the render WI: pagination shift, fragment recreation wiping nodes, enumerate-vs-`ChapterSegmenter` count divergence (iOS #268). If a hard blocker appears, EPUB drops to a tracked follow-up (phasing fallback) with the specific spike reason — never the false "requires a fork."
   196	- **Concurrency (audit HIGH — was under-specified).** WI-6 adds: a monotonic position-request sequence checked after every suspension; per-unit generation tokens; a captured language/granularity/provider snapshot per launch; cancellation on granularity change; `CancellationException` handled BEFORE generic error mapping; `ensureActive()` immediately before the Room write; cipher/decrypt failures mapped to unconfigured/provider-failure (never a crash). Snapshot-consistent profile+key pairing (from one `snapshot()`) is preserved.
   197	- **Segment↔render count divergence** (iOS Bugs #268/#330/#344). TXT/MD segment through the SAME `ChapterSegmenter` on translate + render sides, so 1:1 pairing holds by construction; granularity is in the cache key so a paragraph row is never read as sentences. EPUB uses WI-0's finding (direct-block path if enumerate diverges — iOS `translatePreSegmented` parity).
   198	- **Cost/latency of translating on scroll.** Lazy current+next prefetch + disk cache; N-of-M progress; cancellation on navigate-away/generation-bump.
   199	- **Provider JSON non-compliance.** `TranslationChunkContract.decode` + per-segment fallback (iOS parity) — never drops a paragraph.
   200	- **DataStore per-book key growth.** One Preferences entry per book keyed by fingerprint; scales like `ReaderSettingsStore`/`AiProviderStore`.
   201	
   202	## 7. Backward compat
   203	
   204	- **Room migration additive** (new `chapter_translations`, FK CASCADE, `lookupKey` PK). Existing rows untouched; migration + structural test guard it. Version number allocated at the merge slot (v5 today → v6).
   205	- **Reader unchanged when bilingual off** — `TxtBody` render loop byte-identical unless `enabled && format∈{txt,md} && translation present`. `ReaderBottomChrome` is **not modified** (v1's Translate slot removed), so #129's chrome is unaffected. EPUB render adapter is inert unless bilingual is on.
   206	- **#118 AI provider files unchanged** — the prefetcher/readiness are new consumers; the only #118-adjacent change is *wiring* `AiProviderStore` into `AppContainer` (which #118 left unwired — it was component/round-trip-verified, not nav-integrated).
   207	- **Backup contract already compatible** — `PerBookSettingsOverride.bilingualEnabled/TargetLanguage/Granularity` exist (verified; **no `bilingualStyle`**), and there is **no translation-cache section** in `contracts/vectors/backup-sections.json` (verified — the cache is device-local, re-derivable). v1 introduces the store that writes the three fields locally; backup collect/restore of them is a small additive follow-up (no contract change), out of v1 scope; until then bilingual config is device-local (safe default). The `PerBookBilingualStore` is confirmed device-local; backup-collect/restore is the scoped-out follow-up.
   208	
   209	## Design gates (rule 51 — for `needs-design` filing)
   210	
   211	1. **"Bilingual mode" setup sheet with BOTH Style AND Granularity in one Android sheet** — `vreader-bilingual.jsx` depicts Granularity (no Style); `vreader-ai-android.jsx` depicts Style (no Granularity); no committed bundle shows both together. v1 reproduces the granularity-only `vreader-bilingual.jsx` sheet and DROPS Style. If Style is wanted as an Android user control, file `Design needed: bilingual setup sheet (Style + Granularity) for feature #131`. **This is the one open design gate for #131.**
   212	2. **Dependency gate (not a #131 design gate, but blocks the "Set up" affordance)** — the setup sheet's unconfigured "Set up" CTA has no live nav destination (`AiProviderListScreen` is unreachable in-app today; no `#119`). #131 does not invent it (box-F chrome / #118 follow-on); the CTA renders but is wired only once that route ships.
   213	
   214	## Revision history
   215	
   216	- v1 (2026-07-10): Gate-1 draft (Plan agent). Gate-2 Codex audit pending.
   217	- v2 (2026-07-11): Gate-2 round-1 REDESIGN resolved — Readium-feasibility corrected, entry-point rebased on box F, setup-sheet design-gated, DI/cache/concurrency fixed.
     1	// Purpose: Room database + schema-versioned migration scaffold — feature #106 WI-3.
     2	// Version 8 is the current schema; v1 was the initial books+positions baseline and
     3	// MIGRATION_1_2 is the worked example of the additive-migration pattern (adds
     4	// books.lastOpenedAt). Subsequent additive migrations: 2→3 daily_reading (#122),
     5	// 3→4 annotations (#123), 4→5 collections (#127), 5→6 books.author (#128 search),
     6	// 6→7 the FTS search index (search_sections + search_sections_fts + search_index_state
     7	// + search_sections_staging, all #128 WI-4), 7→8 the composite UNIQUE (bookKey, profileKey)
     8	// index on `bookmarks` — preceded by an in-migration dedupe of pre-existing duplicate rows so
     9	// the unique index can't fail on a legacy duplicate (feature #135 WI-3). The migration round-trip
    10	// test (VReaderDatabaseMigrationTest) guards them. Future schema changes append a
    11	// Migration(n, n+1) to ALL_MIGRATIONS and bump `version`.
    12	package com.vreader.app.data
    13	
    14	import android.content.Context
    15	import androidx.room.Database
    16	import androidx.room.Room
    17	import androidx.room.RoomDatabase
    18	import androidx.room.migration.Migration
    19	import androidx.sqlite.db.SupportSQLiteDatabase
    20	
    21	@Database(
    22	    entities = [
    23	        BookEntity::class, ReadingPositionEntity::class, DailyReadingEntity::class,
    24	        HighlightEntity::class, AnnotationNoteEntity::class, BookmarkEntity::class,
    25	        CollectionEntity::class, BookCollectionCrossRef::class,
    26	        SearchSectionEntity::class, SearchSectionFtsEntity::class,
    27	        SearchIndexStateEntity::class, SearchStagingEntity::class,
    28	    ],
    29	    version = 8,
    30	    exportSchema = true,
    31	)
    32	abstract class VReaderDatabase : RoomDatabase() {
    33	    abstract fun bookDao(): BookDao
    34	    abstract fun readingPositionDao(): ReadingPositionDao
    35	    abstract fun readingStatsDao(): ReadingStatsDao
    36	    abstract fun annotationDao(): AnnotationDao
    37	    abstract fun collectionDao(): CollectionDao
    38	    abstract fun searchDao(): SearchDao
    39	
    40	    companion object {
    41	        private const val DB_NAME = "vreader.db"
    42	
    43	        /** v1 → v2: add the nullable `lastOpenedAt` recents column to `books`. */
    44	        val MIGRATION_1_2: Migration = object : Migration(1, 2) {
    45	            override fun migrate(db: SupportSQLiteDatabase) {
   100	@OptIn(ExperimentalReadiumApi::class)
   101	class ReaderActivity : AppCompatActivity() {
   102	
   103	    private val container get() = (application as VReaderApp).container
   104	    private val repository: LibraryRepository get() = container.repository
   105	    private val bridge = ReadiumLocatorBridge()
   106	
   107	    private val annotations: AnnotationsRepository get() = container.annotationsRepository
   108	
   109	    private var containerId: Int = 0
   110	    private var navigator: EpubNavigatorFragment? = null
   111	    private var publication: Publication? = null   // host-owned; closed in onDestroy
   112	    private var book: Book? = null
   113	
   114	    // feature #132 WI-7-EPUB — the persistent chrome model the top/bottom bands + sheet layer collect,
   115	    // populated as the async open completes and updated on every position change. The active Display
   116	    // theme (also read by the chrome bands' colors) is mirrored so the ComposeViews can render immediately.
   117	    private val chromeModel = MutableStateFlow(ReaderChromeModel())
   118	    private val chromeTheme = mutableStateOf(ReaderTheme.Paper)
   119	    // The hoisted top/bottom-visibility + open-sheet state (a Compose snapshot state, so the ComposeViews
   120	    // recompose on change). Kept in-memory for the reader's lifetime (rotation always starts fresh — see
    25	import kotlinx.coroutines.SupervisorJob
    26	import kotlinx.coroutines.flow.map
    27	import vreader.contracts.BookFormat
    28	import java.io.File
    29	
    30	/** Process-wide singletons, lazily built. */
    31	class AppContainer(context: Context) {
    32	    private val appContext = context.applicationContext
    33	
    34	    val database: VReaderDatabase by lazy { VReaderDatabase.build(appContext) }
    35	    val repository: LibraryRepository by lazy {
    36	        LibraryRepository(database.bookDao(), database.readingPositionDao())
    37	    }
    38	    val importer: BookImporter by lazy {
    39	        BookImporter(File(appContext.filesDir, "books"), repository)
    40	    }
    41	
    42	    // feature #122 — reading-stats. The repository + the time tracker are process-singletons so a
    43	    // reading session survives the (shorter-lived) reader ViewModel / rotation. ONE shared DateClock
    44	    // so the dashboard's "today" and the tracker's bucket dates can't drift apart.
    45	    private val dateClock: SystemDateClock by lazy { SystemDateClock() }
    46	    val statsRepository: ReadingStatsRepository by lazy {
    47	        ReadingStatsRepository(database.readingStatsDao(), repository, dateClock)
    48	    }
    49	    val readingTimeTracker: ReadingTimeTracker by lazy {
    50	        ReadingTimeTracker(statsRepository, SystemElapsedClock(), dateClock)
    51	    }
    52	
    53	    // feature #123 — annotations (EPUB highlights & notes). Process-singleton so the reader VM /
    54	    // rotation share one instance (the statsRepository precedent).
    55	    val annotationsRepository: AnnotationsRepository by lazy {
    56	        AnnotationsRepository(database.annotationDao())
    57	    }
    58	
    59	    // feature #127 — library collections. Process-singleton (the annotationsRepository precedent).
    60	    val collectionRepository: com.vreader.app.data.CollectionRepository by lazy {
    61	        com.vreader.app.data.CollectionRepository(database.collectionDao())
    62	    }
    63	
    64	    // feature #129 — reader display settings. A device-local DataStore (the OpdsSourceStore /
    65	    // AiProviderStore precedent), global (not per-book), process-singleton so a settings change
    66	    // propagates to whatever reader is open. Stored under noBackupFilesDir — display prefs are
    67	    // per-device (NOT in the backup contract), so they must be excluded from Android Auto Backup.
    68	    private val readerSettingsDataStore: androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences> by lazy {
    69	        androidx.datastore.preferences.core.PreferenceDataStoreFactory.create {
    70	            File(appContext.noBackupFilesDir, "reader_settings.preferences_pb")
    71	        }
    72	    }
    73	    val readerSettingsStore: com.vreader.app.reader.settings.ReaderSettingsStore by lazy {
    74	        com.vreader.app.reader.settings.ReaderSettingsStore(readerSettingsDataStore)
    75	    }
    76	
    77	    /** Process-lifetime scope for fire-and-forget writes that must outlive a screen
    78	     *  (e.g. the reader's onStop position flush — it must finish even as the activity
    79	     *  is being torn down). */
    80	    val appScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    81	
    82	    // feature #128 WI-5 — cross-book search index. The coordinator observes the library and
    83	    // streams each indexable book (epub/txt/md) through the WI-3 extractors into WI-4's staging →
    84	    // atomic publish. Eagerly started once from onCreate; pdf/azw3 map to null (never indexable).
    85	    private val bookOpener: BookOpener by lazy { BookOpener(appContext) }

exec
/bin/zsh -lc "nl -ba dev-docs/designs/vreader-fidelity-v1/project/vreader-more.jsx | sed -n '82,105p'
nl -ba dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx | sed -n '118,148p'
nl -ba docs/parity/android-checklist.md | sed -n '82,89p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
    82	             active={s.ttsPlaying}
    83	             on={() => onAction('tts')}/>
    84	
    85	        <Row icon={Icons.Timer} label="Auto-turn pages"
    86	             sub={s.autoTurn ? `Every ${s.autoTurnInterval || 30}s` : 'Off'}
    87	             toggle={s.autoTurn}
    88	             active={s.autoTurn}
    89	             on={() => onToggle('autoTurn')}/>
    90	
    91	        {s.aiUnavailable ? (
    92	          <Row icon={Icons.Translate} label="Bilingual mode"
    93	               sub="Configure AI provider first"
    94	               disabled
    95	               on={() => onAction('configure-ai')}/>
    96	        ) : (
    97	          <Row icon={Icons.Translate} label="Bilingual mode"
    98	               sub={s.bilingual ? `English ↔ ${s.bilingualLang || 'Chinese'}` : 'Translate inline'}
    99	               toggle={s.bilingual}
   100	               active={s.bilingual}
   101	               on={() => onToggle('bilingual')}/>
   102	        )}
   103	
   104	        <Row divider/>
   105	
   118	                : 'rgba(0,0,0,0.08)',
   119	              display: 'flex', alignItems: 'center', justifyContent: 'center',
   120	              flexShrink: 0,
   121	            }}>
   122	              <Icons.Sparkle size={14} color={aiConfigured ? '#fff' : t.sub} stroke={2}/>
   123	            </div>
   124	            <div style={{ flex: 1, minWidth: 0 }}>
   125	              <div style={{ fontSize: 13.5, color: t.ink, fontWeight: 600 }}>
   126	                {aiConfigured ? 'Claude · with this book\'s context' : 'No AI provider configured'}
   127	              </div>
   128	              <div style={{ fontSize: 11.5, color: t.sub, marginTop: 1 }}>
   129	                {aiConfigured
   130	                  ? 'Translations cached per paragraph, one page ahead.'
   131	                  : 'Bilingual mode needs an AI provider to translate.'}
   132	              </div>
   133	            </div>
   134	            <button style={{
   135	              padding: '5px 11px', borderRadius: 100, border: 'none',
   136	              background: aiConfigured
   137	                ? (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)')
   138	                : t.accent,
   139	              color: aiConfigured ? t.ink : '#fff',
   140	              fontFamily: 'inherit', fontSize: 11.5, fontWeight: 600, cursor: 'pointer',
   141	              flexShrink: 0,
   142	            }}>{aiConfigured ? 'Change…' : 'Set up'}</button>
   143	          </div>
   144	        </div>
   145	
   146	        {/* CTA */}
   147	        <button onClick={onClose} style={{
   148	          width: '100%', marginTop: 22, padding: '14px 0', borderRadius: 14,
    82	  done). Box C checks when BOTH #127 and #128 are VERIFIED — #127 ✓, #128 remains.**
    83	
    84	- [ ] **D. Bilingual interlinear reading** — interlinear original+translation rendering + the bilingual
    85	  setup sheet (languages · provider · model · style), building on the #118 AI provider.
    86	  Design: `vreader-ai-android.jsx` (BilingualReader/BilingualSetupSheet) + `vreader-bilingual.jsx`.
    87	  Note: the pipeline + UI are buildable autonomously; LIVE translation verification is
    88	  AI-credential-gated (a mock/integration path verifies the pipeline). iOS parity: #56/#100.
    89	

codex
The Readium feasibility correction is valid: the local 3.3.0 AAR exists, and its transformed API JAR exposes public `evaluateJavascript(String, Continuation<? super String>)`, `getCurrentLocator()`, `firstVisibleElementLocator(...)`, and `submitPreferences(...)`. `ReaderActivity.navigator` also exists with the claimed concrete type. The #118 AI signatures and backup fields are otherwise accurately described.

## Critical

None.

## High

1. **TXT/MD pairing is based on a nonexistent chapter model and the proposed render boundary is not the segmentation boundary.**  
   Plan: [§2 New files / Modified files](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:35), [WI-4](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:165), [§6 parity claim](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:197).

   `TxtDocument` has line-based, maximum-4,000-character chunks only; it has no chapter model. `TxtMdTextExtractor` explicitly treats each chunk as a section because “TXT has no sub-resource grouping.” Meanwhile the plan proposes `txtChapterIndex` units and rendering one `BilingualInterlinearBody` inside each existing `items(document.chunkCount)` item. A chunk can contain multiple paragraphs or split a long paragraph, so this does not establish the claimed “same `ChapterSegmenter` on translate and render” 1:1 contract.

   **Concrete fix:** define the real TXT/MD unit and render mapping. Either:

   - use document-global units with segment ranges produced once by `ChapterSegmenter`, map every segment to its source UTF-16 range/chunk span, and render source/translation pairs from those same ranges; or
   - introduce an explicitly specified chapter detector/model, including deterministic UTF-16 chapter ranges, and then segment each chapter identically on both paths.

   Add tests for paragraphs spanning chunk boundaries, multiple paragraphs in one chunk, a >4,000-character paragraph, CR/LF/CRLF, MD markers, locator-to-unit mapping, and source-byte parity while disabled.

2. **The mandatory EPUB count-divergence recovery is named but never implemented by a WI.**  
   Plan: [WI-0 divergence decision](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:116), [WI-3 service API](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:163), [WI-7b](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:173), [§6 parity claim](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:197).

   The plan says divergence adopts iOS’s `translatePreSegmented` path, but WI-3 builds only `cachedTranslation` and `translate`; WI-4 has no direct-block prefetch/cache API. The iOS parity path actually includes:

   - `translatePreSegmented`
   - cache write using the enumerated count
   - cache-only restore by `expectedSegmentCount`
   - direct-block prefetch without requiring a provider on a cache hit

   Therefore `EpubReaderBilingualConnectedTest.count-divergence handled` has no planned implementation behind it.

   **Concrete fix:** add those APIs and their cache semantics to WI-3/WI-4, with cancellation and partial-failure behavior matching iOS Bugs #268/#330/#343. Add direct-path cache-hit/reopen, mismatch replacement, partial-not-cached, all-failed, and zero-provider-call cache-restore tests.

3. **A fresh-install user cannot configure AI, and an expressly open design/acceptance gate remains.**  
   Plan: [AppContainer/navigation correction](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:64), [out-of-scope route](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:87), [Design gates](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:209).

   The live app has no route to `AiProviderListScreen`. The committed More design disables the bilingual row when AI is unavailable, while the setup sheet’s “Set up” control also has no destination. Thus a normal fresh install cannot reach either provider configuration or the configured bilingual flow. In addition, the parity checklist still defines box D as including provider/model/style, while the plan drops Style and nevertheless has WI-9 flip box D to done.

   **Concrete fix:** make a tracked, designed AI-settings navigation feature a hard dependency and verify `unconfigured → Configure/Set up → add provider → return → enable → translate`. Resolve the Style/Granularity design conflict before WI-9, or explicitly amend the authoritative checklist through a product/design decision; until then, do not mark #131 DONE or flip box D.

## Medium

1. **WI-0 lacks enforceable go/no-go thresholds and a navigator-operation race contract.**  
   Plan: [WI-0 contract](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:116), [WI-0 work item](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:157).

   “Stable,” “measure effects,” and “re-apply” do not define pass criteria. The plan also does not serialize `enumerate → translate → inject` against disable/clear, href changes, reflow, or teardown. A late inject can otherwise land after a clear.

   **Concrete fix:** require WI-0 to prove, on a real EPUB:

   - deterministic, idempotent enumeration and node IDs;
   - no duplicate nodes after repeated application;
   - clear wins over every older inject;
   - href away/back, same-href `submitPreferences` reflow, internal page-fragment recreation, and activity recreation all restore from cache;
   - locator/visible-source preservation across injection, with a stated permissible delta;
   - an identified production re-apply signal for every tested recreation case.

   Specify a single actor/mutex or monotonic navigator-session token, checks after every suspended JS/AI call, and cancellation/clear before publication teardown. Failure to find a deterministic re-apply signal must be an explicit no-go.

2. **WI-7b incorrectly treats a Compose body as the EPUB render surface.**  
   Plan: [BilingualInterlinearBody description](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:71), [WI-7b](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:173).

   `BilingualInterlinearBody` cannot render inside Readium’s WebView. EPUB needs DOM node construction and CSS; it can share state/value types with Compose, but not the composable render body.

   **Concrete fix:** define separate `EpubBilingualJs`/adapter and DOM-CSS styling, consuming a host-neutral state DTO. Test escaping, CSP-safe text insertion, RTL/CJK style, empty translations, loading cleanup, idempotent replacement, and source-only fallback. Remove the misleading WI-7a UI dependency unless it is needed only for shared state types.

3. **The dependency graph does not make EPUB integration buildable in sequence.**  
   Plan: [WI-6](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:169), [WI-7b dependencies](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:173), [WI-8 DI ownership](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:175).

   WI-7b needs VM prefetch behavior from WI-6 but does not depend on it. It also wires `ReaderActivity` before the AppContainer services/factory that are assigned to WI-8.

   **Concrete fix:** extract DI/factory wiring into an earlier shared WI, then make both host integrations depend on it and WI-6. A suitable order is foundation/cache → service/direct-block APIs → provider/DI → VM state/prefetch → host-specific renderers → entry wiring.

4. **The Room schema baseline is stale and names a conflicting migration.**  
   Plan: [Modified files](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:76), [Backward compatibility](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:204).

   The live database is version 8, not 5; `MIGRATION_5_6` already belongs to feature #128. Implementing the named migration would conflict with existing history.

   **Concrete fix:** state “allocate current→next at implementation time”; against this checkout that is 8→9, `MIGRATION_8_9`, append after `MIGRATION_7_8`, and extend the exported-schema/full-chain tests from version 8.

## Low

1. **The feature-dependency description is stale.**  
   Plan: [§4 dependency notes](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:152).

   #129, #132, and #134 are now VERIFIED, and the live More model already reserves `MoreActionId.BILINGUAL`.

   **Concrete fix:** replace “prospective/not yet decomposed/waits on” language with the exact landed integration points and mark these dependencies satisfied.

2. **The work-item count is internally ambiguous.**  
   Plan: [§4 introduction](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:148).

   WI-0, WI-1…6, WI-7a, WI-7b, WI-8, and WI-9 are eleven PR-sized items, not ten.

   **Concrete fix:** state “11 WIs/PRs” and list the conditional EPUB WI clearly.

**GATE-2 ROUND-2 VERDICT: FINDINGS (0 Critical, 3 High, 4 Medium)**
tokens used
157,631
The Readium feasibility correction is valid: the local 3.3.0 AAR exists, and its transformed API JAR exposes public `evaluateJavascript(String, Continuation<? super String>)`, `getCurrentLocator()`, `firstVisibleElementLocator(...)`, and `submitPreferences(...)`. `ReaderActivity.navigator` also exists with the claimed concrete type. The #118 AI signatures and backup fields are otherwise accurately described.

## Critical

None.

## High

1. **TXT/MD pairing is based on a nonexistent chapter model and the proposed render boundary is not the segmentation boundary.**  
   Plan: [§2 New files / Modified files](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:35), [WI-4](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:165), [§6 parity claim](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:197).

   `TxtDocument` has line-based, maximum-4,000-character chunks only; it has no chapter model. `TxtMdTextExtractor` explicitly treats each chunk as a section because “TXT has no sub-resource grouping.” Meanwhile the plan proposes `txtChapterIndex` units and rendering one `BilingualInterlinearBody` inside each existing `items(document.chunkCount)` item. A chunk can contain multiple paragraphs or split a long paragraph, so this does not establish the claimed “same `ChapterSegmenter` on translate and render” 1:1 contract.

   **Concrete fix:** define the real TXT/MD unit and render mapping. Either:

   - use document-global units with segment ranges produced once by `ChapterSegmenter`, map every segment to its source UTF-16 range/chunk span, and render source/translation pairs from those same ranges; or
   - introduce an explicitly specified chapter detector/model, including deterministic UTF-16 chapter ranges, and then segment each chapter identically on both paths.

   Add tests for paragraphs spanning chunk boundaries, multiple paragraphs in one chunk, a >4,000-character paragraph, CR/LF/CRLF, MD markers, locator-to-unit mapping, and source-byte parity while disabled.

2. **The mandatory EPUB count-divergence recovery is named but never implemented by a WI.**  
   Plan: [WI-0 divergence decision](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:116), [WI-3 service API](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:163), [WI-7b](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:173), [§6 parity claim](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:197).

   The plan says divergence adopts iOS’s `translatePreSegmented` path, but WI-3 builds only `cachedTranslation` and `translate`; WI-4 has no direct-block prefetch/cache API. The iOS parity path actually includes:

   - `translatePreSegmented`
   - cache write using the enumerated count
   - cache-only restore by `expectedSegmentCount`
   - direct-block prefetch without requiring a provider on a cache hit

   Therefore `EpubReaderBilingualConnectedTest.count-divergence handled` has no planned implementation behind it.

   **Concrete fix:** add those APIs and their cache semantics to WI-3/WI-4, with cancellation and partial-failure behavior matching iOS Bugs #268/#330/#343. Add direct-path cache-hit/reopen, mismatch replacement, partial-not-cached, all-failed, and zero-provider-call cache-restore tests.

3. **A fresh-install user cannot configure AI, and an expressly open design/acceptance gate remains.**  
   Plan: [AppContainer/navigation correction](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:64), [out-of-scope route](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:87), [Design gates](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:209).

   The live app has no route to `AiProviderListScreen`. The committed More design disables the bilingual row when AI is unavailable, while the setup sheet’s “Set up” control also has no destination. Thus a normal fresh install cannot reach either provider configuration or the configured bilingual flow. In addition, the parity checklist still defines box D as including provider/model/style, while the plan drops Style and nevertheless has WI-9 flip box D to done.

   **Concrete fix:** make a tracked, designed AI-settings navigation feature a hard dependency and verify `unconfigured → Configure/Set up → add provider → return → enable → translate`. Resolve the Style/Granularity design conflict before WI-9, or explicitly amend the authoritative checklist through a product/design decision; until then, do not mark #131 DONE or flip box D.

## Medium

1. **WI-0 lacks enforceable go/no-go thresholds and a navigator-operation race contract.**  
   Plan: [WI-0 contract](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:116), [WI-0 work item](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:157).

   “Stable,” “measure effects,” and “re-apply” do not define pass criteria. The plan also does not serialize `enumerate → translate → inject` against disable/clear, href changes, reflow, or teardown. A late inject can otherwise land after a clear.

   **Concrete fix:** require WI-0 to prove, on a real EPUB:

   - deterministic, idempotent enumeration and node IDs;
   - no duplicate nodes after repeated application;
   - clear wins over every older inject;
   - href away/back, same-href `submitPreferences` reflow, internal page-fragment recreation, and activity recreation all restore from cache;
   - locator/visible-source preservation across injection, with a stated permissible delta;
   - an identified production re-apply signal for every tested recreation case.

   Specify a single actor/mutex or monotonic navigator-session token, checks after every suspended JS/AI call, and cancellation/clear before publication teardown. Failure to find a deterministic re-apply signal must be an explicit no-go.

2. **WI-7b incorrectly treats a Compose body as the EPUB render surface.**  
   Plan: [BilingualInterlinearBody description](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:71), [WI-7b](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:173).

   `BilingualInterlinearBody` cannot render inside Readium’s WebView. EPUB needs DOM node construction and CSS; it can share state/value types with Compose, but not the composable render body.

   **Concrete fix:** define separate `EpubBilingualJs`/adapter and DOM-CSS styling, consuming a host-neutral state DTO. Test escaping, CSP-safe text insertion, RTL/CJK style, empty translations, loading cleanup, idempotent replacement, and source-only fallback. Remove the misleading WI-7a UI dependency unless it is needed only for shared state types.

3. **The dependency graph does not make EPUB integration buildable in sequence.**  
   Plan: [WI-6](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:169), [WI-7b dependencies](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:173), [WI-8 DI ownership](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:175).

   WI-7b needs VM prefetch behavior from WI-6 but does not depend on it. It also wires `ReaderActivity` before the AppContainer services/factory that are assigned to WI-8.

   **Concrete fix:** extract DI/factory wiring into an earlier shared WI, then make both host integrations depend on it and WI-6. A suitable order is foundation/cache → service/direct-block APIs → provider/DI → VM state/prefetch → host-specific renderers → entry wiring.

4. **The Room schema baseline is stale and names a conflicting migration.**  
   Plan: [Modified files](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:76), [Backward compatibility](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:204).

   The live database is version 8, not 5; `MIGRATION_5_6` already belongs to feature #128. Implementing the named migration would conflict with existing history.

   **Concrete fix:** state “allocate current→next at implementation time”; against this checkout that is 8→9, `MIGRATION_8_9`, append after `MIGRATION_7_8`, and extend the exported-schema/full-chain tests from version 8.

## Low

1. **The feature-dependency description is stale.**  
   Plan: [§4 dependency notes](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:152).

   #129, #132, and #134 are now VERIFIED, and the live More model already reserves `MoreActionId.BILINGUAL`.

   **Concrete fix:** replace “prospective/not yet decomposed/waits on” language with the exact landed integration points and mark these dependencies satisfied.

2. **The work-item count is internally ambiguous.**  
   Plan: [§4 introduction](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:148).

   WI-0, WI-1…6, WI-7a, WI-7b, WI-8, and WI-9 are eleven PR-sized items, not ten.

   **Concrete fix:** state “11 WIs/PRs” and list the conditional EPUB WI clearly.

**GATE-2 ROUND-2 VERDICT: FINDINGS (0 Critical, 3 High, 4 Medium)**
