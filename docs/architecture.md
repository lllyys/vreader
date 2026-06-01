# VReader Architecture

## Overview

VReader is an iOS e-book reader built with SwiftUI + SwiftData. It supports TXT, EPUB, AZW3/MOBI, PDF, and Markdown formats, each rendered by a format-specific native host (UIKit/WebView bridges) selected internally by `ReaderEngine` (feature #54). AZW3/MOBI is rendered via Foliate-js inside a WKWebView. The `UnifiedTextRenderer` (TextKit 2 reflow) stack is retained in the codebase but no longer wired into the reader dispatch.

## System Diagram

```
┌──────────────────────────────────────────────────────┐
│                    VReaderApp                         │
│  SwiftData SchemaV8 · PersistenceActor · BookImporter│
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

- `VReaderApp.swift` — SwiftData `ModelContainer` init (SchemaV8), migration plan (V1→V2→V3→V4→V5→V6→V7→V8), test seeding, error handling. Injects the live `PersistenceActor` into the SwiftUI environment via `\.persistenceActor` so settings sub-screens can construct backup providers without rewriting every parent's signature. Adopts `@UIApplicationDelegateAdaptor(VReaderAppDelegate.self)` for background-URLSession completion-handler delivery (feature #47).
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
  it.

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

`ReaderUnifiedCoordinator` loads text + applies transforms (replacement rules, simp/trad); `UnifiedTextRenderer` displays with TextKit 2 pagination or scroll. Feature #54 removed the unified path from the reader dispatch and the reader-settings Reading Mode picker, so this stack is **no longer reachable from reader dispatch** — it is retained (a follow-up may consume it for bilingual reading, or delete it once provably orphaned). Content replacement rules and Chinese conversion that previously required Unified mode now run in the native readers directly: `MDFileLoader.load` composes `ReplacementTransform` + `SimpTradTransform` over the decoded source text before parsing (feature #54 WI-7); native TXT has Chinese conversion only — TXT replacement rules are deferred (they need a source↔display offset map).

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
| `AIService`                          | OpenAI-compatible REST API | Summarize, translate, chat. Feature #56 added a resolved-provider seam — `ResolvedAIProviderConfig` (an immutable `{kind, baseURL, apiKey, model, maxTokens}` snapshot) plus `resolveActiveProviderConfig()` / `resolveProviderConfig(profileID:modelOverride:)` / `sendRequest(_:using:)`. A *multi-request* operation (chapter translation = one request per chunk) resolves the config ONCE and pins the credential + model for every chunk; `sendRequest(_:using:)` deliberately bypasses `AIResponseCache` (its key is not provider-aware). The original `resolveProvider()` / `sendRequest(_:)` / `streamRequest(_:)` are unchanged |
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
| `DebugBridge`                        | URL handler (DEBUG-only)   | `vreader-debug://` reset/seed/open/settle/snapshot/eval/tts/search/highlight/provider/present/ai/seed-sessions/seek/scroll-sheet/navigate/scroll-boundary; feature #49 added position-aware open + DebugSnapshot schema v2 (TTS state, render phase, settings provenance); feature #45 WI-4c-b added `tts?action=start\|stop` to bypass XCUITest's audio-session block; bug #238 added `search?query=...[&index=N]` to drive search-result-tap repros (Bug #182 / GH #621) CU-free; bug #237 added `highlight?start=...&end=...[&color=...]` for TXT/MD highlight creation CU-free; bug #243 added `provider?action=add\|remove\|clear` for AI provider configuration without driving Settings → AI through CU (unlocks Feature #56 b/d / Feature #65 / Feature #69 / Bug #93 autonomous AI verification); bug #253 added `present?sheet=...[&tab=...]` + bug #255 added `ai?action=summarize\|chat\|translate` for CU-free reader-sheet + AI-response-card verification; bug #263 added `seed-sessions?book=<key>[&seconds=<n>]` to seed a deterministic `ReadingSession` spread (one per dashboard window band) so the reading-stats dashboard (Feature #58) renders non-zero per-window totals CU-free; bug #267 added `seek?fraction=<0...1>` to drive the active Foliate (AZW3/MOBI) reader to a fractional position CU-free; bug #271 added `scroll-sheet?to=top\|bottom` to scroll the active presented sheet's content (today `TranslationResultCard`) so the accent translation card below the tall ORIGINAL card — beyond even the `detent=large` fold (Bug #256) — becomes screenshot-capturable, unblocking Feature #65 row 11; bug #273 added `navigate?spine=<N>[&fraction=<F>]` to drive `.readerNavigateToLocator` for the active EPUB reader CU-free (the `search` driver doesn't navigate in continuous mode), posting DEBUG-only `.debugBridgeNavigateCommand` → `EPUBReaderContainerView` resolves spine → href → `Locator` → re-posts `.readerNavigateToLocator` — unblocking feature #71 WI-8 continuous-mode navigation verification (paired with the `multi-chapter-epub` 4-tall-chapter fixture for the out-of-window rebuild branch); a follow-up added `scroll-boundary?spine=<N>&near=top\|bottom` to post a DEBUG-only `.debugBridgeScrollBoundaryCommand` → `EPUBReaderContainerView` builds an `EPUBScrollBoundarySignal` and calls `EPUBContinuousScrollCoordinator.handleBoundarySignal` directly — bypassing the rAF-throttled `continuousScrollObserverJS` (unverifiable CU-free on a virtual display) so feature #71's scroll-driven extend/evict RESPONSE can be device-verified. **Host-vs-runner driving constraint (bug #242 / GH #1054)**: bridge URLs MUST be invoked from the host (`xcrun simctl openurl` outside any iOS sandbox) — invoking them from inside an XCUITest binary fails with NSPOSIX 61 because the runner sandbox blocks the CoreSimulatorService XPC endpoint. In-runner verification flows use `XCTSkipUnless(bridgeReachable())` (PR #1053) when they cannot move the bridge-dependent assertion to a host-side driver. See `docs/subsystems/debug-bridge.md` § "Driving the bridge from a verification flow". |
| `DebugPositionResolver`              | —                          | Pure parser: `?position=<value>` string → typed `DebugPosition` per BookFormat (TXT/MD UTF-16 offset, EPUB CFI, AZW3 Foliate-CFI, PDF page). Every format takes its native seek path (feature #54 retired the Native/Unified mode + its position-unsupported guard). Feature #49 WI-7a. |
| `DebugReaderRegistry.awaitReader`    | DebugReaderRegistry singleton | Token-based keyed waiter that resumes when a reader matching `fingerprintKey` registers. Concurrent waiters with different timeouts each get their own continuation (UUID-token ownership). Feature #49 WI-7a. |
| `DebugReaderRegistry.awaitReaderSettled` | DebugReaderRegistry singleton (`+Settle` extension) | Bug #141: render-settled signal keyed by `(fingerprintKey, token)`. Hosts call `markReaderSettled` on real render-complete — EPUB from `webView(_:didFinish:)`, AZW3/MOBI from the Foliate `relocate` message. `ReaderContainerView` wires `probe.settleStrategy` so `vreader-debug://settle` blocks until that signal (or `settleTimeout`) instead of the 100ms placeholder. TXT/MD/PDF keep the placeholder. Same UUID-token waiter machinery + stale-write guard as `awaitReader`. |
| `ImportJobQueue`                     | Actor                      | Serializes book imports (avoids parallel `BookImporter` writes)           |
| `FileURLImportRouter`                | `BookImporting` (protocol) | `@MainActor` dispatcher for incoming `file://` URLs from iOS Share Sheet / "Open in vreader" (Feature #59 WI-2). Wired by `VReaderApp`'s production `.onOpenURL`. Returns `false` for non-file URLs (Debug-bridge handler intercepts those upstream). Unsupported extensions reported via injected closure (App layer wires the user-facing alert; current production wiring is a no-op). Supported extensions kick off `bookImporter.importFile(at:source:.shareSheet)` in a fire-and-forget Task. Security-scope handling owned by `BookImporter`, not the router. |
| `LibraryRefreshService`              | NotificationCenter         | Coalesces library refresh requests across views                           |
| `FeatureFlags`                       | Static                     | Compile/runtime flag resolution (`SyncService` and others gate on it)     |
| `DictionaryLookup`                   | UIKit                      | System dictionary + AI-translate hooks for selected text                  |
| `ChapterTranslationStore`            | SwiftData (actor-isolated) | Persistent disk cache for feature #56 bilingual reading. Wraps its own `ModelContext` over the `ChapterTranslation` `@Model` (SchemaV7) — a separate actor from `PersistenceActor` so bulk translation writes during a global-translate run never block library reads. App-scoped `.shared` single instance (the `ProviderProfileStore.shared` precedent); idempotent `upsert` fetches by `lookupKey` and updates in place, never relying on the unique constraint to throw. Returns the value-type `ChapterTranslationRecord` DTO, never the `@Model`. The cache is derived, re-fetchable data — excluded from WebDAV backup |
| `ChapterTranslationService`          | `ChapterTranslationStore` + `AIService` | Translates one chapter unit for feature #56 bilingual reading. Pipeline: cache lookup → (on miss) `ChapterSegmenter` → `ChapterTranslationChunker` → one `AIService.sendRequest(_:using:)` per chunk → strict `TranslationChunkContract` JSON-array decode → per-segment fallback on any decode/count/element mismatch → recombine → cache-write. Reaches the AI side through the `TranslationRequestSending` boundary protocol (tests inject a mock). `Task.checkCancellation()` between chunks so a cancelled prefetch stops promptly |
| `ChapterTextProviding` (`Services/Reader/`) | per-format reader services | Feature #56 WI-2.5 boundary protocol — supplies a book's translation units (`translationUnits()`), per-unit plain source text (`sourceText(for:)`), and the `Locator → unit` resolution (`unit(containing:)` / `unit(after:)`) the bilingual prefetch trigger needs. The translation *unit* is the format's natural rendering segment, not the logical TOC chapter (plan Decision 2.7). Four concrete `Sendable` `struct` adapters: `EPUBChapterTextProvider` (spine documents, HTML-stripped via `EPUBTextExtractor`), `TXTChapterTextProvider` (`TXTChapterIndex` chapters, UTF-16 slicing), `MDChapterTextProvider` (`MDHeading`-bounded chapters), `PDFChapterTextProvider` (page ranges via PDFKit). The AZW3/MOBI `FoliateChapterTextProvider` (an `actor`, bridges the `@MainActor` Foliate coordinator via the `FoliateSectionExtracting` facade) lands in WI-11. `ChapterTranslationService` / `BookTranslationCoordinator` consume this boundary, never a format-specific extractor |
| `FoliateChapterTextProvider` (`Services/Reader/`) | `FoliateSectionExtracting` | Feature #56 WI-11 — AZW3/MOBI `ChapterTextProviding` adapter. The odd one out: an `actor` (not a `struct`) because the live Foliate seam (`FoliateSpikeView.Coordinator` + `WKWebView`) is `@MainActor`. Stores an `any FoliateSectionExtracting` and reaches it via `await`; an `actor` is `Sendable` by construction so it satisfies `ChapterTextProviding: Sendable` without `nonisolated(unsafe)`. Caches the ordered section-id list on the first `translationUnits()` call; a book reopen rebuilds the provider from scratch so the cache never goes stale within one open book |
| `FoliateSectionExtracting` (`Services/Reader/`) | `FoliateSpikeView.Coordinator` (extension) | Feature #56 WI-11 — `@MainActor protocol` bridging the live Foliate per-section text extraction seam (the `readerAPI.bilingualSectionIDs` / `readerAPI.bilingualSectionText` JS calls) into the `Sendable` `ChapterTextProviding` boundary. Class-bound + `Sendable` + `@MainActor` means a `@MainActor`-isolated `AnyObject` existential is safely `Sendable` (members are main-actor-isolated), so the `FoliateChapterTextProvider` actor can hold a single live reference without an unsafe escape hatch |
| `ChapterPrefetching` (`Services/AI/`) | `BilingualReadingViewModel` | Feature #56 WI-7b seam — `translatedSegments(for:targetLanguage:granularity:)`, the single-method translation-prefetch boundary `BilingualReadingViewModel`'s unit-aware prefetch trigger depends on. Decouples the view model from provider resolution / the disk cache / chunking; production wires a thin adapter over `ChapterTranslationService` + `AIService`, tests inject a deterministic mock |
| `ChapterTranslationPrefetcher` (`Services/AI/`) | `ChapterTranslationService` + `AIService` + `ChapterTextProviding` | Feature #56 WI-10 production `ChapterPrefetching` adapter. `Sendable` `struct` per open book. Each `translatedSegments(...)` call resolves the active provider config once (`AIService.resolveActiveProviderConfig`) — a profile flip during a chapter prefetch does not split chunks across providers. Pulls per-unit source text from the injected `ChapterTextProviding` and routes the request through `ChapterTranslationService.translate(...)`. Default style is `.natural`; the re-translate picker (WI-15) is the only path that overrides it |
| `BookTranslationCoordinator` (`Services/AI/`) | `ChapterTranslationService` + `ChapterTranslationStore` + `ChapterTextProviding` | Feature #56 WI-14 actor driving the "translate entire book" flow. App-scoped `.shared` instance (configured at `VReaderApp.init`). `start(...)` spawns a background task that iterates `ChapterTextProviding.translationUnits()`, skips units already covered in `ChapterTranslationStore.cachedUnits(...)`, hands each remaining unit to `ChapterTranslationService.translate(...)`, and emits monotonic `BookTranslationProgress` snapshots through an `AsyncStream` (`progressUpdates(forBookWithKey:)`). At most one running job per book — a second `start` for the same book is a silent no-op. `cancel(_:)` stops between units; `cancelAndPurge(_:)` additionally wipes the book's cache rows for the user-delete-book path (plan edge case (g)). Posts `.readerBookTranslationProgressDidChange` on every snapshot so a reader open on the book drives its `ReaderTranslateBanner` |
| `BookTranslationViewModel` (`ViewModels/`) | `BookTranslationCoordinator` | Feature #56 WI-14 `@MainActor @Observable` UI-facing state for the translate-entire-book flow. Drives the confirm alert (`presentConfirm` loads `estimate` + shows alert), the status sheet (`startObserving` subscribes to the coordinator's progress stream and mirrors snapshots into `progress`), and the cancel alert (`requestCancel` opens the confirmation, `confirmCancel` propagates to the coordinator). One per surface (Book Details, library card, reader chrome); multiple VMs for the same book observe the same coordinator job |
| `ChapterReTranslateViewModel` (`ViewModels/`) | `AIService` + `ChapterTranslationService` + `ChapterTranslationStore` | Feature #56 WI-15 `@MainActor @Observable` UI-facing state for the per-chapter re-translation flow. `presentPicker(...)` opens `ReTranslatePickerSheet` with the chosen unit + title + target language; `updateSelection(_:)` mutates the picker's `(providerProfileID, model, style, keepGlossary)` selection; `submit()` deletes the original cache row by `lookupKey`, resolves the picker's `ResolvedAIProviderConfig` through the `RetranslateProviderResolving` boundary (`AIService` conforms), runs the translation through `ChapterReTranslating` (`ChapterTranslationService` conforms), and fires `onTranslationApplied` so the host posts `.readerBilingualReTranslateApplied`. Picker override never mutates `ProviderProfileStore` (acceptance criterion (f)) |
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

SwiftData SchemaV8 entities:

- `Book` (fingerprintKey unique; gains `originalExtension: String?` in SchemaV5 for backup blob extension preservation; gains `fileState: String` and `blobPath: String?` in SchemaV6 for feature #47's lazy-load row state) → `ReadingPosition` (gains `vreaderLocatorData: Data?` in SchemaV8 — feature #42's engine-agnostic `VReaderLocator` envelope, stored as raw JSON `Data?` mirroring `Highlight.anchorData`; additive/optional → lightweight migration, no stage), `Highlight`, `Bookmark`, `AnnotationNote`, `BookCollection`
- `ReadingSession`, `ReadingStats`
- `BookSource`, `ContentReplacementRule` (added in SchemaV4)
- `ChapterTranslation` (added in SchemaV7 — feature #56 bilingual-reading persistent translation cache; independent entity, no `@Relationship` to `Book`; `lookupKey: String` is the `@Attribute(.unique)` dedupe key joined from `bookFingerprintKey` + `unitStorageKey` + `targetLanguage` + `providerProfileID` + `promptVersion`)

`PersistenceActor.fetchAllBooksForBackup() -> [BackupBookProjection]` (in `PersistenceActor+Backup.swift`) returns a Sendable value-type view of every book — used by feature #46's WebDAV backup to emit `library-manifest.json` without leaking `@Model` instances across the actor boundary. Legacy V4 rows (no `originalExtension`) coalesce to the canonical extension for their format.

**Feature #47 — Selective picker + lazy-load (data layer)**: backend complete (WI-3 + WI-4 + WI-5 partial); UI picker + WebDAVProvider integration in WI-6; final acceptance + Docker-test follow-ups in WI-7. `Book.fileState` enum mirrors `BookFileState`: `.local` (bytes present, default), `.remoteOnly` (row exists, blob on server, no local bytes), `.downloading` (lazy fetch in flight), `.failed` (lazy fetch errored — retryable), `.missingRemote` (server lost the blob — needs re-upload, not re-download). `LibraryBookItem` carries the projection so row UI branches on `isReadable` / `needsDownload` / `canShare`. `PersistenceActor+RemoteOnly.swift` adds the bulk insert + state mutation helpers the lazy-download coordinator + `SelectiveRestoreCoordinator` use. The lazy-download coordinator's `bookFileStateDidChange` notification refreshes library rows after reconcile flips an orphaned `.downloading` row to `.failed`.

**Feature #46 — WebDAV materializing restore (data layer)**: backup ZIPs now carry an additional `library-manifest.json` section (one `BackupLibraryEntry` per book, including content-addressed `blobPath`). On `backup`, `WebDAVProvider` uploads each missing book blob atomically — `WebDAVBlobStore` PUTs to `VReader/uploads/tmp/<uuid>.part`, PROPFIND-verifies the size, then `MOVE`s into the canonical `VReader/books/<format>/<sha256>_<byteCount>.<ext>` path. Repeat backups skip already-published blobs via PROPFIND-by-size dedupe. On `restore`, when the manifest is present and a `BookImporter` is wired in (production: via `\.bookImporter` SwiftUI Environment), `BookFileMaterializer` downloads + verifies + imports each missing blob before metadata sections apply. v1-format backups (no manifest) restore as before — books silently skipped if missing locally. The 412 response from `MOVE Overwrite: F` is treated as "blob already converged" (content-addressing). 501 from `MOVE` raises `BackupBlobStoreError.serverCapabilityMissing` — no silent atomicity loss.

Backup section JSONs (`vreader/Services/Backup/BackupSectionDTOs.swift`) are
versioned via the `BackupVersionedEnvelope` protocol. Restore validates exact
`schemaVersion == 1` and raises `BackupRestoreError.unsupportedSchemaVersion`
on mismatch, so a future v2 archive can't silently apply on a v1 client.

Key types:

- `DocumentFingerprint` — `{format}:{SHA256}:{byteCount}` deterministic identity
- `Locator` — universal position: href+progression+CFI (EPUB/AZW3), page (PDF), UTF-16 offset (TXT/MD)
- `AnnotationAnchor` — format-agnostic location encoding for highlights/bookmarks
- `FormatCapabilities` — per-`BookFormat` capability matrix (selection, highlights, search, TTS, native pagination, unified reflow, TOC, annotations) consulted by the dispatcher and feature gates

## Notification Bus (`vreader/Views/Reader/ReaderNotifications.swift`)

All cross-component communication uses NotificationCenter:

| Notification                   | Payload              | Direction                                               |
| ------------------------------ | -------------------- | ------------------------------------------------------- |
| `.readerContentTapped`         | nil                  | Bridge → Container (toggle chrome)                      |
| `.readerPositionDidChange`     | `Locator`            | Format container → ReaderContainerView → AI coordinator |
| `.readerNavigateToLocator`     | `Locator`            | Container → Format container                            |
| `.readerBookmarkRequested`     | nil                  | Chrome → Format container                               |
| `.readerTextSelected`          | `TextSelectionInfo`  | Bridge → Container (active selection state)            |
| `.readerHighlightRequested`    | `TextSelectionInfo`  | Bridge → Container                                      |
| `.readerSelectionPopoverRequested` | `TextSelectionInfo` (object) | Bridge → `SelectionPopoverPresenterModifier` (Feature #60 WI-7c1). Bridges that have swapped to the popover suppress their legacy `UIMenu` and post this instead; the presenter mounts `SelectionPopoverView` (WI-7a) as a sheet and routes taps through `SelectionPopoverActionRouter` (WI-7b). |
| `.readerHighlightRemoved`      | UUID string          | HighlightListVM → Container                             |
| `.readerHighlightsDidImport`   | fingerprintKey       | Importer → format containers (refresh persisted highlights) |
| `.readerDidClose`              | fingerprintKey       | ViewModel → LibraryView                                 |
| `.readerAnnotationRequested`   | `TextSelectionInfo`  | Bridge → Container                                      |
| `.readerDefineRequested`       | `TextSelectionInfo`  | Bridge → Container (dictionary)                         |
| `.readerTranslateRequested`    | `TextSelectionInfo`  | Bridge → Container (AI translate)                       |
| `.searchHighlightClear`        | nil                  | SearchViewModel → Bridges                               |
| `.readerPreviousPage`          | nil                  | `ReaderTapZoneRouter` (left-zone tap in `.paged` layout) → format container's `onReceive` consumer. Bug #239 / GH #988 restored this producer after feature #54 WI-3 unmounted the legacy `TapZoneOverlay` overlay; native bridges' tap recognizers / WKWebView JS handlers now route through the router. |
| `.readerNextPage`              | nil                  | `ReaderTapZoneRouter` (right-zone tap in `.paged` layout) → format container's `onReceive` consumer. Mirror of `.readerPreviousPage`. Foliate (AZW3/MOBI) additionally observes on the spike coordinator and evaluates `readerAPI.next();` against the live WKWebView. |
| `.readerOpenContents`          | nil                  | `ReaderBottomChrome` toolbar → ReaderContainerView (Feature #62 — opens `TOCSheet` on the Contents tab) |
| `.readerOpenNotes`             | nil                  | `ReaderBottomChrome` toolbar → ReaderContainerView (Feature #62 — opens `HighlightsSheet` on the All filter) |
| `.readerOpenDisplay`           | nil                  | `ReaderBottomChrome` toolbar → ReaderContainerView (Feature #60 WI-6b — opens reader settings) |
| `.readerOpenAI`                | nil                  | `ReaderBottomChrome` toolbar → ReaderContainerView (Feature #60 WI-6b — opens the AI assistant when configured) |
| `.readerMoreReadAloud`         | nil                  | `ReaderMorePopover` → ReaderContainerView (Feature #60 WI-6c — starts read-aloud / TTS) |
| `.readerMoreToggleAutoTurn`    | nil                  | `ReaderMorePopover` → ReaderContainerView (Feature #60 WI-6c — flips `ReaderSettingsStore.autoPageTurn`) |
| `.readerMoreBookDetails`       | nil                  | `ReaderMorePopover` → ReaderContainerView (opens the `BookDetailsSheet`, feature #61) |
| `.readerMoreShareBook`         | nil                  | `ReaderMorePopover` → ReaderContainerView (Feature #60 WI-6c — presents the system share sheet for the book file) |
| `.readerMoreExportAnnotations` | nil                  | `ReaderMorePopover` → ReaderContainerView (Feature #62 — opens `HighlightsSheet` on the Highlights filter, which carries the export button) |
| `.readerMoreBilingual`         | nil                  | `ReaderMorePopover` → format containers (Feature #56 WI-8 — tap the bilingual row; per-format containers route to `BilingualReadingViewModel.setEnabled(...)`, or to AI Settings when bilingual is `.unavailable`) |
| `.readerMoreReTranslateChapter` | nil                 | `ReaderMorePopover` → `ReaderContainerView` (Feature #56 WI-8/WI-15 — tap the conditional re-translate row; `ReaderContainerView+ReTranslate` constructs the `ChapterReTranslateViewModel`, refreshes the provider-profile list, and raises `ReTranslatePickerSheet`) |
| `.readerBilingualReTranslateApplied` | `["fingerprintKey": String, "unit": TranslationUnitID, "segments": [String]]` | `ChapterReTranslateViewModel` → per-format reader containers (Feature #56 WI-15 — a re-translation succeeded; the active container updates its `BilingualReadingViewModel.applyReTranslateResult(_, for:)` so the open chapter re-renders with the fresh segments) |
| `.readerBilingualDidChange`    | `["fingerprintKey": String, "isEnabled": Bool, "targetLanguage": String]` | `BilingualReadingViewModel` → format renderers + parent reader chrome (Feature #56 WI-7b/WI-10/WI-11 — bilingual toggled on/off, language changed, or a unit's translation became available; renderers re-inject or clear the interlinear translation, the parent `ReaderContainerView` mirrors `isEnabled` + `targetLanguage` into `bilingualActive` / `bilingualLanguage` so the `BilingualPill` and More-menu row paint without crossing the host boundary) |
| `.readerBilingualRetry`        | nil | PDF below-page bilingual panel offline-state Retry button → `PDFReaderContainerView+Bilingual` (Feature #56 WI-13 — host calls `BilingualReadingViewModel.retryUnit(currentUnit)`, scoped to the current page's unit, NOT the whole-book `resetTriggerState()`) |
| `.readerBilingualSectionMaterialized` | `["fingerprintKey": String, "spineIndex": Int]` | `EPUBContinuousScrollCoordinator` (via `EPUBContinuousScrollConfig.onSectionMaterialized`) → `EPUBReaderContainerView+ContinuousBilingual` (Feature #71 WI-7 — a stitched chapter section materialized in EPUB continuous-scroll mode; the modifier drives a SECTION-SCOPED enumerate `bilingualEnumerateJS(spineIndex:)` through the live evaluator, then prefetches + injects THAT section's own unit. Posted with no View capture from the long-lived config closure) |
| `.readerBilingualSectionEvicted` | `["fingerprintKey": String, "spineIndex": Int]` | `EPUBContinuousScrollCoordinator` (via `EPUBContinuousScrollConfig.onSectionEvicted`, fired only on a successful far-side remove eval) → `EPUBReaderContainerView+ContinuousBilingual` (Feature #71 WI-7 — a stitched chapter section was evicted from the continuous-scroll DOM; the modifier drops that section's `EPUBBilingualOrchestrator.blocksBySection` bucket so per-section caches don't accumulate) |
| `.readerOpenAITranslate`       | nil | PDF below-page bilingual panel offline-state "Open AI tab" button → ReaderContainerView (Feature #56 WI-13 — gated on `resolvedAICoordinator.isAIAvailable`; resets `translationViewModel` then sets `aiInitialTab = .translate` + `showAIPanel = true` to open the AI Translate tab cold without a selection) |
| `.foliateBilingualBlocksEnumerated` | `["blocks": [BilingualBlock], "fingerprintKey": String]` | `FoliateSpikeView.Coordinator` → `FoliateBilingualContainerView` (Feature #56 WI-11 — AZW3/MOBI live `bilingualEnumerate` JS message parsed into `[BilingualBlock]`; the container caches blocks on the orchestrator and asks the bilingual VM to prefetch translations for the current unit) |
| `.foliateRequestBilingualEvalJS` | `["js": String, "fingerprintKey": String]` | `FoliateBilingualContainerView` → `FoliateSpikeView.Coordinator` (Feature #56 WI-11 — request the live Foliate WKWebView to evaluate an enumerate / inject / clear JS payload; mirrors the `.foliateRequestAnnotationJSCreate` / `.foliateRequestAnnotationJSDelete` seam) |
| `.foliateRequestSeekFraction`  | `["fraction": Double, "fingerprintKey": String]` | `FoliateBilingualContainerView` (bottom-chrome scrubber) → `FoliateSpikeView.Coordinator` (Bug #260 — the AZW3/MOBI reading-progress scrubber seek; the Coordinator evaluates `readerAPI.goToFraction(<clamped>)`, JS built by pure `FoliateBottomChromeSeek`; dedicated channel mirroring the Bug #239 `.readerNextPage` / `.readerPreviousPage` precedent) |
| `.foliateBookReadyTOC`         | `["toc": [FoliateTOCItem], "fingerprintKey": String]` | `FoliateSpikeView.Coordinator` → `FoliateBilingualContainerView` (Bug #262 — the live AZW3/MOBI TOC source; `book-ready` already carries the parsed `toc`, posted here when non-empty so the container can build Contents. `ReaderTOCFactory.buildTOC` has no Foliate file parser, so this is the only AZW3/MOBI TOC source) |
| `.foliateTOCAvailable`         | `["entries": [TOCEntry], "fingerprintKey": String]` | `FoliateBilingualContainerView` → `ReaderContainerView` (Bug #262 — the `.foliateBookReadyTOC` tree converted via `FoliateTOCConverter` into flat `[TOCEntry]`; the host sets `tocEntries` so the Bug #260 bottom-chrome Contents button lists chapters) |
| `.foliateRequestSeekTarget`    | `["target": String, "fingerprintKey": String]` | `FoliateBilingualContainerView` → `FoliateSpikeView.Coordinator` (Bug #262 — a shared TOC/Notes/Highlight row tap relayed from `.readerNavigateToLocator`; `target` is the locator's CFI (preferred) or EPUB-style href, resolved by pure `FoliateNavSeek.navigationTarget`; the Coordinator evaluates `readerAPI.goTo('<escaped>')`. Mirrors the `.foliateRequestSeekFraction` channel) |
| `.foliateSectionLoaded`        | `["sectionIndex": Int, "fingerprintKey": String]` | `FoliateSpikeView.Coordinator` → `FoliateBilingualContainerView` (Feature #56 WI-11 — Foliate-js `section-load` event surfaced so the bilingual container refreshes its enumerate payload against the freshly-rendered section) |
| `.readerBookTranslationProgressDidChange` | `["fingerprintKey": String, "completed": Int, "total": Int, "phase": String]` | `BookTranslationCoordinator` → reader / library (Feature #56 WI-14 producer — every `BookTranslationProgress` snapshot fires this; the `ReaderTranslateBanner` and `LibraryCardTranslateBadge` observe it filtered by `fingerprintKey`) |
| `.readerBookTranslationTextProviderAvailable` | `["fingerprintKey": String]`, `object: any ChapterTextProviding` | per-format reader containers (TXT/MD/EPUB/Foliate via `ensureBilingualViewModel`) → `ReaderContainerView` (Feature #56 WI-14 — published once the format's `ChapterTextProviding` adapter is built; the host caches it so the Book Details "Translate entire book…" entry point can hand it to `BookTranslationViewModel` without bubbling per-format internals upwards) |
| `.epubFootnoteDetected`        | footnote ref         | EPUB bridge → Container (footnote popup)                |
| `.bookFileStateDidChange`      | `["fingerprintKey","state"]` | LazyDownloadCoordinator (reconcile) → LibraryView (refresh row, feature #47) |
| `.libraryRowTappedWhileNotLocal` | `["fingerprintKey","fileState"]` | LibraryView → BookDownloadSheet (future, #47 WI-6) |
| `.bookDidImport`               | `["fingerprintKey"]`         | BookImporter (after persist, new + duplicate paths) → LibraryView (force-refresh; bug #197) |
| `.openReadingStatsRequested`   | nil                          | `SettingsView` profile-card Stats pill → `SettingsView` itself (feature #67 WI-4 — Settings sheet hosts both the post site and the observer; the observer presents `ReadingDashboardView` as a sheet over the `.modelContext` container's aggregator). Lives in `vreader/Services/SettingsNotifications.swift` (the file is app-shell scoped, not reader-bridge scoped — `ReaderNotifications.swift` is documented as reader coordination only). |

## Shared Reader UI State (Phase R3)

`TextReaderUIState` (`@Observable`) holds UI state shared between TXT and MD containers:

- Highlight/annotation state: `scrollToOffset`, `highlightRange`, `highlightIsTemporary`, `persistedHighlightRanges`, `pendingAnnotationInfo`, `annotationNoteText`
- Pagination state: `pageNavigator`, `pagedCurrentPage`, `autoPageTurner`
- Reading progress: `readingProgress`
- Helper methods: `syncPagedState()`, `updatePagination()`, `updateAutoPageTurner()`, `refreshPersistedHighlights()`

Conforms to `ReaderNotificationHandlerStateProtocol` so `ReaderNotificationModifier` mutates it directly. Note: TXT extraction is partial — `TXTReaderContainerView` still holds some legacy `@State` alongside `uiState` and a follow-up pass would consolidate it.

Format-specific state remains in each container:

- TXT: chunking, chunk offsets, attributed string building, large-file detection
- MD: rendered attributed string (from `MDReaderViewModel`)

## Highlight System (Phase R4a/R4b)

`HighlightRenderer` protocol defines format-agnostic visual operations: `apply(record:)`, `remove(id:)`, `restore(records:)`.

| Adapter                 | Format    | Mechanism                                                                           |
| ----------------------- | --------- | ----------------------------------------------------------------------------------- |
| `TextHighlightRenderer` | TXT, MD   | Mutates `TextReaderUIState.persistedHighlightRanges`                                |
| `EPUBHighlightRenderer` | EPUB      | Generates CSS Highlight API JS via `onInjectJS` callback                            |
| `PDFHighlightRenderer`  | PDF       | Creates/removes `PDFAnnotation` objects; tracks `highlightId → [PDFAnnotation]` map |
| _(none yet)_            | AZW3/MOBI | Selection capture + CFI anchoring landed; `FoliateHighlightRenderer` exists for SVG-overlay JS but is not yet wired as a `HighlightRenderer` adapter. AZW3 highlight create/restore are TODO/no-op placeholders today. |

`HighlightCoordinator` orchestrates the highlight lifecycle:

- `create()` — persists via `HighlightPersisting`, then calls `renderer.apply()`
- `handleRemoval()` — calls `renderer.remove()`, re-fetches, calls `renderer.restore()`
- `restoreAll()` — fetches from persistence, calls `renderer.restore()`

Each container creates its format-specific renderer and coordinator:

- TXT/MD: via `ReaderNotificationModifier` (handles `readerHighlightRequested` / `readerHighlightRemoved`)
- EPUB: coordinator for persistence, renderer for JS injection
- PDF: coordinator + renderer with annotation map (fixes bug #87: highlight deletion)

## Key Design Patterns

1. **Bridge** — UIKit views (UITextView, WKWebView, PDFView) wrapped in `UIViewRepresentable` with Coordinator for delegate/gesture handling
2. **Coordinator** — Complex multi-subsystem flows managed by dedicated coordinator objects (AI, Search, Unified, Highlight)
3. **Protocol injection** — `LibraryPersisting`, `BookImporting`, `PreferenceStoring`, `TTSProviderProtocol`, `HighlightRenderer` enable testing
4. **Actor isolation** — `PersistenceActor` serializes all SwiftData writes; `TXTService` is actor-isolated
5. **Deferred setup** — AI is wired on first AI/TTS invoke. The search service+VM are prepared eagerly on reader open (`ReaderSearchCoordinator.prepareEagerly()`, bug #79) so the first search shows the real field immediately rather than a "Preparing search…" placeholder; the cold SQLite open is `nonisolated` and runs off the MainActor (a detached task) so eager prep never stalls reader open (bug #89). Background full-text *indexing* is still deferred to `setup()` (fired by `ensureSearchReady()` when the search sheet first opens). TXT TOC is also eager on reader open so the chapter progress bar has data in legacy mode.
6. **Observer** — NotificationCenter decouples format-specific readers from chrome and coordinators
7. **Shared state extraction** — `TextReaderUIState` eliminates duplicated `@State` between TXT/MD containers (Phase R3)
8. **Format adapters** — `HighlightRenderer` protocol with per-format adapters decouples highlight lifecycle from rendering mechanism (Phase R4a)
9. **Extension splitting** — Container views and bridges decomposed into `+Highlights`, `+Navigation`, `+Overlays`, `+Helpers` extensions. Core wiring stays in the main file; subviews and action methods live in extensions (Phase R5a/R5b)
10. **Lifecycle composition** — `ReaderLifecycleHelper` owns session tracking, periodic flush, time display, and close/background/foreground sequences. Each format VM composes one instance and delegates shared lifecycle calls (Phase R6)

## Performance Optimizations

| Optimization                      | Target                                      |
| --------------------------------- | ------------------------------------------- |
| Sample-based encoding (8KB)       | Fast TXT open for non-UTF-8 files           |
| Chunked reader (UITableView)      | Large TXT files (>500K UTF-16)              |
| Deferred coordinator setup        | AI wired on invoke; search service+VM prepared eagerly on reader open (off-MainActor cold open, bug #79/#89), indexing deferred to first sheet open. TXT TOC stays eager for the chapter progress bar |
| Persistent FTS5 index             | Skip re-indexing on subsequent opens        |
| Off-main-thread attributed string | Non-blocking TXT/MD rendering               |
| PaginationCache                   | Avoid redundant TextKit layout passes       |
| Non-contiguous layout             | TextKit 1 performance for large documents   |

## File Organization

```
vreader/
├── App/                    # VReaderApp, ContentView
├── Models/                 # SwiftData models, DocumentFingerprint, Locator
├── ViewModels/             # LibraryViewModel, format ViewModels
├── Views/
│   ├── LibraryView.swift   # Library grid/list
│   ├── Reader/             # Reader container, format containers, bridges
│   │   └── Annotations/    # TOCSheet, HighlightsSheet, AnnotationsSheetRoute (feature #62)
│   ├── Annotations/        # AddNoteSheet, AnnotationEditSheet
│   ├── Settings/           # SettingsView, ReaderSettingsPanel
│   └── Stats/              # ReadingDashboardView, StatsTimeWindowBar, StatsPerBookTable (feature #58 WI-6a); StatsCustomRangePicker + state (WI-6b)
├── Services/
│   ├── PersistenceActor.swift
│   ├── TXT/                # TXTService, TXTFileLoader
│   ├── EPUB/               # EPUBParser, EPUBTypes
│   ├── Search/             # SearchService, FTS5, extractors
│   ├── AI/                 # AIService, providers
│   ├── TTS/                # TTSService, providers
│   ├── Backup/             # WebDAV, BackupProvider
│   ├── Import/             # BookImporter
│   ├── Export/             # AnnotationExporter
│   ├── Locator/            # LocatorFactory, position resolution
│   ├── OPDS/               # OPDSClient, OPDSParser
│   ├── Sync/               # SyncService, SyncStatusMonitor
│   ├── AZW3/              # MOBICoverExtractor (native PDB/MOBI header parsing)
│   ├── Foliate/            # FoliateURLSchemeHandler, FoliateMessageParser, FoliateTypes, JS/
│   ├── Unified/            # PaginationCache, TextKit2 helpers
│   └── TextMapping/        # Transforms, offset mapping
└── (no Plugins/ directory — BookSource views are in Views/BookSource/)
```

## Verification Harness (`vreaderUITests/Verification/`)

DEBUG-only XCUITest harness that exercises 13 features' UI surfaces end-to-end
on iPhone 17 Pro Simulator for autonomous device verification. Shipped as
feature #45 in WI-1 (PR #581) → WI-2 (PR #584) → WI-3 (PR #587) → WI-4
(this WI).

```
vreaderUITests/Verification/
├── Helpers/
│   ├── VerificationDebugBridgeHelper.swift    # Wraps vreader-debug:// commands
│   └── VerificationSettingsHelper.swift       # Reader settings panel navigation
├── Feature11EPUBHighlightVerificationTests.swift
├── Feature21PaginatedModeVerificationTests.swift
├── Feature23TXTTocVerificationTests.swift
├── Feature27ReplacementRulesVerificationTests.swift
├── Feature28ChineseConversionVerificationTests.swift
├── Feature29WebDAVVerificationTests.swift
├── Feature31AutoPageTurnVerificationTests.swift
├── Feature34CollectionsVerificationTests.swift
├── Feature35AnnotationsExportVerificationTests.swift
├── Feature36OPDSVerificationTests.swift
├── Feature37PerBookSettingsVerificationTests.swift
├── Feature40TTSSentenceHighlightVerificationTests.swift
└── Feature41TTSAutoScrollVerificationTests.swift
```

### Conventions

- **`test_verify_` method prefix** — XCTest discovers methods starting
  with `test`; the `_verify_` infix preserves the descriptive feature
  slug for grep-friendly mapping (`test_verify_feature_<NN>_<scenario>`).
  The verification harness runs on its own cadence by `-only-testing:
  vreaderUITests/<Class>` invocations or by the named `Verification`
  test plan: `xcodebuild test -scheme vreader -testPlan Verification`
  (Feature #45 WI-6). The plan lives at `TestPlans/Verification.xctestplan`
  and selects exactly 25 `test_verify_*` per-method identifiers across
  the 13 classes listed below; the default plan
  `TestPlans/All.xctestplan` runs the full `vreaderTests` + `vreaderUITests`
  suites on no-flag `xcodebuild test` / `Cmd+U`. Bug #192 (GH #686, 2026-05-15) fixed an earlier
  shape where these methods used a plain `verify_` prefix — they were
  XCTest-invisible and the entire 13-class verification suite had
  been silently no-opping (`Executed 0 tests` + `TEST SUCCEEDED` =
  vacuous pass). The rename to `test_verify_*` made them discoverable.
- **`@MainActor final class XCTestCase`** — verification tests touch
  the SwiftUI element tree which is main-actor-isolated.
- **Seed via `launchApp(seed:)`** — `.warAndPeace` / `.mdTOC` for tests
  that need real content; `.books` for UI-surface-only tests.
- **`XCTSkip` for capability gates** — features gated by
  `FormatCapabilities` (e.g., autoPageTurn on TXT) skip gracefully
  rather than fail.
- **`XCTSkip` for env-var-gated live tests** — WebDAV/OPDS live-server
  tests skip unless `CI_WEBDAV_URL` / `CI_OPDS_URL` are set.
- **RED-proof catalog** at `dev-docs/verification-red-checks.md`
  records evidence that each `test_verify_` method correctly fails when
  its production seam is broken.

### Why no auto-discovery

vreader's default `xcodebuild test` gate runs `vreaderTests/` only
(skipping UITests via `-only-testing:vreaderTests`). The verification
harness is heavier (each test launches the app + drives gestures) and
runs on its own cadence via the verify cron. Auto-discovery from the
default scheme would slow every dev unit-test run by minutes for no
incremental signal.

