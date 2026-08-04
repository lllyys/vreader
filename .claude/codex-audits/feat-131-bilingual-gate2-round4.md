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
session id: 019f545d-5aa1-7c30-8822-76137dc0b24c
--------
user
Gate-2 plan audit ROUND 4 (DECISIVE) for feature #131 (Android bilingual interlinear reading). Read the v4 plan at dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md and verify its resolutions against the LIVE code. This is round 4; the remaining findings were concrete correctness/wiring (not architecture) plus a scope change (folding in the AI-config path). Be DECISIVE: state whether each round-3 finding is now correctly resolved and whether any NEW blocker exists.

The round-3 findings v4 claims to resolve — verify each against live code:
1. H1 (final-chunk drop): v4 specifies 'endExclusive = if (i+1 < document.chunkCount) offsetForChunk(i+1) else document.text.length' with explicit half-open [start,endExclusive) pairs (NOT Kotlin IntRange). Confirm TxtDocument.offsetForChunk clamps out-of-range to the last chunk (reader/TxtDocument.kt ~17) so this fix is necessary + correct; confirm chunkForOffset(segEndExclusive-1) anchoring is off-by-one-safe. Is a one-chunk doc / final-chunk / exact-boundary / EOF anchor now correct?
2. H2 (render breaks per-chunk layout/selection): v4's binding contract is that translations are ADDITIVE LazyColumn items at chunk (line) boundaries and the source chunk Text is NEVER split (source loop byte-identical; a translation item is non-selectable + registers no chunk). Verify against reader/TxtReaderActivity.kt (~1043 items loop, ~1059 onTextLayout, ~1062-1066 registerChunk/unregisterChunk): does this ACTUALLY preserve one-TextLayoutResult + one-selection-registration per source chunk? Is the sentence-granularity rule-51 design-gate call correct (verify vreader-bilingual.jsx BilingualPageContent depicts ONLY paragraph interlinear, and sentence granularity appears only as a setup-sheet control)? Is 'Sentence selection falls back to paragraph render, cache still granularity-keyed' a sound v1 stance?
3. M1 (EPUB direct-block flow): v4 makes EpubBilingualController the SINGLE OWNER of EPUB units (enumeratedBlocks -> cachedDirect else prefetchDirect -> session-token-guarded commit), VM position-driven prefetch is TXT/MD-only. Is this race-free + coherent (no two writers for the same canonical cache row)?
4. M2 (cancellation): dual native CancellationException + typed ChapterTranslationError.Cancelled before generic mapping + a per-unit single-flight prefetchTasks: Map<TranslationUnitId, Job> (cancel-or-join prior). Confirm the iOS parity (vreader/Services/AI/ChapterTranslationService.swift ~359 dual-catch; BilingualReadingViewModel.swift prefetchTasks registry). Sound?
5. M3 (blank model): AiRequest.model = profile.model.ifBlank { profile.kind.defaultModel }. Confirm AiChatViewModel.kt ~61 precedent + that OpenAiCompatibleProvider/AnthropicProvider serialize request.model directly.
6. FOLD-IN (the closed #136): v4 adds WI-AIP (ReaderAiProvidersSheet) reusing the #118 AiProviderListScreen/AiProviderEditSheet/AiSettingsViewModel VERBATIM, pushed inside the bilingual flow, pop-back-on-first-Save, per reader-ai-provider-entry.md Variant A; WI-4b now constructs AiProviderStore in AppContainer (verify VReaderApp.kt AppContainer does NOT construct it today — only a comment ~66). Is this rule-51 compliant (reproduces only what reader-ai-provider-entry.md + vreader-ai-provider-entry.jsx depict, invents no AI-config UI)? Is aiConfigured = active-profile-exists AND its key decrypts-non-empty (NOT profiles.isEmpty), with cipher-failure -> not-ready, correct against AiProviderStore.kt (~34 active, ~108 apiKey/decrypt)? Is 'first Save -> store.setActive(savedId) + pop to bilingual' sound against AiProviderStore.upsert (~81 activeId = cur.activeId ?: id)?
7. Deps now [feat:#132, feat:#134] (no #136), WI count 13. Correct?
8. Any NEW risk/edge-case v4's changes introduce (the additive-item interleaving, the single-owner EPUB controller, WI-4b constructing AiProviderStore, the setActive-on-first-save).

Output findings grouped by severity (Critical / High / Medium / Low), each with file:line evidence, then a FINAL VERDICT line exactly one of: ship-as-is | follow-up-recommended | block-recommended. ship-as-is or follow-up-recommended clears Gate-2 round 4.
codex
I’ll audit the v4 plan against the exact live implementations and committed design artifacts, then trace every round-3 item to a decisive resolved/unresolved judgment. I’ll begin with repository state and the governing architecture/parallel rules, then inspect the cited code paths.
exec
/bin/zsh -lc "git status -sb && sed -n '1,240p' docs/architecture.md && sed -n '1,260p' .claude/rules/48-parallel-execution.md" in /Users/ll/workspace/vreader
 succeeded in 1065ms:
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-cqKtg3GG' (errno=Operation not permitted)
## main...origin/main
 M dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md
 M docs/features.md
?? .claude/codex-audits/feat-131-bilingual-gate2-round2.md
?? .claude/codex-audits/feat-131-bilingual-gate2-round3.md
?? .claude/codex-audits/feat-131-bilingual-gate2-round4.md
?? .claude/codex-audits/feat-136-ai-provider-reachable-gate2.md
?? android/2026-06-29-223908-this-session-is-being-continued-from-a-previous-c.txt
?? dev-docs/security/
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
# 48 — Parallel Execution

## Purpose

Parallelism is an **isolation tool first and a speed tool second**. Use it when it reduces wall-clock time without weakening review, audit, TDD order, or resource ownership. Use it wrong and you trade serial work for merge hell, audit gaps, or simulator flakiness.

This rule applies to: spawning subagents, launching parallel `/fix-issue` runs, splitting work across git worktrees, or running concurrent feature implementations.

## Decision test

Before parallelizing, estimate honestly:

```
expected wall-clock saved  >  setup + review + conflict + resource-contention + failure cost
```

| Cost | What it covers |
|---|---|
| **setup** | Worktree creation, branch hygiene, subagent brief writing, DerivedData warmup |
| **review** | Main-agent integration time when subagent returns |
| **conflict** | Shared file edits (`project.yml`, `docs/features.md`, `docs/architecture.md`) → rebase |
| **resource** | Single simulator, single device, one Codex/test session at a time |
| **failure** | Probability the subagent drifts and needs collapse + redo |

If the answer isn't clearly positive, don't parallelize.

## Hard rules (non-negotiable)

1. **Author/auditor separation**: the agent that writes a plan, code, or PR is never the agent that audits it. (cc-suite running Codex as a separate `codex exec` process satisfies this by accident; preserve the boundary explicitly.)
2. **Hard dependency blocks downstream Gate 3**: if feature B depends on feature A, you cannot start B's TDD until A is `DONE`. Dependency graph in the tracker is the source of truth.
3. **One writer per file/area at a time**: two agents can work the same feature if their write sets are disjoint and explicit. Two agents writing the same file is a merge conflict you will lose.

## Cross-platform write isolation (Android port — feature #103 Phase 0)

The repo now hosts two native apps (iOS at the root, Android under
`android/`). Their *code* is disjoint, but the automation, trackers,
contracts, designs, and release config are **shared, contended** surfaces.
To prevent the `project.pbxproj`-contamination class (PR #1029) from
recurring across the platform split:

- **Android/Kotlin agents MUST NOT touch iOS code** — never `vreader/`,
  `vreaderTests/`, `*.xcodeproj`, `project.yml`.
- **iOS/Swift agents MUST NOT touch Android code** — never `android/`,
  `spikes/`, `buildSrc/`, `gradle/`, root Gradle files, `gradlew*`,
  `gradle.properties`, `*.kt`/`*.kts`, `AndroidManifest.xml`, or any
  Android `res/` tree (the full set the audit classifier gates).
- **Shared surfaces get a single writer per change**: `docs/*` (incl.
  `dev-docs/*` — plans, designs, verification evidence), `contracts/*`,
  `.claude/*`, `AGENTS.md`, root shared docs (`README.md`, `CLAUDE.md`),
  release config. The existing "one writer per area" rule applies; the
  platform split just makes the boundary explicit. A `contracts/`-touching
  change is the canonical multi-platform-impacting edit — give it one owner
  and the versioned contract merge gate (ADR-0001), not two parallel writers.
- The audit gate's code-path classifier (`.claude/hooks/lib/code-paths.sh`)
  decides which PRs need a Codex audit (code vs docs/meta); it's the
  reference for the Android/Kotlin/`contracts/` paths above, but it is a
  boolean gate, not a full ownership taxonomy.

## Strong defaults (negotiable with cause)

- Shared-file edits (status flips, version bumps, doc-sync) require **one owner** or a **final integration pass**. They batch at PR merge time, not in parallel.
- Planning subagents are **read-only by default** — return content/patch for the main agent to apply. Write access only when the subagent has its own worktree.
- Parallel Xcode builds require **explicit simulator/device ownership**. Otherwise contention produces misleading test failures.

## Subagent contract (every spawn must specify)

| Field | Required content |
|---|---|
| **Objective** | One sentence — what deliverable you want |
| **Inputs** | Exact file paths to read; relevant audit-gap context (don't rely on "absorbing" parent conversation) |
| **Allowed writes** | Either "none" (read-only, return content) or a specific path prefix |
| **Forbidden actions** | What it must NOT do (e.g., "no Swift code", "no `xcodebuild`", "no PR") |
| **Output format** | What the return message must contain |
| **Stop condition** | When to return — explicit completion criteria |

A subagent without one of these will drift.

## Subagent failure handling

- Subagent output is **advisory until reviewed** by the main agent.
- If it drifts, **re-brief once** with a narrower task. Don't ask it to self-correct indefinitely.
- If still bad, **collapse to the main agent**. Discard the subagent's output.
- **Never merge or apply** generated code/plan text without main-agent review.

## Decision matrix (gate-by-gate)

| Two work units' state | Approach |
|---|---|
| Both Gate 1 (planning) | Single agent, sequential — context switch is cheap |
| Mixed Gate 1 (planning) + Gate 3 (TDD) | Inline Gate 3 + read-only subagent for Gate 1 (tight brief) |
| Both Gate 2 (plan audit) | Parallel OK — independent Codex sessions, different threads |
| Same feature, Gate 2 of plan + Gate 3 of WI on same plan | **Serialize** — never implement against an unaudited plan |
| Both Gate 3 (TDD) on disjoint files | Worktrees + one agent each |
| Both Gate 3 (TDD) on overlapping files | **Serialize** — one writer per area |
| Same feature, WI-N-1 Gate 5 + WI-N Gate 3 | Parallel only if WI-N doesn't depend on WI-N-1's verification result |
| Both Gate 4 (impl audit) | Parallel OK — independent audits |
| Both Gate 5 (verification) | **Serialize** — single device/simulator |
| Mixed Gate 5 + Gate 3 | Parallel OK — different resources |

## Worktree rules

- Use a worktree when **isolation prevents more cost than it adds**. A 30-min high-risk schema change can deserve one; a 4-hour docs-only plan rarely does.
- Worktrees go under `.claude/worktrees/<feature-or-issue-id>/`.
- After removing a worktree, **clean its DerivedData**: each worktree creates its own (~5GB). The `/fix-issue` skill's multi-issue mode includes the cleanup pass; replicate it.
- Never give two concurrent agents the same worktree. One worktree = one writer.
- The main checkout's working tree must be clean before spawning a worktree-based agent — pre-existing dirty state poisons the agent's git context.

## Worktree cwd discipline (binding for every worktree-isolated agent)

**Failure mode.** When the orchestrator spawns a subagent with `Agent(subagent_type: claude, isolation: worktree, ...)`, the Agent harness creates the worktree but does **NOT** set the spawned subprocess's initial cwd to the worktree path. The agent's Bash tool starts with `cwd = orchestrator's cwd` (typically `/Users/ll/workspace/vreader`, the main checkout). The agent must explicitly `cd "<worktree-path>"` at the start of **every** Bash call. The Bash tool persists cwd between calls in a single session, but a single early call from the wrong cwd writes files to the wrong place — and any later `xcodegen generate` in the contaminated main checkout will fold those stray files into `vreader.xcodeproj/project.pbxproj`, producing a build that fails on any clean clone with "file not found in compile sources".

**Standing precedent.** This class of bug has manifested multiple times:

- **v3.37.18 → v3.37.19 hotfix (PR #1029)**: the WI-7b → WI-8 transition shipped stray `ReaderMoreMenuBilingualTests.swift` references in `project.pbxproj` without the source file being git-tracked. Required a dedicated hotfix PR to restore main.
- **Bugfix #957 agent self-report**: the agent caught itself mid-flow — "my first 4 Bash calls accidentally cd'd into /Users/ll/workspace/vreader (main checkout) instead of staying in the worktree, so the initial RED→GREEN cycle ran in the main repo. I patched this mid-flow by saving the diff to /tmp, reverting the main checkout, and re-applying the patch inside the worktree on the proper branch before committing." Self-rescue, no main contamination shipped, but only because the agent noticed.
- **Bug #241 filing (2026-05-20)**: filed by the verify cron after 3+ recurrences in a single session.

The session-tested workaround: **the briefs from WI-10 onward all included an explicit "cd "<worktree-path>" first" discipline in their preamble, and no contamination recurred for the agents that received that discipline.** This subsection codifies that workaround into a rule.

**Mandate.** Every worktree-isolated agent's brief MUST include a "Critical Operational" preamble that:

1. States the exact worktree path the agent is expected to operate inside.
2. Requires `cd "<worktree-path>"` at the **start of every `Bash` tool call** — not just the first one. (A single later call that omits the prefix can silently land work in the main checkout.)
3. Requires `pwd` confirmation in the first Bash call, before any edit or write, so the agent fails loudly if it's not where it expects to be.
4. Names the consequence explicitly so the agent treats the discipline as load-bearing, not decorative: contaminating main produces broken builds on clean clones and costs a hotfix PR.

This requirement applies to **every** worktree-isolated agent spawn — feature agents, bugfix agents, audit subagents, verification subagents. There is no "small task" exemption; the contamination cost is the same whether the agent writes one file or twenty.

**Copy-pasteable preamble template** (orchestrators: paste verbatim into the brief, substituting the worktree path):

```
## CRITICAL OPERATIONAL — binding

Your worktree path is: <ABSOLUTE-WORKTREE-PATH>

Every `Bash` tool call you issue MUST begin with `cd "<ABSOLUTE-WORKTREE-PATH>"`.
Before your first edit or write, run `pwd` and confirm it prints the worktree
path. If `pwd` does NOT match, stop and report — do NOT attempt to recover by
guessing.

The Agent harness creates the worktree but does NOT set your initial cwd to
it. Your Bash tool starts with cwd = the orchestrator's main checkout
(`/Users/ll/workspace/vreader`). A single Bash call that forgets the `cd`
prefix can write to the main checkout instead of your worktree; a later
`xcodegen generate` then folds stray files into `project.pbxproj` and breaks
the build on every clean clone. Standing precedent: PR #1029 (v3.37.19) was a
hotfix for exactly this pattern; bug #957's agent self-rescued from the same
drift mid-flow.

This is binding for every Bash call, not just the first. Do not skip this in
the interest of brevity.
```

**Orchestrator checklist when spawning a worktree-isolated agent.** Before sending the brief:

- [ ] The brief includes the "Critical Operational" preamble (or an equivalent that names the cwd, the `pwd` confirmation, and the consequence).
- [ ] The worktree path is the **absolute** path, not a relative one.
- [ ] If the brief includes multi-step bash sequences, every step starts with `cd "<worktree-path>"` (compound commands `cd X && Y && Z` are fine — what's not fine is a later Bash call that omits the prefix and assumes the previous call's cwd persists).
- [ ] If the agent reports something that smells like contamination (PR has unexpected `project.pbxproj` references, `git status` in main checkout shows files the agent shouldn't have written), treat the agent's output as suspect and verify by inspecting the main checkout's working tree before merging.

## Lane dispatch (feature #130 — THE sanctioned fan-out mechanism)

Multi-item parallel work runs through **`/dispatch`**
(`.claude/skills/dispatch/SKILL.md`) under the **rule 55** lane contract —
worktree-isolated `implementer` lanes on leased simulators
(`scripts/sim-lease.sh`), write-sets gated by `scripts/check-write-set.sh`,
dependencies gated by `scripts/deps-check.sh`, one global `dispatch` lock
(`scripts/agent-lock.sh`), a serial integration tail with version-at-slot,
and ≤2 lanes (width 1 default). Lane briefs are GENERATED from the dispatch
skill's template — never hand-written — and always embed this rule's
"Critical Operational" preamble verbatim. The subagent contract above now
includes the rule-55 HANDOFF JSON as the required return format for lanes.
Hand-rolled multi-worktree orchestration (the old fix-issue M1–M5 prose) is
dead — see the dispatch skill's "Dropped by design" section.

## Worked examples

**Good — mixed gates, this session's `#46 WI-0a + #48 planning`**:
- Main agent on `feat/46-wi-0a-...` branch implementing Swift code (Gate 3).
- Spawned read-only subagent reading 14 files + writing one markdown plan to `dev-docs/plans/20260503-feature-48-...md` (Gate 1).
- No file-write overlap. Subagent's output reviewed and integrated by main agent.

**Good — `/fix-issue` multi-issue mode**:
- N issues, N worktrees, N agents. Each runs its own pipeline. Cleanup pass removes stale DerivedData after each worktree is removed.

**Bad — would have been wrong**:
- `#46` and `#47` in parallel: hard dependency (`#47` needs `#46`'s blob storage layout). Tracker says so explicitly. Parallelizing would have wasted `#47`'s implementation.

**Bad — would have been wrong**:
- Spawning a subagent with prompt "implement WI-0a, you have full context" — context absorption fails; the subagent will misremember field names and produce uncompilable code.

## What this rule does NOT cover

- Per-PR parallelism (CI runs across PRs) — handled by the CI infrastructure, not this rule.
- Agent-to-agent communication mid-flight — out of scope; subagents are fire-and-forget with single return.

exec
/bin/zsh -lc "rg -n \"H1|H2|M1|M2|M3|FOLD|WI-AIP|WI-4b|Dependencies|dependency|13 work|endExclusive|chunkForOffset|Sentence selection|EpubBilingualController|prefetchTasks|CancellationException|AiRequest.model|ifBlank|ReaderAiProvidersSheet|aiConfigured|setActive|#136|#132|#134\" dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md && rg --files android vreader dev-docs/designs | rg '(TxtDocument|TxtReaderActivity|AiChatViewModel|Provider|AiProviderStore|VReaderApp|BilingualReadingViewModel|ChapterTranslationService|vreader-bilingual|reader-ai-provider-entry)'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
3:**Feature number assumption:** highest active row in `docs/features.md` is `#136` (now CLOSED, see below); `#131` is a landed `PLANNED` row (`GH: #1923`). The orchestrator adjusts if a row is claimed first.
8:- **The in-reader AI-config surface (folded in from the closed #136):** `dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md` (the CANONICAL **Variant A** decision + navigation model, lines ~39–76, ~110–134) and `.../vreader-ai-provider-entry.jsx` (`AIProvidersSheet`, `BilingualEngineStrip`, `NavSheet`). `reader-ai-readiness.md` (iOS #82) is **informational only** — its 4-gate readiness (feature flag + consent manager + provider + key) is iOS-specific and **implementation-deferred**; Android #118 has no feature flag and no consent manager, so the Android readiness gate is provider+key only (see §"AI-config reachability").
12:**Status:** Gate-1 draft **v4** (2026-07-12) — Gate-2 round-3 (block-recommended) findings resolved AND the AI-config path folded in (#136 closed). Awaiting Gate-2 round-4 audit.
18:The engineering questions are (a) **which render host(s)** get true interlinear, (b) **what the real TXT/MD segmentation unit is** (there is no chapter model — round-2 H1), (c) **how the enabled render preserves the live per-chunk layout/selection model** (round-3 H2), and (d) **where the entry point AND the AI-config path live**. The render-host feasibility was settled in v2 (EPUB-primary via Readium `EpubNavigatorFragment.evaluateJavascript`; TXT/MD Compose; AZW3/PDF deferred) and was **CONFIRMED correct by the Gate-2 round-2 audit** — it is not revisited here. This v4 resolves the round-3 findings that concern *how the pipeline maps to real code* and folds in the AI-config reachability that the design proved is inseparable from the bilingual flow:
21:- **TXT/MD unit (round-2 H1)** — `TxtDocument` has NO chapter model; it is line-based ≤4000-char chunks addressed by UTF-16 offset. v4 defines **document-global units with segment UTF-16 ranges produced ONCE by the segmenter** and renders source/translation pairs from those same ranges, with the **round-3 H1 final-chunk math fix** and the **round-3 H2 additive-item render contract** (§2, §3).
22:- **Entry point** — the design puts the toggle in the **More-menu** (`vreader-more.jsx`; the live `MoreActionId.BILINGUAL` id is already reserved, and `MoreRow.Toggle` carries `on`/`onToggle` — `reader/more/MoreRow.kt:24,56–63`) + a **top-chrome pill** (`vreader-reader.jsx`). Both landed as box-F sub-features **#132 (top chrome) and #134 (More menu), now VERIFIED** — the entry wiring targets them directly (§4).
23:- **AI-config path (folded in — #136 CLOSED)** — the ONLY designed Android AI-config reader surface is the **Variant A scoped "AI Providers" sheet pushed inside the bilingual flow**, reached from the bilingual engine strip's "Set up"/"Change…" button (`reader-ai-provider-entry.md`). #131 now owns it end-to-end (§"AI-config reachability", WI-4b + WI-AIP + WI-9).
29:**Two hosts, in dependency order:**
31:1. **EPUB (Readium `EpubNavigatorFragment`) — PRIMARY.** Interlinear via `evaluateJavascript` (enumerate leaf blocks → inject translation DOM nodes → clear on teardown/reflow), mirroring iOS `EPUBBilingualOrchestrator`. Gated by **WI-0 (a Readium bilingual spike with enforceable go/no-go thresholds + a navigator-race contract — round-2 M1)** before the EPUB render WI (WI-7b) is built.
32:2. **TXT/MD (Compose `TxtReaderActivity`) — INCLUDED.** No WebView; deterministically Compose-testable. Renders translations as **additive `LazyColumn` items at chunk (line) boundaries** — the source chunk `Text` is never split (round-3 H2), from **document-global segment ranges** (round-2 H1).
38:### The TXT/MD segmentation unit + render mapping (round-2 H1 + round-3 H1/H2 — the core corrections)
40:**Verified against live code:** `TxtDocument` (`reader/TxtDocument.kt`) exposes only `text: String`, `chunkCount` (`starts.size`, TxtDocument.kt:14), `offsetForChunk(index)` (TxtDocument.kt:17), `chunkForOffset(offsetUtf16)` (TxtDocument.kt:23), `textForChunk(index)` (TxtDocument.kt:36) — line-based ≤4000-char chunks over UTF-16 offsets against the RAW text (no line-ending normalization). It has **no chapter/section concept**.
49:- The whole `.txt`/`.md` is treated as **one translation document**. The **segmenter runs once over `TxtDocument.text`** (the full raw backing string) and emits, per segment, its **half-open UTF-16 span `[start, endExclusive)`** against that same backing string (the segmenter's `paragraphRanges(text): List<IntRange>` / `sentenceRanges(text): List<IntRange>` — the range-returning peers of `paragraphs`/`sentences`; iOS precedent `ChapterSegmenter.sentenceRanges(in:)` at `ChapterSegmenter.swift:78`, returns `[Range<Int>]`). These ranges are the SINGLE source of truth used by BOTH the translate side and the render side, so the two segment identically **by construction** (they read the same array). Ranges are stored/compared as explicit `(start, endExclusive)` integer pairs (see the H1 fix below), NOT re-derived on the render side.
50:- **Unit granularity for TXT/MD is the whole document, sub-batched for cache/prefetch by a deterministic "unit window."** To avoid translating a 14 MB book at once (and to keep cache rows bounded), segment ranges are grouped into fixed **unit windows** of contiguous segments (window size a build-time constant; it does not change the 1:1 contract). Each window is a `TranslationUnitId(kind = txtDocSegmentWindow, value = windowIndex)` — a document-global index, NOT a chunk index. `unitContaining(charOffsetUTF16)` maps the reader's saved offset → the segment whose range contains it → its window index (via a precomputed segment-start binary search, the same shape as `TxtDocument.chunkForOffset`, TxtDocument.kt:23–33). `unitAfter(unit)` = next window index or null at document end.
52:#### H1 fix (round-3 High-1) — final-chunk source span math (BINDING)
57:val endExclusive = if (i + 1 < document.chunkCount) document.offsetForChunk(i + 1) else document.text.length
58:// chunk i source span is the HALF-OPEN [document.offsetForChunk(i), endExclusive)
61:- All chunk-span and segment-span computations use **explicit half-open `[start, endExclusive)` integer pairs**, NOT ambiguous Kotlin `IntRange` (an `IntRange` is inclusive-inclusive and `range.last` for an empty/at-EOF segment is a footgun). A segment's "end offset" for anchoring (below) is its `endExclusive`; the chunk that "contains a segment's end" is `document.chunkForOffset(segEndExclusive - 1)` when `segEndExclusive > segStart`, clamped to `[0, chunkCount-1]` (an empty segment is dropped by the segmenter and never anchored).
64:#### H2 fix (round-3 High-2) — the enabled render contract (BINDING; preserves the live per-chunk model)
70:> **Translations are ADDITIVE `LazyColumn` items rendered at CHUNK (line) boundaries. A source chunk's `Text` is NEVER split.** The existing `items(count = document.chunkCount, key = { it })` source loop stays **byte-identical to today** — same one `Text`, same one `TextLayoutResult`, same one `registerChunk(i, …)`/`unregisterChunk(i)`, same `highlightSpan(i)`/`washesForChunk(i)`/`selectionForChunk(i)` wiring. Each **translation is a NEW, separate `LazyColumn` item** inserted **AFTER** the source chunk that contains the segment's **end** offset (`document.chunkForOffset(segEndExclusive - 1)`, per the H1 math). The translation item is a plain muted `Text` (accent left-border, `fontSize*0.88`, CJK/RTL styling per `BilingualPageContent`) that is **non-selectable and registers NO chunk** — it does not call `registerChunk`, contributes no `TextLayoutResult` to the selection controller, and does not perturb any source chunk's UTF-16 offsets or index `i`.
75:2. Look up the translations **anchored** to chunk `i` = every segment whose end resolves to `chunkForOffset(segEndExclusive - 1) == i`, in segment order, from the shared range array. For **paragraph** granularity there is at most one such translation per anchor chunk in the common case (a paragraph's translation renders after the paragraph's last line-chunk). For **sentence** granularity, when several sentences END in the same line-chunk (one line, multiple sentences), their translations are **grouped** and rendered as a stack of muted items after that chunk, in sentence order.
76:3. Emit each anchored translation as its own additive item (keyed by the segment's `(start, endExclusive)` so a granularity/language change re-keys cleanly).
80:- **Enabled-mode tests (WI-8 connected + WI-7a Compose, BINDING):** with bilingual ON — (a) each source chunk's **selection registration is UNCHANGED** (same `registerChunk(i, …)` count and coordinates as OFF; a translation item registers nothing); (b) **highlights/annotation washes/read-aloud wash still key off the source chunks** at the correct offsets (a translation item between chunks does not shift them); (c) a **translation item is non-selectable** and does not perturb source offsets (selecting across the boundary selects source only); (d) **MD source mapping** — the markdown renderer (`mapper.renderedText(i)`, TxtReaderActivity.kt:1049) still owns the source chunk render; the translation item is plain muted text; (e) **paragraph-spanning-many-chunks** renders exactly ONE translation (after the paragraph's last chunk), never per-line; (f) final-chunk/one-chunk anchors render (H1).
82:- **Granularity depiction (round-3 H2 — rule-51 call, stated with evidence):** `vreader-bilingual.jsx` `BilingualPageContent` (lines 200–277) is a **paragraph-interlinear** renderer: it maps `page.paragraphs.map(...)` and renders **one source `<p>` followed by ONE translation `<p>`** per paragraph. **Sentence-granularity interlinear (a translation after the line where each sentence ends, grouped when several sentences share a line) is NOT depicted anywhere** — sentence granularity appears ONLY as an option in the `BilingualSetupSheet` Granularity segmented control (`vreader-bilingual.jsx:85–99`), never in the renderer. **Call:** paragraph granularity IS the depicted interlinear pattern and **ships in v1**. The **sentence-granularity render is a rule-51 design gate** (named precisely below) — v1 ships the setup-sheet Granularity control (both options selectable, as depicted) but the **renderer implements only the depicted paragraph pattern**; selecting Sentence in v1 falls back to the depicted paragraph interlinear (the granularity is still carried in the cache key so no wrong-shape row is served) until the sentence-interlinear render is designed. This keeps rule 51 (implement only what is depicted) while shipping the depicted paragraph parity. (The additive-item render contract above is written to accommodate sentence grouping so the gate, once designed, is a render-only follow-up.)
86:This closes H1 (no dropped final-chunk translations), H2 (per-chunk layout/selection preserved; source `Text` never split), and Low-2 (correct chunk semantics).
88:### AI-config reachability — FOLDED IN (#136 CLOSED; Variant A owned by #131)
92:The Gate-2 audits + the two design-notes proved the ONLY designed Android AI-config reader surface is **Variant A** (`reader-ai-provider-entry.md`, CANONICAL): a **scoped "AI Providers" sheet pushed _inside_ the bilingual sheet**, reached from the bilingual engine-strip's "Set up"/"Change…" button. The design explicitly **rejected** a standalone entry (there is NO designed standalone More-menu "Configure AI" row), a full-Settings deep-link (alternative B), and inline expansion (alternative C). So AI-config reachability is **NOT separable** from the bilingual flow — the #136 spin-out is **CLOSED (GH #1976, not-planned)** and **#131 now owns it end-to-end** (user decision 2026-07-12).
102:     ReaderAiProvidersSheet  [nav bar: ‹ Bilingual · "AI Providers"]
114:- **"Change…"** (already-configured strip) opens the **SAME** `ReaderAiProvidersSheet`, populated, current provider checked.
117:**Android readiness gate (BINDING — round-3/round-2 H3 + the #136-audit High-3 lesson):** `aiConfigured` on the engine strip is derived by `BilingualAiReadiness.resolve(snapshot)` = **an ACTIVE profile exists AND its API key decrypts to non-empty.** Deriving from `profiles.isEmpty()` alone is **WRONG**: the store keeps a separate `activeId` that can be **null with profiles present** (`AiProviderSnapshot.active = profiles.firstOrNull { it.id == activeId }`, AiProviderStore.kt:34–36), and key usability depends on **decrypting the active profile's token** (`apiKey(profile) = cipher.decrypt(profile.encryptedApiKey)`, AiProviderStore.kt:108). A cipher/keystore failure maps to **not-ready, never a crash** (the resolve wraps the decrypt in `runCatching`). **Note:** the iOS Variant A design-note (`reader-ai-provider-entry.md:172–174`) derives `aiConfigured` from `providers.isEmpty == false`, and iOS #82 (`reader-ai-readiness.md`) adds a 4-gate readiness (flag + consent + provider + key). **Android has NO consent manager and NO feature flag** (#118 has neither — confirm during build); the Android gate is exactly what #118 enforces = **provider (active) + key (decrypts non-empty)**. We do NOT invent a consent/flag gate.
123:- `bilingual/TranslationUnitId.kt` — `data class TranslationUnitId(kind, value)` with `enum Kind { epubHref, foliateHref, txtDocSegmentWindow, mdDocSegmentWindow, pdfPageRange }`; `storageKey = "${kind.name}:$value"`. TXT/MD kinds are **document-global segment-window indices** (H1), NOT chunk indices. v4 uses `epubHref` + `txtDocSegmentWindow`/`mdDocSegmentWindow`; others reserved so the cache-key format never breaks. *(Assumption: iOS's exact Kind case names for the TXT/MD variants; only the `storageKey` string format is load-bearing for the cache contract, and that is preserved.)*
124:- `bilingual/TranslationGranularity.kt` — `enum { paragraph, sentence }`. (Design's Granularity control; sentence-render is design-gated per H2.)
126:- `bilingual/ChapterSegmenter.kt` — **NEW file (no existing Android segmenter — verified).** Port of iOS `ChapterSegmenter`: `paragraphs(text)` / `sentences(text)` **plus the range-returning peers `paragraphRanges(text): List<IntRange>` / `sentenceRanges(text): List<IntRange>`** (half-open UTF-16 spans against the input string — iOS `sentenceRanges(in:)` precedent). Ranges are exposed as explicit `(start, endExclusive)` pairs to the render side (H1). CJK-aware sentence enumeration (`。！？` vs Latin). Pure.
130:- `bilingual/TxtChapterTextProvider.kt` — provider over `TxtDocument` + the segmenter's range array (H1). Builds the document-global segment `(start, endExclusive)` ranges once, groups them into windows, resolves `unitContaining` via a segment-start binary search over `charOffsetUTF16`. MD source = raw markdown segment text.
131:- `bilingual/EpubChapterTextProvider.kt` (WI-0-gated shape) — provider over the Readium `Publication` reading order; `units()` = spine hrefs, `unitContaining` = the locator's href (from `EpubNavigatorFragment.getCurrentLocator()`), `sourceSegments(unit)` = the DOM-enumerated block texts (the render's OWN enumeration, for direct-block 1:1 — H2). Its render-side collaborator is `EpubBilingualJs`.
133:- `bilingual/ChapterTranslationService.kt` — the iOS-parity service (full divergence-recovery surface, round-2 H2):
136:  - `translate(bookKey, unit, sourceText, targetLanguage, providerProfile, granularity, bypassCacheRead=false)` — segment → chunk → per-chunk `AiClient.chat` one-shot → `decode` → per-segment fallback → per-chunk graceful degrade (Bug #330) → cache-write only on full success (`sourceParagraphCount = segments.size`). **Cancellation:** maps BOTH native `CancellationException` AND typed `ChapterTranslationError.Cancelled` to `Cancelled` (mirrors iOS `ChapterTranslationService.swift:359–364`); `ensureActive()` between chunks AND immediately before the Room write.
139:- `bilingual/ChapterTranslationPrefetcher.kt` — resolves the active profile from one `AiProviderStore.snapshot()` (`snapshot.active`), decrypts via `store.apiKey(profile)` (snapshot-consistent, AiProviderStore.kt:108), builds an `AiClient` via an **injected factory param** (below), cache-first then translate. Adds the direct-block peers (H2):
143:  - **`AiRequest` construction (round-3 M3 fix, BINDING):** `model = profile.model.ifBlank { profile.kind.defaultModel }` — matches `AiChatViewModel.kt:61`; both wire clients serialize `request.model` **directly** (`put("model", request.model)` in `OpenAiCompatibleProvider.kt:39` and `AnthropicProvider.kt:37`), so a blank `profile.model` would send an empty model. Full request: `AiRequest(model = profile.model.ifBlank { profile.kind.defaultModel }, messages = …, temperature = profile.temperature, maxTokens = profile.maxTokens, system = …)`. A **blank-model regression test** asserts the fallback is applied.
150:- `bilingual/BilingualViewModel.kt` — `StateFlow<BilingualUiState>` with `enabled`, `targetLanguage`, `granularity`, `needsSetupSheet`, `aiConfigured`, `translationsByUnit`, `inFlightUnits`, `unavailableUnits`, `errorUnit`. Setters + `dismissSetupSheet`, `onPositionChanged(charOffsetUTF16)`, `retryUnit(unit)`, and the EPUB direct-block entry `onEpubBlocksEnumerated(unit, blocks)` (M1, below). Generation/epoch-guarded prefetch (current + next unit); a **per-unit single-flight job registry** (M2); dual-cancellation handling (M2). Port of iOS `BilingualReadingViewModel` (`prefetchTasks: [TranslationUnitID: Task]`, `BilingualReadingViewModel.swift:141`) + `+Prefetch`. Split to `BilingualPrefetchController.kt` if it nears ~300 lines. No `style` field.
154:- `data/ChapterTranslationEntity.kt` — `@Entity(tableName="chapter_translations", indices=[Index("bookKey")], foreignKeys=[FK→books.fingerprintKey ON DELETE CASCADE])`. **`@PrimaryKey val lookupKey: String`** (Room requires a PK; project pattern `@PrimaryKey` + `@Upsert`, verified `BookEntity`/`BookDao`). `lookupKey` = `bookKey|unitStorageKey|targetLanguage|promptVersion`. Columns: `bookKey`, `unitStorageKey`, `targetLanguage`, `promptVersion`, `translatedJson`, `sourceParagraphCount`, `createdAt`. Mirrors iOS `ChapterTranslationRecord.lookupKey` (`book|unit|lang|prompt`, profile-agnostic — Bug #342). `sourceParagraphCount` is load-bearing for H2 (stores the enumerate's count on the `translatePreSegmented` path so `cachedTranslation(expectedSegmentCount:)` restores).
158:**Cache-identity (reconciled with iOS parity):** the 4-part key `book|unit|lang|promptVersion` is profile-AGNOSTIC / style-agnostic (Bug #342). Style is descoped (§3) so no `s=` component. **Granularity IS user-selectable**, carried in `promptVersion` as an effective composite: `promptVersion = "bilingual-v1|g=${granularity}"` (a paragraph vs sentence translation is a different cache row — closes the iOS #344 "sentence silently ignored" class by construction; also means the H2 sentence design-gate never serves a paragraph row as sentences). A granularity change cancels in-flight jobs, bumps the VM generation, clears shaped `translationsByUnit`, and forces a correctly-keyed re-fetch (WI-6).
164:- `bilingual/BilingualSetupSheet.kt` — reproduces `vreader-bilingual.jsx`'s `BilingualSetupSheet` (lines 27–156) EXACTLY: header; a preview strip (`BilingualPreview`); a language grid over `BILINGUAL_LANGS` (glyph tiles, selected accent); a **Granularity** segmented control (Paragraph "Translate after each ¶" / Sentence "Translate after each sentence"); a **Translation engine** strip (configured: "Claude · with this book's context" + "Change…"; unconfigured: "No AI provider configured" + "Bilingual mode needs an AI provider to translate." + "Set up"); the "Turn on bilingual mode" CTA. **No Style control, no provider/model card, no term-overrides toggle, no cost footer** (those belong to the `vreader-ai-android.jsx` sheet, not reproduced — §3). The `aiConfigured` flag comes from `BilingualAiReadiness.resolve`. The "Set up"/"Change…" CTA routes to `ReaderAiProvidersSheet` (wired in WI-9).
165:- `bilingual/ReaderAiProvidersSheet.kt` — **NEW (folded in; the Android analog of iOS `ReaderAIProvidersView`).** The Variant A scoped in-reader AI Providers sheet, reproducing `vreader-ai-provider-entry.jsx` `AIProvidersSheet` + `NavSheet` (nav bar `‹ Bilingual` leading + centered "AI Providers" title). It hosts **ONLY the provider list** — nothing else from settings. It **reuses the #118 `AiProviderListScreen` (list, empty + populated states) and `AiProviderEditSheet` (the canonical add/edit modal) VERBATIM**, driven by the #118 `AiSettingsViewModel` (`listState`, `editState`, `openAdd/openEdit/save/setActive`, verified `AiSettingsViewModel.kt`). Behavior per the nav model:
167:  - **Add provider** presents `AiProviderEditSheet` unchanged; **on the first Save** the new provider becomes active/the bilingual engine and the stack **pops all the way back** to the bilingual sheet with the engine strip now reading "Claude · configured / Change…". (First-provider-active is already the store's behavior — `AiProviderStore.upsert` sets `activeId = cur.activeId ?: id`, AiProviderStore.kt:81; the sheet additionally calls `store.setActive(savedId)` on the first-Save-from-bilingual path so the freshly-saved provider is the engine even if others existed.)
169:  - "Change…" opens the SAME sheet, populated, current provider checked (tapping a row → `setActive`).
171:- `bilingual/BilingualInterlinearBody.kt` — the Compose render surface for the **TXT/MD host ONLY** (round-2 M2). Emits the **additive translation `LazyColumn` items** per the H2 render contract (source chunks unchanged; translation items after the anchor chunk): muted `Text`, accent left-border, `fontSize*0.88`, CJK font for cjk scripts, RTL handling for Arabic (per `BilingualPageContent`, `vreader-bilingual.jsx:200–277`). Consumes the host-neutral `BilingualRenderState` DTO. Loading state ("Translating chapter… N%" + per-segment dim), error state ("Couldn't translate" + Retry), partial/offline (`unavailableUnits`): source-only silent fallback (iOS Decision 2). **NOT the EPUB render surface.**
172:- `bilingual/BilingualRenderState.kt` — the host-neutral state DTO shared by the Compose body and the EPUB adapter (round-2 M2): per-unit `{ segments: List<String>?, phase: Loaded|Loading(fraction)|Error|SourceOnly }`. Compose and EPUB share the state/value types, NOT the composable body.
173:- `bilingual/EpubBilingualJs.kt` (WI-0-gated) — the EPUB render surface (round-2 M2). Pure Kotlin builder producing JS strings for `navigator.evaluateJavascript(...)`: `enumScript` (enumerate current-resource leaf blocks → JSON `[{id,text}]`), `injectScript(blockId, translationText)` (translation DOM node after the block; CSP-safe: `textContent`/`createTextNode`, never `innerHTML` string-concat; RTL/CJK via class + injected `<style>`), `clearScript()` (idempotent removal). Escaping done in Kotlin (JSON-encode every interpolated string). No Compose. Consumes `BilingualRenderState`.
174:- `bilingual/EpubBilingualController.kt` (WI-0-gated) — **the single owner of EPUB units (M1, below).** The runtime actor that serializes enumerate→(cache-restore|translate)→inject/clear against the navigator using WI-0's chosen mechanism (a single mutex OR a monotonic navigator-session token); checks the session token after every suspended JS/AI call; clears BEFORE publication teardown; re-applies on the identified production re-apply signal.
175:- `bilingual/BilingualPill.kt` — the `EN ↔ 中` reader-top-chrome pill (per `vreader-reader.jsx` + `vreader-bilingual.jsx` `BilingualPill`:282–305). Rendered by #132's top chrome; #131 provides the composable, #132's surface hosts it (§4).
179:The **`EpubBilingualController` is the SINGLE OWNER of EPUB units**; the VM's position-driven regular `prefetch` path is **TXT/MD-only**. Concretely, an EPUB position change routes THROUGH the controller (the VM does not run `prefetch(unit)` for `epubHref` units), so the **controller is the sole writer** of an EPUB unit's canonical cache row and its `BilingualRenderState`/`translationsByUnit` entry — the position-driven regular prefetch and the direct-block path can never both write the same canonical cache row. The control flow (every suspended step session-token-guarded):
202:- **Dual-cancellation across the service/VM boundary:** both the service AND the VM handle **BOTH** native `CancellationException` **AND** the typed `ChapterTranslationError.Cancelled` **before** generic error mapping — matching iOS `ChapterTranslationService.swift:359–364` (which catches `is CancellationError` and `ChapterTranslationError.cancelled` separately, both re-throwing `cancelled`). A cancelled stale request MUST NOT surface as `errorUnit` (it is discarded).
203:- **Per-unit single-flight job registry (VM):** a `prefetchTasks: MutableMap<TranslationUnitId, Job>` (iOS `prefetchTasks: [TranslationUnitID: Task]`, `BilingualReadingViewModel.swift:141`, cancelled/removed on disable/unit-change at :165). A NEW request for a unit **cancels-or-joins** the prior job (a stale prior is cancelled and awaited so it cannot run overlapping translations or Room writes), keyed by unit. Rapid retry/navigation cannot run overlapping translations for the same unit. `retryUnit(unit)` goes through the same registry. Tests: a mid-flight cancel discards (no `errorUnit`, no partial cache row); a rapid re-trigger for the same unit does not double-write.
208:- `reader/TxtReaderActivity.kt` — own a `BilingualViewModel`; collect state; render translations as **additive items after the anchor chunk in the existing `items(count = document.chunkCount, key = { it })` loop (TxtReaderActivity.kt:1043), source chunks byte-unchanged (H2)**; on position change call `vm.onPositionChanged(charOffsetUTF16)`. Strictly gated to `originalFormat ∈ {txt, md}`; disabled = body byte-unchanged (overlay-only). **Owned by #129 (VERIFIED, merged) — a straight edit, rule 48 one-writer-per-file satisfied.**
209:- `reader/ReaderActivity.kt` (Readium EPUB) — WI-0-gated: attach `EpubBilingualController` to `navigator.evaluateJavascript`; re-apply on the identified production re-apply signal; clear on teardown BEFORE publication teardown. `navigator: EpubNavigatorFragment?` is the verified live field (ReaderActivity.kt:110).
210:- `reader/chrome/ReaderChromeScaffold.kt` — extend `readerMoreRows(...)` (currently supplies only `MoreActionId.DETAILS` + `SHARE`, ReaderChromeScaffold.kt:255–258) to ALSO supply the **`MoreRow.Toggle(id = MoreActionId.BILINGUAL, on = enabled, onToggle = …)`** row (or `MoreRow.Disabled` "Configure AI provider first" when not configured — `MoreRow.Disabled` exists for exactly this, MoreRow.kt:65–72). Threaded via new nullable params so #132/#134-only callers stay valid (the scaffold's established nullable-default pattern). This is the WI-9 entry-wiring edit.
211:- `VReaderApp.kt` / `AppContainer` — **provide `AiProviderStore` INTO `AppContainer` itself** (it is NOT provided today — verified, only a comment names it at VReaderApp.kt:66) using the #116 `KeystoreSecretCipher` + a DataStore under the same convention as `readerSettingsStore`, PLUS provide `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, an `AiSettingsViewModel` factory (for the Variant A sheet), and a `BilingualViewModel` factory. **Extracted into the shared DI WI (WI-4b).** No `feat:#136` dependency remains — #131 owns the `AiProviderStore`-into-`AppContainer` wiring.
213:**NOT modified:** `reader/chrome/ReaderBottomChrome.kt` gets **no** bilingual/Translate slot — the design's entry is the More-menu toggle (#134) + the top-chrome pill (#132), NOT a bottom-chrome slot. `ReaderBottomChrome`'s existing `extraSlot` is untouched.
221:- **Sentence-granularity interlinear RENDER** — not depicted (H2); design-gated. v1 renders the depicted paragraph pattern; Sentence selection falls back to paragraph render (cache still granularity-keyed).
230:**How iOS does interlinear:** iOS renders EPUB/AZW3 in a WKWebView it fully controls. `EPUBBilingualOrchestrator` injects JS that (1) enumerates leaf blocks posting `[{bid,text}]` to Swift, (2) after translation injects a translation node after each block. TXT/MD render in a text path where the renderer interleaves translation runs. The mechanism = **the app inserts translation nodes between source nodes** — which is exactly the Android additive-item contract (H2) for TXT/MD and the DOM-inject contract for EPUB.
234:**WI-0 — Readium bilingual spike (gates WI-7b; round-2 M1):** a throwaway harness that, against a real EPUB on the emulator, must PROVE each go/no-go criterion: (a) enumeration deterministic + idempotent with stable node IDs (repeat apply = no duplicate nodes); (b) clear wins over every older inject (a late inject checks the session token and no-ops); (c) recreation restores from cache for every case (href away/back, same-href `submitPreferences` reflow, internal page-fragment recreation, activity recreation) via `cachedDirect(expectedCount)` (zero provider calls) with an identified PRODUCTION re-apply signal per case; (d) locator/visible-source preservation across injection (stated permissible pagination delta); (e) enumerated block count vs segmenter count measured — divergence → the direct-block path (`prefetchDirect`/`cachedDirect`, H2) is the recovery, proven end-to-end. **Race contract:** single actor/mutex OR monotonic navigator-session token; token/mutex check after every suspended JS/AI call; clear before publication teardown. **No deterministic re-apply signal for a recreation case (c) = explicit NO-GO** → EPUB drops to a tracked follow-up, box D ships **TXT/MD-only** with the honest reason (a specific spike finding), never the false "requires a fork."
241:5. **One `BilingualInterlinearBody` per chunk (v2)** — REJECTED (round-2 H1): a chunk is not a segment.
242:6. **A Compose body as the EPUB render surface (v2)** — REJECTED (round-2 M2): Compose cannot render inside Readium's WebView.
243:7. **Splitting a chunk's source `Text` into per-segment `Text` nodes to interleave translations (v3)** — REJECTED (round-3 H2): breaks the live one-`TextLayoutResult` + one-selection-registration-per-chunk model. Replaced by additive `LazyColumn` items at chunk boundaries, source `Text` never split.
244:8. **Deriving `aiConfigured` from `profiles.isEmpty()` (the iOS Variant A note's derivation)** — REJECTED for Android: `activeId` can be null with profiles present, and key usability needs the active profile's token to decrypt (H3). Android uses `BilingualAiReadiness.resolve` = active-profile + decrypts-non-empty.
245:9. **Spinning AI-config reachability out as a separate feature #136** — REJECTED / CLOSED (2026-07-12): the design proved the ONLY designed Android AI-config reader surface is bilingual-coupled Variant A; there is no designed standalone entry, so it is not separable. #131 owns it.
267:- **Single-flight job registry**: iOS `prefetchTasks: [TranslationUnitID: Task]` (`BilingualReadingViewModel.swift:141`) — ported as `prefetchTasks: Map<TranslationUnitId, Job>` (M2).
268:- **Entry point via #132/#134 (VERIFIED)**: the More-menu bilingual toggle (`MoreActionId.BILINGUAL` reserved; `MoreRow.Toggle`/`MoreRow.Disabled`) + top-chrome pill are landed; #131 mounts the pill + wires the toggle (§4).
272:**13 WIs/PRs (round-3 Low-1 fix — corrected count):** the list is exactly **WI-0, WI-1, WI-2, WI-3, WI-4a, WI-4b, WI-5, WI-6, WI-7a, WI-7b, WI-AIP, WI-8, WI-9** = **13 WIs**. (v3 had 12: WI-0,1,2,3,4a,4b,5,6,7a,7b,8,9. Folding in the Variant A "AI Providers" sheet adds **WI-AIP**, making 13. The prior "11 WIs" claim in the plan header and `docs/features.md` was wrong on two counts and is corrected here.) Each WI = one PR. Build order: **foundation/cache → service/direct-block APIs → shared DI/factory (incl. `AiProviderStore` in `AppContainer`) → VM state/prefetch → host-specific renderers (TXT/MD + EPUB) + the Variant A AI Providers sheet → entry wiring.**
274:**Dependencies (round-3 Medium-4 — dependency honesty; #136 folded in):**
276:- **`Deps: [feat:#132, feat:#134]`.** **#132 (top chrome) and #134 (More menu) are VERIFIED.** **#129 (TXT/MD reader) is VERIFIED** — `TxtReaderActivity` is a straight edit, not a blocker. **There is NO external AI-reachability blocker** — the former #136 is CLOSED (GH #1976, not-planned) and its scope is #131-owned.
277:- **WI-4b is foundational and gates the behavioral chain.** WI-4b now provides `AiProviderStore` into `AppContainer` PLUS the bilingual services + factories. Per the audit's Medium-4, WI-4b transitively gates WI-6 (needs the prefetcher/DI), WI-7b (needs DI), WI-AIP (needs `AiProviderStore` + `AiSettingsViewModel` from `AppContainer`), and WI-8 (needs DI). **Chosen resolution: injected seams so the behavioral work proceeds against fakes before WI-4b lands, AND WI-4b is sequenced early.** Concretely: the VM (WI-5/WI-6) takes an injected `ChapterTranslationPrefetcher` (fake in tests) and an injected `AiProviderSnapshot` provider (fake); the TXT/MD host Compose/unit work (WI-8) and the Variant A sheet (WI-AIP) take injected VM/store/`AiSettingsViewModel` seams — so unit/Compose tests do not wait on `AppContainer`. **WI-4b is built right after WI-4a (before WI-6/WI-7b/WI-AIP/WI-8) so the production wiring lands before the host integrations that mount it.** This is stated honestly: the *production run-through* of WI-6/WI-7b/WI-AIP/WI-8 depends on WI-4b; their *unit/Compose gates* depend only on the injected seams. No external feature gates any of this.
279:**WI-0 (spike): Readium EPUB bilingual injection — go/no-go + race contract (M1).** Harness + criteria (a)–(e) and the race contract in §3. Output: a go/no-go on EPUB-in-v1 (no-go = box D ships TXT/MD-only, tracked) + the concrete `EpubChapterTextProvider` / `EpubBilingualJs` / `EpubBilingualController` surfaces + the EPUB direct-block ownership sequence (Medium-1). Deps: none (uses the existing #106 Readium host). Not TDD-gated (throwaway spike); feeds WI-7b.
281:**WI-1 (foundational): value types + pure segmentation/chunk/contract.** `TranslationUnitId`, `TranslationGranularity`, `BilingualLanguages`, **`ChapterSegmenter` (with `paragraphRanges`/`sentenceRanges` returning half-open UTF-16 `(start, endExclusive)` spans — H1)**, `TranslationChunker`, `TranslationChunkContract` (no `style`), `ChapterTranslationError`. Pure; ported iOS vectors. Deps: none.
285:**WI-3 (foundational): `ChapterTranslationService`** against a fake `AiClient`. Both `cachedTranslation` overloads (incl. the `expectedSegmentCount` divergence restore — H2) + `translate` + `translatePreSegmented`. **Dual-cancellation (native + typed `Cancelled`) BEFORE generic mapping (M2).** Deps: WI-1, WI-2. Tests: cache hit → zero client calls; miss → translate + write; decode fail → per-segment fallback; one-chunk fail → source-only that chunk (others translated, NOT cached); all-chunks fail → throw; native-cancel → `Cancelled` (no write); typed-`Cancelled`-from-chunk → `Cancelled` (no write); ensureActive-before-write; `AiError` mapping incl. `Config`/`InsecureUrl` → `ProviderFailed`; `translatePreSegmented` full-success caches under the enumerate count; partial degrade NOT cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` returns on stored-count match, null on mismatch, needs no provider.
287:**WI-4a (foundational): `ChapterTextProvider` (TXT/MD) + `ChapterTranslationPrefetcher` + `BilingualAiReadiness`.** `TxtChapterTextProvider` builds the document-global segment `(start, endExclusive)` ranges once (H1), groups into windows, resolves `unitContaining(charOffsetUTF16)` via segment-start binary search, `sourceSegments(unit)`. Prefetcher: `prefetch` + `prefetchDirect` + `cachedDirect`; resolves active profile from `snapshot()`, decrypts snapshot-consistent, builds client via the injected factory param (default `AiProviderFactory::create`), constructs `AiRequest` with **`model = profile.model.ifBlank { profile.kind.defaultModel }` (M3)**. Readiness = active profile with non-empty decrypted key; **cipher failure → not-ready, never a crash.** Fake store + fake factory. Deps: WI-1, WI-3. Tests (all half-open-range-based): unit resolution + clamp + empty; **one-chunk document (no trailing newline) → its segment translation renders, not dropped (H1)**; **final-chunk anchor → renders (H1)**; **exact-boundary → correct anchor (H1)**; **EOF anchor (`segEndExclusive == text.length`) → last chunk, no clamp-collapse (H1)**; paragraph spanning MANY chunks → one segment/one unit, anchored to the last chunk (Low-2); multiple SENTENCES in one chunk → distinct sentence segments (Low-2); a >4000-char paragraph hard-split across chunks → one segment; CR/LF/CRLF; MD markers; locator→unit mapping; `unitAfter` end→null; **source-byte parity while disabled**; cache-hit-no-profile still returns (#306); no-profile miss → `ProviderFailed`; `prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls; **blank `profile.model` → `AiRequest.model == kind.defaultModel` (M3 regression)**; readiness true/false; empty-key → false; no-active-with-profiles-present → false (H3); cipher-throw → readiness false (no crash).
289:**WI-4b (foundational — shared DI/factory, incl. `AiProviderStore` in `AppContainer`): AppContainer bilingual + AI-config graph.** `AppContainer` **now constructs `AiProviderStore`** (DataStore + #116 `KeystoreSecretCipher`, following the `readerSettingsStore` convention — this is #131's change, not an external feature's) and provides `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, an `AiSettingsViewModel` factory (for WI-AIP), and the `BilingualViewModel` factory. Deps: **WI-4a** (no external dep — #136 closed). Tests: container resolves the bilingual + AI-config graph; `AiProviderStore` resolves and round-trips a profile; the prefetcher's injected factory defaults to `AiProviderFactory::create`.
291:**WI-5 (behavioral): `PerBookBilingualStore` + `BilingualViewModel` state core.** Store per book (enabled/targetLanguage/granularity — no style); VM setters (persist + first-enable `needsSetupSheet`); `aiConfigured` from `BilingualAiReadiness.resolve` over an injected snapshot; language/granularity change clears cache-shaped state + bumps generation. Injected prefetcher/snapshot seams (Medium-4). Turbine tests: first-enable raises sheet; re-enable persisted does not; disable clears; language change resets; granularity change resets + re-keys; `aiConfigured` true/false from readiness; round-trip through store; no style field. Deps: WI-1 (+ store).
293:**WI-6 (behavioral): VM prefetch trigger + generation/cancellation + single-flight (M2).** `onPositionChanged(charOffsetUTF16)` derives current unit (TXT/MD only), dedupes, prefetches current+next; a monotonic position-request sequence checked after every suspension; **per-unit single-flight `prefetchTasks: Map<TranslationUnitId, Job>` (a new request cancels/joins the prior — M2)**; a captured language/granularity/provider snapshot per launch; generation bumps on disable/language/granularity/unit-change discard stale; **BOTH `CancellationException` AND typed `ChapterTranslationError.Cancelled` handled BEFORE generic error mapping (M2)**; a cancelled stale request does NOT surface as `errorUnit`; `Offline`→`unavailableUnits`; transient failure leaves unit unfetched + clears anchor to retry; `retryUnit` routes through the registry. The EPUB `onEpubBlocksEnumerated` entry is present but EPUB prefetch is owned by the controller (Medium-1); the VM's position-driven `prefetch` dispatches TXT/MD units only. Fake prefetcher (Medium-4 seam). Deps: WI-4a, WI-4b, WI-5. Tests: current+next on unit change; same-unit no-op; cancel-mid discards stale (no `errorUnit`); typed-`Cancelled` discards (not `errorUnit`); rapid re-trigger same unit → single-flight, no double-write; offline→unavailable; failure→retry-able; `retryUnit` re-fetches; granularity change cancels + re-fetches under the new key.
295:**WI-7a (behavioral): Compose UI — setup sheet + interlinear body (TXT/MD) + pill.** Reproduce `vreader-bilingual.jsx` (setup sheet: language grid / granularity / preview / engine strip configured+unconfigured; body: the **additive translation items** per the H2 render contract — translated / loading N%+dimmed / error+Retry / offline source-only; pill). Consumes the host-neutral `BilingualRenderState` DTO. Light+dark. Compose UI tests each state, incl. **paragraph interlinear renders a translation item after a paragraph (depicted)** and **Sentence selection falls back to paragraph render (H2 gate)**. Deps: WI-5 (state shape). NO Style control; the unconfigured "Set up" CTA renders and (in WI-9) routes to the Variant A sheet.
297:**WI-7b (behavioral, CONDITIONAL — only if WI-0 = go): EPUB render adapter (DOM injection, NOT Compose — M2) + direct-block ownership (M1).** `EpubBilingualJs` (enum/inject/clear JS builders, CSP-safe escaping) + `EpubBilingualController` (the serialization actor / session token AND the **single-owner enumerate→cachedDirect/prefetchDirect→guarded-commit sequence — Medium-1**) + `EpubChapterTextProvider`, wired into `ReaderActivity`, driving DOM from the shared `BilingualRenderState` DTO. Uses `prefetchDirect`/`cachedDirect` for the count-divergence path (H2). Depends on WI-6 (VM state) and WI-4b (DI); the WI-7a UI dependency is only the shared `BilingualRenderState`/value types. Connected test on a real EPUB (seeded cache): enable → injects; disable → cleared; reflow/href-change/fragment-recreation/activity-recreation → re-applies from cache (zero provider calls) via `cachedDirect`; count-divergence handled (direct path); **the regular TXT/MD prefetch path is never invoked for an EPUB unit (Medium-1)**. Unit tests: JS escaping/CSP-safe insertion, RTL/CJK style, empty translations, loading cleanup, idempotent replacement, source-only fallback, stale-session-token commit discarded (no `errorUnit`). Deps: WI-0, WI-3, WI-4a, WI-4b, WI-6, (shared types from WI-7a). (If WI-0 = no-go, dropped; box D ships TXT/MD-only, tracked.)
299:**WI-AIP (behavioral — the folded-in Variant A AI Providers sheet): `ReaderAiProvidersSheet`.** The scoped in-reader "AI Providers" push sheet (nav bar `‹ Bilingual` + "AI Providers" title) reproducing `vreader-ai-provider-entry.jsx` `AIProvidersSheet`/`NavSheet`, hosting ONLY the #118 `AiProviderListScreen` (empty + populated) + the canonical `AiProviderEditSheet`, driven by the #118 `AiSettingsViewModel` (from WI-4b's `AppContainer` factory). Empty state carries the bilingual-context copy ("Bilingual mode needs a provider to translate" / "Add provider" CTA). On first Save → the provider becomes the bilingual engine (`store.setActive(savedId)`) + pop the whole stack back to the bilingual sheet (engine strip now "configured / Change…"). `‹ Bilingual` without adding → unconfigured, no state mutated. No consent/flag surface (Android has none). Deps: WI-4b (for `AiProviderStore` + `AiSettingsViewModel` in `AppContainer`), WI-7a (bilingual sheet host). Tests (Compose + connected): empty → Add → Save → pop-to-bilingual with strip configured; `‹ Bilingual` without adding → strip unconfigured, snapshot unchanged; "Change…" → populated list, current provider checked, tap row → `setActive`; editor reused verbatim (no divergent form).
301:**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into the `items(count = document.chunkCount)` loop as **additive translation items after the anchor chunk, source chunks byte-unchanged (H2)** + position-change (`charOffsetUTF16`) + setup-sheet. `originalFormat`-gated (TXT/MD). Uses WI-4b's DI. **#129 VERIFIED — straight edit.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2)**; **highlights/annotation-washes/read-aloud-wash still key off source chunks (H2)**; a translation item is non-selectable, does not perturb source offsets (H2); disable → source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders exactly one translation after its last chunk (H1/Low-2)**; **one-chunk/final-chunk anchors render (H1)**; MD source mapping. Deps: WI-6, WI-7a, WI-4b.
303:**WI-9 (behavioral): entry wiring + acceptance.** Mount `BilingualPill` in #132's VERIFIED top chrome; extend `readerMoreRows(...)` to supply the #134 VERIFIED More-menu `MoreActionId.BILINGUAL` toggle (`MoreRow.Toggle` `on`/`onToggle`, or `MoreRow.Disabled` "Configure AI provider first" when not configured) wired to the VM; **wire the setup sheet's "Set up"/"Change…" affordance → the #131-owned `ReaderAiProvidersSheet` (Variant A)**. Full acceptance across EPUB (if WI-7b landed) + TXT/MD, including the fresh-user path `unconfigured → Set up (→ Variant A AI Providers sheet) → add provider → return → enable → translate` (now #131-owned end-to-end). **Flip box D to done ONLY for provider/model/granularity + the Style-descope note; file the follow-up checklist amendment; do NOT claim full box-D parity.** The DONE flip **no longer waits on #136** (closed). Update `docs/architecture.md` (bilingual pipeline + the new `chapter_translations` schema + `AiProviderStore` + bilingual services in `AppContainer` + the Variant A AI Providers sheet). → DONE. Deps: WI-8, WI-AIP, WI-7b (if go), feat:#132, feat:#134.
307:JVM/Robolectric (`android/app/src/test/...bilingual/`): `ChapterSegmenterTest` (paragraph blank-line; sentence CJK `。！？` vs Latin; empty→[]; single; **`paragraphRanges`/`sentenceRanges` return correct half-open UTF-16 `(start, endExclusive)` spans**); `TranslationChunkerTest` (packs to budget; oversize→own chunk+subSplit; empty→[]); `TranslationChunkContractTest` (prompt shape; strict JSON decode; code-fence strip; count mismatch→`CountMismatch`; non-array→`NotAStringArray`); `ChapterTranslationServiceTest` (cache hit 0 calls; miss→translate→write; decode-fail per-segment fallback; one-chunk-fail partial-not-cached; all-fail→throw; **native-cancel→Cancelled no write; typed-`Cancelled`→Cancelled no write (M2)**; ensureActive-before-write; offline/timeout/429/http/config/insecure→error mapping; very long chapter N-of-M; stale-cache count-mismatch re-translates; `translatePreSegmented` caches under enumerate count on full success; partial degrade not cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` hit/miss with no provider); `ChapterTranslationErrorMappingTest`; `TxtChapterTextProviderTest` (**one-chunk document → renders (H1); final-chunk anchor → renders (H1); exact-boundary → correct anchor (H1); EOF anchor → last chunk, no clamp-collapse (H1)**; paragraph spanning MANY chunks → one segment/unit anchored to last chunk (Low-2); multiple SENTENCES in one chunk → distinct segments (Low-2); >4000-char paragraph → one segment across hard-split chunks; CR/LF/CRLF; MD markers; locator→unit mapping; `unitAfter` end→null; source-byte parity while disabled); `ChapterTranslationPrefetcherTest` (snapshot-consistent profile+key; injected-factory used; `AiRequest` built from profile; **blank `profile.model` → `kind.defaultModel` (M3 regression)**; cache-hit-no-profile #306; no-profile miss→ProviderFailed; `prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls; CJK↔English + Latin round-trip via fake; cipher-throw→ProviderFailed not crash); `BilingualAiReadinessTest` (active+key→true; **no-active-with-profiles-present→false (H3); activeId-null→false (H3)**; empty key→false; cipher-throw→false, no crash); `PerBookBilingualStoreTest` (enabled/lang/granularity round-trip; no style field); `BilingualViewModelTest` (Turbine: first-enable sheet; re-enable no-sheet; disable clears; language reset; granularity reset + re-key; `aiConfigured` from readiness; prefetch current+next; same-unit no-op; **cancel-mid discards (no errorUnit); typed-Cancelled discards (M2); rapid re-trigger same unit single-flight, no double-write (M2)**; offline→unavailable; error→errorUnit+retry; `retryUnit`); `EpubBilingualJsTest` (JS escaping / CSP-safe insertion; RTL/CJK style; empty translations; clear idempotent; inject idempotent replacement; source-only fallback — WI-7b if go); `EpubBilingualControllerTest` (**enumerate→cachedDirect/prefetchDirect→guarded commit; stale-session-token commit discarded, no errorUnit; single-owner (regular TXT/MD prefetch never runs for EPUB unit) — Medium-1** — WI-7b if go).
311:Compose UI (`androidTest/...bilingual/`): `BilingualSetupSheetUiTest` (language grid, granularity, preview, engine configured vs unconfigured driven by `aiConfigured`; no Style control present; light+dark); `BilingualInterlinearBodyUiTest` (**additive translation item after a paragraph anchor chunk (depicted); paragraph interlinear translated incl. CJK font + RTL Arabic; Sentence selection → paragraph-render fallback (H2 gate)**; loading N%+dimmed; error+Retry; offline source-only; empty translation→source-only no crash); `ReaderAiProvidersSheetUiTest` (**empty state with bilingual-context copy + Add CTA; populated list + current-provider checked; `‹ Bilingual` back label; editor reused (WI-AIP)**); `BilingualPillUiTest`.
313:Connected (`androidTest/...reader/`): `TxtReaderBilingualConnectedTest` (API 35, fake `AiClient` via injected factory): enable→setup→confirm→interlinear from seeded Room cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2); highlights/annotation-washes/read-aloud-wash still key off source chunks (H2); translation item non-selectable + no source-offset perturbation (H2)**; disable→source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders one translation (H1/Low-2); one-chunk/final-chunk anchors render (H1)**; TXT/MD gated (PDF inert); very long chapter scroll responsive; cancellation leaves no partial cache row. `ReaderAiProvidersConnectedTest` (WI-AIP + WI-9): `unconfigured → Set up → Variant A sheet → add provider → Save → pop-to-bilingual configured → enable → translate`; `‹ Bilingual` without adding → unconfigured, snapshot unchanged; "Change…" → populated, current checked. `EpubReaderBilingualConnectedTest` (only if WI-0=go): enable→inject on a real EPUB; disable→clear; href-change/fragment-recreation/activity-recreation→re-apply from cache (zero provider calls); count-divergence handled via `prefetchDirect`/`cachedDirect`; regular prefetch never runs for EPUB unit (Medium-1).
315:Edge cases: empty translation, failed, partial per-chunk, CJK↔English + Latin + RTL, provider error/timeout/429/config/insecure, native + typed cancellation mid-translation + before-write, single-flight overlap, very long chapters, offline (cache-first + silent source-only), cipher-decrypt failure → not-ready (no crash), enumerate↔segment count divergence (direct path), one-chunk/final-chunk/EOF anchors (H1), blank model (M3).
319:- **Live-translation verification is AI-credential-gated (the box-D caveat).** The whole pipeline is verified without live creds via a deterministic **fake `AiClient`** injected through the prefetcher's `clientFactory` param (default `AiProviderFactory::create`; tests override). WI-3/4a/8 prove segment→chunk→decode→cache→interleave end-to-end incl. every error/edge path. Connected tests seed the Room cache and assert render-from-cache with zero client calls. An optional live smoke confirms wire format but is NOT a gate. The fresh-user `unconfigured → Set up → add provider` reachability leg is now #131-owned (WI-AIP + WI-9) and verified by `ReaderAiProvidersConnectedTest`.
320:- **Final-chunk translation drop (round-3 H1).** Fixed by `endExclusive = if (i+1<chunkCount) offsetForChunk(i+1) else text.length` + explicit half-open `(start, endExclusive)` computations everywhere; one-chunk/final-chunk/exact-boundary/EOF tests. `offsetForChunk`'s clamp (TxtDocument.kt:17) is never relied on for the final end.
321:- **Enabled render breaking the per-chunk layout/selection model (round-3 H2).** Fixed by the additive-item render contract: source chunk `Text` is NEVER split; translations are separate, non-selectable, unregistered `LazyColumn` items after the anchor chunk. Enabled-mode tests assert selection/highlight/wash/annotation parity with disabled. Sentence-granularity render is design-gated (only paragraph interlinear is depicted); Sentence selection falls back to paragraph render, granularity still cache-keyed.
322:- **TXT/MD segment↔render pairing (round-2 H1).** Both sides read the SAME segment `(start, endExclusive)` array over `TxtDocument.text`, so 1:1 holds by construction — no chapter model invented; a paragraph split across many chunks is translated + rendered once (anchored at its last chunk). Granularity is in the cache key.
323:- **EPUB direct-block flow (round-3 Medium-1).** The `EpubBilingualController` is the single owner: `enumeratedBlocks → cachedDirect (zero-provider restore) else prefetchDirect → session-token-guarded commit into BilingualRenderState/translationsByUnit`. The VM's position-driven regular prefetch is TXT/MD-only, so the two paths never write the same canonical cache row. Every suspended step is token-guarded; a stale token discards silently.
324:- **EPUB count divergence (round-2 H2).** The direct-block path (`prefetchDirect` → `translatePreSegmented`, cached by enumerate count, restored by `cachedDirect(expectedCount)` with zero provider calls) — iOS Bugs #268/#330/#343 parity.
325:- **EPUB JS-injection race (round-2 M1).** WI-0's contract (single actor/mutex OR monotonic navigator-session token; token check after every suspended call; clear before publication teardown; identified production re-apply signal per recreation case). No deterministic re-apply signal = explicit NO-GO → TXT/MD-only ship.
326:- **Cancellation + single-flight (round-3 Medium-2).** Both service and VM handle native `CancellationException` AND typed `ChapterTranslationError.Cancelled` before generic mapping (iOS `ChapterTranslationService.swift:359–364`); a per-unit `prefetchTasks: Map<TranslationUnitId, Job>` cancels/joins a prior request so rapid retry/navigation can't run overlapping translations or Room writes; a cancelled stale request never surfaces as `errorUnit`. `ensureActive()` before the Room write.
327:- **Blank model (round-3 Medium-3).** The prefetcher builds `model = profile.model.ifBlank { profile.kind.defaultModel }` (matches `AiChatViewModel.kt:61`; both wire clients serialize `request.model` directly, `OpenAiCompatibleProvider.kt:39`/`AnthropicProvider.kt:37`). Blank-model regression test.
332:- **Dependency honesty (round-3 Medium-4).** WI-4b (DI, incl. `AiProviderStore` in `AppContainer`) is foundational and gates the production run-through of WI-6/WI-7b/WI-AIP/WI-8; those WIs' unit/Compose gates proceed against injected fakes, and WI-4b is sequenced before them. No external feature gates the chain (#136 closed).
337:- **Reader unchanged when bilingual off** — the TXT/MD `items(count = document.chunkCount)` source loop is **byte-identical** unless `enabled && format∈{txt,md} && translation present` (translations are additive, non-selectable overlay items — H2). `ReaderBottomChrome` is not modified. EPUB render adapter inert unless bilingual is on.
341:- **#132/#134/#129 landed** — the top-chrome pill mount + More-menu toggle (`readerMoreRows` extension) + `TxtReaderActivity` edit land on VERIFIED surfaces (rule 48 one-writer-per-file satisfied).
348:*(REMOVED: the v3 "#136 dependency" design-gate line — #136 is closed and the Variant A AI Providers sheet IS the committed design, reproduced by WI-AIP, not a gate.)*
354:- v3 (2026-07-12): Gate-2 round-2 findings resolved — TXT/MD document-global segment model (H1); EPUB translatePreSegmented + count-keyed cache + direct-block prefetch (H2); #136 AI-provider-reachability spun out as a hard dependency (GH #1976) + Style descoped v1 (H3); WI-0 go/no-go + navigator-race contract (M1); EPUB DOM-injection adapter not Compose body (M2); DI/factory WI reordered (M3); Room 8→9 MIGRATION_8_9 (M4); deps/WI-count corrected (L1/L2). Gate-2 round-3 = block-recommended.
356:  - **AI-config FOLDED IN (#136 CLOSED, GH #1976 not-planned; user decision 2026-07-12):** the design proved the ONLY designed Android AI-config reader surface is the bilingual-coupled **Variant A** "AI Providers" sheet (`reader-ai-provider-entry.md`); it is not separable, so #131 now owns it end-to-end. Added **WI-AIP** (`ReaderAiProvidersSheet`, reusing #118 `AiProviderListScreen`/`AiProviderEditSheet`/`AiSettingsViewModel` verbatim, `‹ Bilingual` push, pop-back-on-first-Save); WI-4b now provides `AiProviderStore` into `AppContainer` (verified not provided today — VReaderApp.kt:66 comment only) plus the bilingual services + `AiSettingsViewModel` factory; removed `feat:#136` from Deps (now `[feat:#132, feat:#134]`, no external AI-reachability blocker); the DONE flip no longer waits on #136; `aiConfigured` derivation kept as the correct active-profile+decrypts-non-empty gate (H3), NOT `profiles.isEmpty()` (the iOS note's derivation), with no consent/flag gate (Android has none).
357:  - **H1 (round-3 High-1) final-chunk math:** `endExclusive = if (i+1<chunkCount) offsetForChunk(i+1) else text.length`; explicit half-open `(start, endExclusive)` computations (not `IntRange`); one-chunk/final-chunk/exact-boundary/EOF tests.
358:  - **H2 (round-3 High-2) additive-item render contract:** translations are additive `LazyColumn` items at chunk (line) boundaries; the source chunk `Text` is NEVER split; per-chunk one-`TextLayoutResult`/one-selection-registration preserved (TxtReaderActivity.kt:1043/1059/1062–1066); enabled-mode selection/highlight/wash/annotation/MD tests; sentence-granularity render flagged as a rule-51 design gate (only paragraph interlinear is depicted), paragraph ships.
359:  - **M1 (round-3 Medium-1) EPUB direct-block ownership/API:** `EpubBilingualController` single owner; `enumeratedBlocks → cachedDirect else prefetchDirect → session-token-guarded commit into BilingualRenderState/translationsByUnit`; regular prefetch is TXT/MD-only so the two paths never write the same canonical row.
360:  - **M2 (round-3 Medium-2) dual-cancellation + single-flight:** service AND VM handle native `CancellationException` AND typed `ChapterTranslationError.Cancelled` before generic mapping (iOS `ChapterTranslationService.swift:359–364`); per-unit `prefetchTasks: Map<TranslationUnitId, Job>` cancels/joins a prior; a cancelled stale request never surfaces as `errorUnit`.
361:  - **M3 (round-3 Medium-3) blank-model fallback:** `model = profile.model.ifBlank { profile.kind.defaultModel }` (matches `AiChatViewModel.kt:61`; clients serialize `request.model` directly); blank-model regression test.
362:  - **M4 (round-3 Medium-4) dependency honesty:** WI-4b (DI incl. `AiProviderStore`) is foundational and gates the production run-through of WI-6/WI-7b/WI-AIP/WI-8; those WIs' unit/Compose gates use injected fakes; WI-4b sequenced before them; no external feature gates the chain.
363:  - **Low fixes:** WI count corrected to **13** (added WI-AIP; the "11 WIs" claim was wrong — Low-1); chunk semantics corrected — a chunk is ONE LINE, holds multiple SENTENCES, a paragraph spans MANY chunks; removed the "a chunk can hold multiple paragraphs" claim (Low-2). Awaiting Gate-2 round-4 audit.
dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual-suite.jsx
dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual-offline.jsx
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx
dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx
dev-docs/designs/vreader-fidelity-v1/project/VReader AI Provider Entry Canvas.html
dev-docs/designs/vreader-fidelity-v1/project/VReader AI Provider Editor Canvas.html
vreader/Services/TOCProvider.swift
vreader/Services/DebugBridge/RealDebugBridgeContext+Provider.swift
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md
vreader/Services/Backup/BackupProvider.swift
vreader/Services/Backup/WebDAVProviderFactory.swift
vreader/Services/Backup/WebDAVProvider.swift
vreader/Services/TXT/TXTLazyTextProvider.swift
vreader/Services/Reader/TXTChapterTextProvider.swift
vreader/Services/Reader/TXTLoaderBackedChapterTextProvider.swift
vreader/Services/Reader/FoliateChapterTextProvider.swift
vreader/Services/Reader/PDFChapterTextProvider.swift
vreader/Services/Reader/MDChapterTextProvider.swift
vreader/Services/Reader/EPUBChapterTextProvider.swift
vreader/Services/AI/ChapterTranslationService.swift
vreader/Services/AI/AnthropicProvider+Streaming.swift
vreader/Services/AI/AnthropicProvider.swift
vreader/Services/AI/ResolvedAIProviderConfig.swift
vreader/Services/AI/Tools/BookContentProviderAdapter.swift
vreader/Services/AI/KeychainService+ProviderProfile.swift
vreader/Services/AI/OpenAICompatibleProvider+ToolUse.swift
vreader/Services/AI/ProviderProfileMigrator.swift
vreader/Services/AI/ProviderProfile.swift
vreader/Services/AI/AIProvider.swift
vreader/Services/AI/MockAIProvider.swift
vreader/Services/AI/ProviderKind.swift
vreader/Services/AI/ProviderProfileStore.swift
vreader/Services/AI/ProviderConfigResolving.swift
vreader/Services/AI/AnthropicProvider+ToolUse.swift
vreader/ViewModels/AIProviderPickerViewModel.swift
vreader/ViewModels/BilingualReadingViewModel+Prefetch.swift
vreader/ViewModels/BilingualReadingViewModel.swift
vreader/Services/TTS/TTSProviderProtocol.swift
vreader/Services/TTS/HTTPTTSProvider.swift
vreader/App/VReaderAppDelegate.swift
vreader/App/VReaderApp.swift
vreader/Views/Settings/AIProviderListView.swift
vreader/Views/Reader/AIProviderPicker.swift
vreader/Views/Settings/AIProviderEditSheet+Sections.swift
vreader/Views/Settings/AIProviderEditSheet.swift
vreader/Views/Settings/AIProviderListView+Rows.swift
vreader/Views/Reader/Bilingual/ReaderAIProvidersFlow.swift
vreader/Views/Reader/Bilingual/ReadinessProviderBlock.swift
vreader/Views/Reader/EPUBContinuousChapterProvider.swift
android/app/src/test/kotlin/com/vreader/app/ai/AiChatViewModelTest.kt
android/app/src/test/kotlin/com/vreader/app/ai/AnthropicProviderTest.kt
android/app/src/test/kotlin/com/vreader/app/ai/OpenAiCompatibleProviderTest.kt
android/app/src/test/kotlin/com/vreader/app/ai/AiProviderStoreTest.kt
android/app/src/test/kotlin/com/vreader/app/ai/AiProviderKindTest.kt
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt
android/app/src/test/kotlin/com/vreader/app/reader/share/BookFileProviderDisplayNameTest.kt
android/app/src/test/kotlin/com/vreader/app/reader/nav/ReadiumTocProviderTest.kt
android/app/src/main/kotlin/com/vreader/app/reader/share/BookFileProvider.kt
android/app/src/test/kotlin/com/vreader/app/reader/TxtDocumentTest.kt
android/app/src/main/kotlin/com/vreader/app/reader/nav/ReadiumTocProvider.kt
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocProvider.kt
android/app/src/main/kotlin/com/vreader/app/reader/nav/BookmarkPreviewProvider.kt
android/app/src/main/kotlin/com/vreader/app/reader/nav/EmptyTocProvider.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderFactory.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt
android/app/src/main/kotlin/com/vreader/app/ai/AnthropicProvider.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderKind.kt
android/app/src/main/kotlin/com/vreader/app/ai/OpenAiCompatibleProvider.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt
android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderEditSheetTest.kt
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderListScreenTest.kt
android/app/src/androidTest/kotlin/com/vreader/app/reader/TxtReaderActivityTest.kt

codex
The repository is clean except for the user’s in-progress plan/tracker/audit artifacts, which I’m treating as read-only. The v4 plan now states the intended fixes clearly; I’m checking whether those contracts fit the actual Compose item model, Kotlin offsets, provider persistence, and the iOS parity it cites.
exec
/bin/zsh -lc "sed -n '38,190p' dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md && sed -n '190,370p' dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md && nl -ba android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt && nl -ba android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt | sed -n '1000,1095p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
### The TXT/MD segmentation unit + render mapping (round-2 H1 + round-3 H1/H2 — the core corrections)

**Verified against live code:** `TxtDocument` (`reader/TxtDocument.kt`) exposes only `text: String`, `chunkCount` (`starts.size`, TxtDocument.kt:14), `offsetForChunk(index)` (TxtDocument.kt:17), `chunkForOffset(offsetUtf16)` (TxtDocument.kt:23), `textForChunk(index)` (TxtDocument.kt:36) — line-based ≤4000-char chunks over UTF-16 offsets against the RAW text (no line-ending normalization). It has **no chapter/section concept**.

**Chunk semantics (round-3 Low-2 correction — the real cases):** a chunk is **ONE LINE** — `TxtDocument.of` starts a new chunk after every `\n`, `\r`, or `\r\n` (TxtDocument.kt:65–86; a runaway line >4000 chars is additionally hard-split, never mid-surrogate-pair). Therefore:
- A **chunk can hold multiple SENTENCES** (one line, several `。！？`/`. ! ?` sentences).
- A **paragraph spans MANY chunks** (blank-line-delimited paragraph = several physical lines = several chunks).
- The old v3 claim "a chunk can hold multiple **paragraphs**" is **WRONG and removed.** (A single chunk cannot straddle a line terminator, and paragraph boundaries are blank lines, i.e. chunk boundaries — so a chunk holds *part of one* paragraph, never a whole extra paragraph.)

**v4 model — document-global units with segment ranges produced ONCE:**

- The whole `.txt`/`.md` is treated as **one translation document**. The **segmenter runs once over `TxtDocument.text`** (the full raw backing string) and emits, per segment, its **half-open UTF-16 span `[start, endExclusive)`** against that same backing string (the segmenter's `paragraphRanges(text): List<IntRange>` / `sentenceRanges(text): List<IntRange>` — the range-returning peers of `paragraphs`/`sentences`; iOS precedent `ChapterSegmenter.sentenceRanges(in:)` at `ChapterSegmenter.swift:78`, returns `[Range<Int>]`). These ranges are the SINGLE source of truth used by BOTH the translate side and the render side, so the two segment identically **by construction** (they read the same array). Ranges are stored/compared as explicit `(start, endExclusive)` integer pairs (see the H1 fix below), NOT re-derived on the render side.
- **Unit granularity for TXT/MD is the whole document, sub-batched for cache/prefetch by a deterministic "unit window."** To avoid translating a 14 MB book at once (and to keep cache rows bounded), segment ranges are grouped into fixed **unit windows** of contiguous segments (window size a build-time constant; it does not change the 1:1 contract). Each window is a `TranslationUnitId(kind = txtDocSegmentWindow, value = windowIndex)` — a document-global index, NOT a chunk index. `unitContaining(charOffsetUTF16)` maps the reader's saved offset → the segment whose range contains it → its window index (via a precomputed segment-start binary search, the same shape as `TxtDocument.chunkForOffset`, TxtDocument.kt:23–33). `unitAfter(unit)` = next window index or null at document end.

#### H1 fix (round-3 High-1) — final-chunk source span math (BINDING)

`offsetForChunk()` **CLAMPS** an out-of-range index to the last valid chunk (`starts[index.coerceIn(0, starts.size - 1)]`, TxtDocument.kt:17–20). So for the LAST chunk `i`, `offsetForChunk(i + 1) == offsetForChunk(i)` → an **empty span** → a one-chunk document drops EVERY translation and a paragraph ending in the final chunk drops its sole translation. `textForChunk()` avoids this by using `text.length` for the final end (TxtDocument.kt:39). The render side MUST do the same. **Binding rule:**

```
val endExclusive = if (i + 1 < document.chunkCount) document.offsetForChunk(i + 1) else document.text.length
// chunk i source span is the HALF-OPEN [document.offsetForChunk(i), endExclusive)
```

- All chunk-span and segment-span computations use **explicit half-open `[start, endExclusive)` integer pairs**, NOT ambiguous Kotlin `IntRange` (an `IntRange` is inclusive-inclusive and `range.last` for an empty/at-EOF segment is a footgun). A segment's "end offset" for anchoring (below) is its `endExclusive`; the chunk that "contains a segment's end" is `document.chunkForOffset(segEndExclusive - 1)` when `segEndExclusive > segStart`, clamped to `[0, chunkCount-1]` (an empty segment is dropped by the segmenter and never anchored).
- **Tests (WI-4a / WI-8):** one-chunk document (no trailing newline) → its single paragraph/sentence translation renders (not dropped); final-chunk anchor (a paragraph whose last line is the final chunk) → translation renders after the last chunk; exact-boundary (a segment ending exactly at a chunk `start`) → anchored to the correct chunk, not off-by-one; EOF anchor (`segEndExclusive == text.length`) → resolves to the last chunk, no clamp-collapse.

#### H2 fix (round-3 High-2) — the enabled render contract (BINDING; preserves the live per-chunk model)

**The live invariant (verified, TxtReaderActivity.kt:1043–1085):** the TXT/MD body iterates `items(count = document.chunkCount, key = { it })` (TxtReaderActivity.kt:1043). For **each chunk `i`** it owns **exactly ONE `TextLayoutResult`** (`var layout by remember(i) { … }`, set in `onTextLayout`, TxtReaderActivity.kt:1059/1075) and **exactly ONE selection registration** (`selectionController.registerChunk(i, l, c)` / `unregisterChunk(i)`, TxtReaderActivity.kt:1062–1066). Highlights (`highlightSpan(i)`, :1047), annotation washes (`washesForChunk(i)`, :1058), the read-aloud span wash (`addStyle(SpanStyle(background = wash), …)`, :1050–1054), and selection accents (`selectionForChunk(i)` → `drawRangeFill`, :1069/1081) all key off that **per-chunk** layout and the chunk-local UTF-16 offsets. **Splitting a chunk's source `Text` into multiple `Text` nodes (as v3 implied — "source `Text` then translation `Text` per segment") would break every one of these:** two `Text` nodes = two `TextLayoutResult`s = broken selection coordinates, misplaced highlight/wash/annotation ranges, and a shifted read-aloud wash. This is the crux the round-3 audit blocked on.

**v4 binding render contract:**

> **Translations are ADDITIVE `LazyColumn` items rendered at CHUNK (line) boundaries. A source chunk's `Text` is NEVER split.** The existing `items(count = document.chunkCount, key = { it })` source loop stays **byte-identical to today** — same one `Text`, same one `TextLayoutResult`, same one `registerChunk(i, …)`/`unregisterChunk(i)`, same `highlightSpan(i)`/`washesForChunk(i)`/`selectionForChunk(i)` wiring. Each **translation is a NEW, separate `LazyColumn` item** inserted **AFTER** the source chunk that contains the segment's **end** offset (`document.chunkForOffset(segEndExclusive - 1)`, per the H1 math). The translation item is a plain muted `Text` (accent left-border, `fontSize*0.88`, CJK/RTL styling per `BilingualPageContent`) that is **non-selectable and registers NO chunk** — it does not call `registerChunk`, contributes no `TextLayoutResult` to the selection controller, and does not perturb any source chunk's UTF-16 offsets or index `i`.

Concretely the body becomes, per chunk `i` (in a single `items(count = document.chunkCount)` loop, or an explicit interleaving over a precomputed `chunkIndex -> List<translationItem>` map so keys stay stable):

1. Render the source chunk `i` EXACTLY as today (unchanged code path).
2. Look up the translations **anchored** to chunk `i` = every segment whose end resolves to `chunkForOffset(segEndExclusive - 1) == i`, in segment order, from the shared range array. For **paragraph** granularity there is at most one such translation per anchor chunk in the common case (a paragraph's translation renders after the paragraph's last line-chunk). For **sentence** granularity, when several sentences END in the same line-chunk (one line, multiple sentences), their translations are **grouped** and rendered as a stack of muted items after that chunk, in sentence order.
3. Emit each anchored translation as its own additive item (keyed by the segment's `(start, endExclusive)` so a granularity/language change re-keys cleanly).

When bilingual is **OFF**, no translation items are emitted → the loop is **byte-identical to today** (translations are additive overlay items only; this is asserted by a source-byte-parity test).

- **Enabled-mode tests (WI-8 connected + WI-7a Compose, BINDING):** with bilingual ON — (a) each source chunk's **selection registration is UNCHANGED** (same `registerChunk(i, …)` count and coordinates as OFF; a translation item registers nothing); (b) **highlights/annotation washes/read-aloud wash still key off the source chunks** at the correct offsets (a translation item between chunks does not shift them); (c) a **translation item is non-selectable** and does not perturb source offsets (selecting across the boundary selects source only); (d) **MD source mapping** — the markdown renderer (`mapper.renderedText(i)`, TxtReaderActivity.kt:1049) still owns the source chunk render; the translation item is plain muted text; (e) **paragraph-spanning-many-chunks** renders exactly ONE translation (after the paragraph's last chunk), never per-line; (f) final-chunk/one-chunk anchors render (H1).

- **Granularity depiction (round-3 H2 — rule-51 call, stated with evidence):** `vreader-bilingual.jsx` `BilingualPageContent` (lines 200–277) is a **paragraph-interlinear** renderer: it maps `page.paragraphs.map(...)` and renders **one source `<p>` followed by ONE translation `<p>`** per paragraph. **Sentence-granularity interlinear (a translation after the line where each sentence ends, grouped when several sentences share a line) is NOT depicted anywhere** — sentence granularity appears ONLY as an option in the `BilingualSetupSheet` Granularity segmented control (`vreader-bilingual.jsx:85–99`), never in the renderer. **Call:** paragraph granularity IS the depicted interlinear pattern and **ships in v1**. The **sentence-granularity render is a rule-51 design gate** (named precisely below) — v1 ships the setup-sheet Granularity control (both options selectable, as depicted) but the **renderer implements only the depicted paragraph pattern**; selecting Sentence in v1 falls back to the depicted paragraph interlinear (the granularity is still carried in the cache key so no wrong-shape row is served) until the sentence-interlinear render is designed. This keeps rule 51 (implement only what is depicted) while shipping the depicted paragraph parity. (The additive-item render contract above is written to accommodate sentence grouping so the gate, once designed, is a render-only follow-up.)

- **MD source** = raw markdown segment text (translation renders as plain muted text, not re-markdown-rendered — matches the muted-secondary design line). Segmentation runs over the raw markdown string; MD markers are treated as ordinary characters by the paragraph splitter (blank-line delimited), consistent with `TxtMdTextExtractor` shipping raw markdown to search.

This closes H1 (no dropped final-chunk translations), H2 (per-chunk layout/selection preserved; source `Text` never split), and Low-2 (correct chunk semantics).

### AI-config reachability — FOLDED IN (#136 CLOSED; Variant A owned by #131)

**Verified against live code:** `AppContainer` (`VReaderApp.kt:31–268`) constructs **NO `AiProviderStore`** — the only reference is a *comment* naming "the OpdsSourceStore / AiProviderStore precedent" (VReaderApp.kt:66), no actual instance/provision. There is **no live navigation route to `AiProviderListScreen`** (the #118 `AiProviderListScreen` / `AiProviderStore` / `AiSettingsViewModel` exist and are exercised only by instrumented/round-trip tests). A fresh-install user therefore cannot reach provider config today.

The Gate-2 audits + the two design-notes proved the ONLY designed Android AI-config reader surface is **Variant A** (`reader-ai-provider-entry.md`, CANONICAL): a **scoped "AI Providers" sheet pushed _inside_ the bilingual sheet**, reached from the bilingual engine-strip's "Set up"/"Change…" button. The design explicitly **rejected** a standalone entry (there is NO designed standalone More-menu "Configure AI" row), a full-Settings deep-link (alternative B), and inline expansion (alternative C). So AI-config reachability is **NOT separable** from the bilingual flow — the #136 spin-out is **CLOSED (GH #1976, not-planned)** and **#131 now owns it end-to-end** (user decision 2026-07-12).

**Navigation model (reproduced EXACTLY from `reader-ai-provider-entry.md`:110–134, invent nothing):**

```
More ▸ Bilingual mode (first toggle on)
  └─ BilingualSetupSheet   [bottom sheet]
       engine strip: "No AI provider configured"  [ Set up ]
                             │  onOpenSettings
                             ▼  (push, slide-left, same sheet frame)
     ReaderAiProvidersSheet  [nav bar: ‹ Bilingual · "AI Providers"]
       ├─ empty  → [ Add provider ] ─┐
       └─ list   → tap a row sets it │  (present the canonical editor, full height)
                             ▼        ▼
                    AiProviderEditSheet   [reused VERBATIM from #118]
                             │  Save
                             ▼  (first provider becomes the bilingual engine,
                                  pop the whole stack)
     BilingualSetupSheet  ← engine strip now "Claude · configured" / Change…
```

- **`‹ Bilingual` without adding** returns to the bilingual sheet **still unconfigured — no state mutated.**
- **"Change…"** (already-configured strip) opens the **SAME** `ReaderAiProvidersSheet`, populated, current provider checked.
- The AI Providers view is a **push within the bilingual sheet**, NOT a modal over the reader and NOT the full app Settings.

**Android readiness gate (BINDING — round-3/round-2 H3 + the #136-audit High-3 lesson):** `aiConfigured` on the engine strip is derived by `BilingualAiReadiness.resolve(snapshot)` = **an ACTIVE profile exists AND its API key decrypts to non-empty.** Deriving from `profiles.isEmpty()` alone is **WRONG**: the store keeps a separate `activeId` that can be **null with profiles present** (`AiProviderSnapshot.active = profiles.firstOrNull { it.id == activeId }`, AiProviderStore.kt:34–36), and key usability depends on **decrypting the active profile's token** (`apiKey(profile) = cipher.decrypt(profile.encryptedApiKey)`, AiProviderStore.kt:108). A cipher/keystore failure maps to **not-ready, never a crash** (the resolve wraps the decrypt in `runCatching`). **Note:** the iOS Variant A design-note (`reader-ai-provider-entry.md:172–174`) derives `aiConfigured` from `providers.isEmpty == false`, and iOS #82 (`reader-ai-readiness.md`) adds a 4-gate readiness (flag + consent + provider + key). **Android has NO consent manager and NO feature flag** (#118 has neither — confirm during build); the Android gate is exactly what #118 enforces = **provider (active) + key (decrypts non-empty)**. We do NOT invent a consent/flag gate.

### New files

**Pipeline / domain (host-agnostic, pure or coroutine — JVM-testable):**

- `bilingual/TranslationUnitId.kt` — `data class TranslationUnitId(kind, value)` with `enum Kind { epubHref, foliateHref, txtDocSegmentWindow, mdDocSegmentWindow, pdfPageRange }`; `storageKey = "${kind.name}:$value"`. TXT/MD kinds are **document-global segment-window indices** (H1), NOT chunk indices. v4 uses `epubHref` + `txtDocSegmentWindow`/`mdDocSegmentWindow`; others reserved so the cache-key format never breaks. *(Assumption: iOS's exact Kind case names for the TXT/MD variants; only the `storageKey` string format is load-bearing for the cache contract, and that is preserved.)*
- `bilingual/TranslationGranularity.kt` — `enum { paragraph, sentence }`. (Design's Granularity control; sentence-render is design-gated per H2.)
- `bilingual/BilingualLanguages.kt` — `BilingualLanguage(key, glyph, script)`; `BILINGUAL_LANGS` = the exact set from `vreader-bilingual.jsx:15–25` (Chinese/Japanese/Korean cjk, Spanish/French/German/Italian latin, Arabic rtl, Russian cyrillic) + `findOrDefault(key)`. Default `Chinese`.
- `bilingual/ChapterSegmenter.kt` — **NEW file (no existing Android segmenter — verified).** Port of iOS `ChapterSegmenter`: `paragraphs(text)` / `sentences(text)` **plus the range-returning peers `paragraphRanges(text): List<IntRange>` / `sentenceRanges(text): List<IntRange>`** (half-open UTF-16 spans against the input string — iOS `sentenceRanges(in:)` precedent). Ranges are exposed as explicit `(start, endExclusive)` pairs to the render side (H1). CJK-aware sentence enumeration (`。！？` vs Latin). Pure.
- `bilingual/TranslationChunker.kt` — `chunk(segments, maxCharsPerChunk)` + `subSplit(text, maxChars)`. Port of iOS `ChapterTranslationChunker.chunk(...)` (`ChapterTranslationChunker.swift:85`) + `subSplit(...)` (returns index groups, oversize segment gets its own chunk; `subSplit` is the Bug #330 grapheme-safe over-budget splitter).
- `bilingual/TranslationChunkContract.kt` — `userPrompt(segments, targetLanguage)`; `decode(raw, expectedCount)` (strict JSON-array + code-fence strip); `sealed class DecodeError { NotAStringArray; CountMismatch(expected, actual) }`. Port of iOS `TranslationChunkContract` (`TranslationChunkContract.swift:24`). No `style` param — Style descoped v1 (§3).
- `bilingual/ChapterTextProvider.kt` — `interface { units(); sourceSegments(unit); sourceText(unit); unitContaining(charOffsetUTF16); unitAfter(unit) }`. `sourceSegments(unit)` returns the exact segment strings (from the shared range array). Resolution is host-specific: TXT/MD key on `charOffsetUTF16` → segment-window; EPUB keys on the current-resource `href`. Honest divergence from iOS's uniform Readium `Locator`, documented.
- `bilingual/TxtChapterTextProvider.kt` — provider over `TxtDocument` + the segmenter's range array (H1). Builds the document-global segment `(start, endExclusive)` ranges once, groups them into windows, resolves `unitContaining` via a segment-start binary search over `charOffsetUTF16`. MD source = raw markdown segment text.
- `bilingual/EpubChapterTextProvider.kt` (WI-0-gated shape) — provider over the Readium `Publication` reading order; `units()` = spine hrefs, `unitContaining` = the locator's href (from `EpubNavigatorFragment.getCurrentLocator()`), `sourceSegments(unit)` = the DOM-enumerated block texts (the render's OWN enumeration, for direct-block 1:1 — H2). Its render-side collaborator is `EpubBilingualJs`.
- `bilingual/ChapterTranslationError.kt` — `sealed { Offline; TimedOut; ProviderFailed(msg); Cancelled }`. Maps from `AiError` (verified cases `Auth401`, `RateLimited429`, `Offline`, `Timeout`, `Http(code)`, `Decode`, `Stream`, `InsecureUrl`, `Config`, AiTypes.kt).
- `bilingual/ChapterTranslationService.kt` — the iOS-parity service (full divergence-recovery surface, round-2 H2):
  - `cachedTranslation(bookKey, unit, sourceText, targetLanguage, granularity, acceptCountMismatch=false)` — cache-only; serves a row only when `sourceParagraphCount == segments.size` (or `acceptCountMismatch`). No provider (#306 parity).
  - `cachedTranslation(bookKey, unit, expectedSegmentCount, targetLanguage)` — the divergence-fallback cache-only restore (iOS Bug #343): serves the canonical row only when its STORED `sourceParagraphCount == expectedSegmentCount`. Needs no source text and no provider → a cache-hit toggle/reopen restores with **zero provider calls**.
  - `translate(bookKey, unit, sourceText, targetLanguage, providerProfile, granularity, bypassCacheRead=false)` — segment → chunk → per-chunk `AiClient.chat` one-shot → `decode` → per-segment fallback → per-chunk graceful degrade (Bug #330) → cache-write only on full success (`sourceParagraphCount = segments.size`). **Cancellation:** maps BOTH native `CancellationException` AND typed `ChapterTranslationError.Cancelled` to `Cancelled` (mirrors iOS `ChapterTranslationService.swift:359–364`); `ensureActive()` between chunks AND immediately before the Room write.
  - `translatePreSegmented(bookKey, unit, segments, targetLanguage, providerProfile)` — the count-divergence recovery (iOS Bugs #268/#330/#343). Takes the render's OWN enumerated block texts as `segments` (1:1), chunks them, translates with the same per-chunk graceful-degrade + dual-cancellation contract, and — on full success only — caches under the canonical key with the ENUMERATE's count as `sourceParagraphCount`. A partial degrade is NOT cached; a cache-write failure does not fail the translation (iOS `ChapterTranslationService.swift:374–384`).
  - Uses `AiClient.chat(AiRequest)` (one-shot, verified — NOT `streamChat`).
- `bilingual/ChapterTranslationPrefetcher.kt` — resolves the active profile from one `AiProviderStore.snapshot()` (`snapshot.active`), decrypts via `store.apiKey(profile)` (snapshot-consistent, AiProviderStore.kt:108), builds an `AiClient` via an **injected factory param** (below), cache-first then translate. Adds the direct-block peers (H2):
  - `prefetch(unit)` — the plain-text path.
  - `prefetchDirect(unit, sourceSegments, targetLanguage)` — the divergence path (iOS `translatedSegmentsDirect`, `ChapterTranslationPrefetcher.swift:197`).
  - `cachedDirect(unit, expectedCount, targetLanguage)` — the **zero-provider cache-only restore** (iOS `cachedSegmentsDirect` → `cachedTranslation(expectedSegmentCount:)`, `ChapterTranslationPrefetcher.swift:236`): returns a cached translation on a hit WITHOUT requiring an active provider (#306 pre-gate precedent). Backs the EPUB cache-restore path.
  - **`AiRequest` construction (round-3 M3 fix, BINDING):** `model = profile.model.ifBlank { profile.kind.defaultModel }` — matches `AiChatViewModel.kt:61`; both wire clients serialize `request.model` **directly** (`put("model", request.model)` in `OpenAiCompatibleProvider.kt:39` and `AnthropicProvider.kt:37`), so a blank `profile.model` would send an empty model. Full request: `AiRequest(model = profile.model.ifBlank { profile.kind.defaultModel }, messages = …, temperature = profile.temperature, maxTokens = profile.maxTokens, system = …)`. A **blank-model regression test** asserts the fallback is applied.
  - Throws `ChapterTranslationError`. Mirrors iOS `ChapterTranslationPrefetcher`.
- `bilingual/BilingualAiReadiness.kt` — `resolve(snapshot: AiProviderSnapshot): Boolean` — active profile exists (`snapshot.active != null`) AND `runCatching { store.apiKey(snapshot.active).isNotEmpty() }.getOrDefault(false)` (cipher/decryption failure → **not-ready**, never crashes). Drives the setup-sheet engine-strip configured/unconfigured state. Exactly the #118 gate (no consent manager / feature flag on Android — confirm during build).

**State / persistence:**

- `bilingual/PerBookBilingualStore.kt` — DataStore-Preferences, keyed by `bookFingerprintKey`, holding `{ enabled, targetLanguage, granularity }`. The Android `PerBookSettingsOverride` bilingual slice — the backup contract declares exactly `bilingualEnabled` / `bilingualTargetLanguage` / `bilingualGranularity` and **NO `bilingualStyle`** (verified). Wiring into backup collect/restore is scoped OUT (§7); until then bilingual config is device-local.
- `bilingual/BilingualViewModel.kt` — `StateFlow<BilingualUiState>` with `enabled`, `targetLanguage`, `granularity`, `needsSetupSheet`, `aiConfigured`, `translationsByUnit`, `inFlightUnits`, `unavailableUnits`, `errorUnit`. Setters + `dismissSetupSheet`, `onPositionChanged(charOffsetUTF16)`, `retryUnit(unit)`, and the EPUB direct-block entry `onEpubBlocksEnumerated(unit, blocks)` (M1, below). Generation/epoch-guarded prefetch (current + next unit); a **per-unit single-flight job registry** (M2); dual-cancellation handling (M2). Port of iOS `BilingualReadingViewModel` (`prefetchTasks: [TranslationUnitID: Task]`, `BilingualReadingViewModel.swift:141`) + `+Prefetch`. Split to `BilingualPrefetchController.kt` if it nears ~300 lines. No `style` field.

**Room (translation cache):**

- `data/ChapterTranslationEntity.kt` — `@Entity(tableName="chapter_translations", indices=[Index("bookKey")], foreignKeys=[FK→books.fingerprintKey ON DELETE CASCADE])`. **`@PrimaryKey val lookupKey: String`** (Room requires a PK; project pattern `@PrimaryKey` + `@Upsert`, verified `BookEntity`/`BookDao`). `lookupKey` = `bookKey|unitStorageKey|targetLanguage|promptVersion`. Columns: `bookKey`, `unitStorageKey`, `targetLanguage`, `promptVersion`, `translatedJson`, `sourceParagraphCount`, `createdAt`. Mirrors iOS `ChapterTranslationRecord.lookupKey` (`book|unit|lang|prompt`, profile-agnostic — Bug #342). `sourceParagraphCount` is load-bearing for H2 (stores the enumerate's count on the `translatePreSegmented` path so `cachedTranslation(expectedSegmentCount:)` restores).
- `data/ChapterTranslationDao.kt` — `getByLookupKey(key)`, `@Upsert suspend fun upsert(row)`, `deleteByLookupKey(key)`.
- `bilingual/ChapterTranslationStore.kt` — coroutine wrapper returning a `CachedTranslation` (segments decoded from JSON), keeping Room entities off the boundary (iOS `ChapterTranslationStore` precedent).

**Cache-identity (reconciled with iOS parity):** the 4-part key `book|unit|lang|promptVersion` is profile-AGNOSTIC / style-agnostic (Bug #342). Style is descoped (§3) so no `s=` component. **Granularity IS user-selectable**, carried in `promptVersion` as an effective composite: `promptVersion = "bilingual-v1|g=${granularity}"` (a paragraph vs sentence translation is a different cache row — closes the iOS #344 "sentence silently ignored" class by construction; also means the H2 sentence design-gate never serves a paragraph row as sentences). A granularity change cancels in-flight jobs, bumps the VM generation, clears shaped `translationsByUnit`, and forces a correctly-keyed re-fetch (WI-6).

**DI / factory (verified live):** `AiProviderFactory` is an `object` with `create(profile, apiKey, dispatcher = Dispatchers.IO): AiClient` (verified, `AiProviderFactory.kt:10`). `ChapterTranslationPrefetcher` takes its OWN injected `clientFactory: (AiProviderProfile, String) -> AiClient` param **defaulting to `AiProviderFactory::create`**, overridden with a fake in tests.

**UI (Compose — every state depicted, reproducing `vreader-bilingual.jsx` + `vreader-ai-provider-entry.jsx`):**

- `bilingual/BilingualSetupSheet.kt` — reproduces `vreader-bilingual.jsx`'s `BilingualSetupSheet` (lines 27–156) EXACTLY: header; a preview strip (`BilingualPreview`); a language grid over `BILINGUAL_LANGS` (glyph tiles, selected accent); a **Granularity** segmented control (Paragraph "Translate after each ¶" / Sentence "Translate after each sentence"); a **Translation engine** strip (configured: "Claude · with this book's context" + "Change…"; unconfigured: "No AI provider configured" + "Bilingual mode needs an AI provider to translate." + "Set up"); the "Turn on bilingual mode" CTA. **No Style control, no provider/model card, no term-overrides toggle, no cost footer** (those belong to the `vreader-ai-android.jsx` sheet, not reproduced — §3). The `aiConfigured` flag comes from `BilingualAiReadiness.resolve`. The "Set up"/"Change…" CTA routes to `ReaderAiProvidersSheet` (wired in WI-9).
- `bilingual/ReaderAiProvidersSheet.kt` — **NEW (folded in; the Android analog of iOS `ReaderAIProvidersView`).** The Variant A scoped in-reader AI Providers sheet, reproducing `vreader-ai-provider-entry.jsx` `AIProvidersSheet` + `NavSheet` (nav bar `‹ Bilingual` leading + centered "AI Providers" title). It hosts **ONLY the provider list** — nothing else from settings. It **reuses the #118 `AiProviderListScreen` (list, empty + populated states) and `AiProviderEditSheet` (the canonical add/edit modal) VERBATIM**, driven by the #118 `AiSettingsViewModel` (`listState`, `editState`, `openAdd/openEdit/save/setActive`, verified `AiSettingsViewModel.kt`). Behavior per the nav model:
  - **Empty state** shows the bilingual-context copy "Bilingual mode needs a provider to translate" + an "Add provider" CTA (the design-note's line 47–49 copy; `AiProviderListScreen`'s `AiEmptyState` already renders an equivalent "Add a provider" CTA — the bilingual-context line is the sheet's own header context strip per `AIProvidersSheetBody`, `vreader-ai-provider-entry.jsx:167–183`).
  - **Add provider** presents `AiProviderEditSheet` unchanged; **on the first Save** the new provider becomes active/the bilingual engine and the stack **pops all the way back** to the bilingual sheet with the engine strip now reading "Claude · configured / Change…". (First-provider-active is already the store's behavior — `AiProviderStore.upsert` sets `activeId = cur.activeId ?: id`, AiProviderStore.kt:81; the sheet additionally calls `store.setActive(savedId)` on the first-Save-from-bilingual path so the freshly-saved provider is the engine even if others existed.)
  - `‹ Bilingual` **without adding** returns unconfigured — **no state mutated.**
  - "Change…" opens the SAME sheet, populated, current provider checked (tapping a row → `setActive`).
  - No consent card, no feature-flag toggle, no readiness tracker (that is iOS #82, deferred — §"AI-config reachability").
- `bilingual/BilingualInterlinearBody.kt` — the Compose render surface for the **TXT/MD host ONLY** (round-2 M2). Emits the **additive translation `LazyColumn` items** per the H2 render contract (source chunks unchanged; translation items after the anchor chunk): muted `Text`, accent left-border, `fontSize*0.88`, CJK font for cjk scripts, RTL handling for Arabic (per `BilingualPageContent`, `vreader-bilingual.jsx:200–277`). Consumes the host-neutral `BilingualRenderState` DTO. Loading state ("Translating chapter… N%" + per-segment dim), error state ("Couldn't translate" + Retry), partial/offline (`unavailableUnits`): source-only silent fallback (iOS Decision 2). **NOT the EPUB render surface.**
- `bilingual/BilingualRenderState.kt` — the host-neutral state DTO shared by the Compose body and the EPUB adapter (round-2 M2): per-unit `{ segments: List<String>?, phase: Loaded|Loading(fraction)|Error|SourceOnly }`. Compose and EPUB share the state/value types, NOT the composable body.
- `bilingual/EpubBilingualJs.kt` (WI-0-gated) — the EPUB render surface (round-2 M2). Pure Kotlin builder producing JS strings for `navigator.evaluateJavascript(...)`: `enumScript` (enumerate current-resource leaf blocks → JSON `[{id,text}]`), `injectScript(blockId, translationText)` (translation DOM node after the block; CSP-safe: `textContent`/`createTextNode`, never `innerHTML` string-concat; RTL/CJK via class + injected `<style>`), `clearScript()` (idempotent removal). Escaping done in Kotlin (JSON-encode every interpolated string). No Compose. Consumes `BilingualRenderState`.
- `bilingual/EpubBilingualController.kt` (WI-0-gated) — **the single owner of EPUB units (M1, below).** The runtime actor that serializes enumerate→(cache-restore|translate)→inject/clear against the navigator using WI-0's chosen mechanism (a single mutex OR a monotonic navigator-session token); checks the session token after every suspended JS/AI call; clears BEFORE publication teardown; re-applies on the identified production re-apply signal.
- `bilingual/BilingualPill.kt` — the `EN ↔ 中` reader-top-chrome pill (per `vreader-reader.jsx` + `vreader-bilingual.jsx` `BilingualPill`:282–305). Rendered by #132's top chrome; #131 provides the composable, #132's surface hosts it (§4).

### EPUB direct-block flow — one owner + concrete API (round-3 Medium-1, BINDING)

The **`EpubBilingualController` is the SINGLE OWNER of EPUB units**; the VM's position-driven regular `prefetch` path is **TXT/MD-only**. Concretely, an EPUB position change routes THROUGH the controller (the VM does not run `prefetch(unit)` for `epubHref` units), so the **controller is the sole writer** of an EPUB unit's canonical cache row and its `BilingualRenderState`/`translationsByUnit` entry — the position-driven regular prefetch and the direct-block path can never both write the same canonical cache row. The control flow (every suspended step session-token-guarded):

```
enumeratedBlocks = navigator.evaluateJavascript(EpubBilingualJs.enumScript)   // [{id,text}] for current resource
        │  (session token S captured before the call; re-checked after)
        ▼
count = enumeratedBlocks.size
restore = prefetcher.cachedDirect(unit, expectedCount = count, targetLanguage)  // zero-provider cache restore
        │
        ├─ hit  → segments = restore
        └─ miss → segments = prefetcher.prefetchDirect(unit, sourceSegments = enumeratedBlocks.texts, targetLanguage)
        │  (token re-checked after each suspension; a stale token → discard, no commit, no error surfaced)
        │  (token re-checked after each suspension; a stale token → discard, no commit, no error surfaced)
        ▼
if token S still current:  commit segments → BilingualRenderState[unit] / translationsByUnit[unit]  (single writer)
        ▼
EpubBilingualJs.injectScript per (blockId, translation)  via navigator.evaluateJavascript   // token-guarded
```

- The VM exposes `onEpubBlocksEnumerated(unit, blocks)` as the controller's entry into VM render state, but the **controller owns the enumerate→cachedDirect/prefetchDirect→guarded-commit sequence**; the VM never initiates an EPUB prefetch itself (its position-driven `prefetch` dispatches only `txtDocSegmentWindow`/`mdDocSegmentWindow` units). A stale session token at any commit point discards silently (no `errorUnit`).
- WI-7b's connected test asserts: enable → inject; disable → clear; reflow/href-change/fragment-recreation/activity-recreation → re-apply from cache via `cachedDirect` (zero provider calls); count-divergence handled via `prefetchDirect`; and that the regular TXT/MD prefetch path is never invoked for an EPUB unit.

### Cancellation + single-flight (round-3 Medium-2, BINDING)

- **Dual-cancellation across the service/VM boundary:** both the service AND the VM handle **BOTH** native `CancellationException` **AND** the typed `ChapterTranslationError.Cancelled` **before** generic error mapping — matching iOS `ChapterTranslationService.swift:359–364` (which catches `is CancellationError` and `ChapterTranslationError.cancelled` separately, both re-throwing `cancelled`). A cancelled stale request MUST NOT surface as `errorUnit` (it is discarded).
- **Per-unit single-flight job registry (VM):** a `prefetchTasks: MutableMap<TranslationUnitId, Job>` (iOS `prefetchTasks: [TranslationUnitID: Task]`, `BilingualReadingViewModel.swift:141`, cancelled/removed on disable/unit-change at :165). A NEW request for a unit **cancels-or-joins** the prior job (a stale prior is cancelled and awaited so it cannot run overlapping translations or Room writes), keyed by unit. Rapid retry/navigation cannot run overlapping translations for the same unit. `retryUnit(unit)` goes through the same registry. Tests: a mid-flight cancel discards (no `errorUnit`, no partial cache row); a rapid re-trigger for the same unit does not double-write.

### Modified files

- `data/VReaderDatabase.kt` — add `ChapterTranslationEntity` to `@Database entities`, bump `version` **8 → 9** (the live DB is v8, migrations `MIGRATION_1_2`..`MIGRATION_7_8`, `ALL_MIGRATIONS` ends at `MIGRATION_7_8` — verified VReaderDatabase.kt:29,224–228), add **`MIGRATION_8_9`** (CREATE TABLE `chapter_translations` + `bookKey` index + FK→`books.fingerprintKey` CASCADE, DDL exactly matching Room's generated schema), **append `MIGRATION_8_9` to `ALL_MIGRATIONS` after `MIGRATION_7_8`**, add `abstract fun chapterTranslationDao()`. Purely additive.
- `reader/TxtReaderActivity.kt` — own a `BilingualViewModel`; collect state; render translations as **additive items after the anchor chunk in the existing `items(count = document.chunkCount, key = { it })` loop (TxtReaderActivity.kt:1043), source chunks byte-unchanged (H2)**; on position change call `vm.onPositionChanged(charOffsetUTF16)`. Strictly gated to `originalFormat ∈ {txt, md}`; disabled = body byte-unchanged (overlay-only). **Owned by #129 (VERIFIED, merged) — a straight edit, rule 48 one-writer-per-file satisfied.**
- `reader/ReaderActivity.kt` (Readium EPUB) — WI-0-gated: attach `EpubBilingualController` to `navigator.evaluateJavascript`; re-apply on the identified production re-apply signal; clear on teardown BEFORE publication teardown. `navigator: EpubNavigatorFragment?` is the verified live field (ReaderActivity.kt:110).
- `reader/chrome/ReaderChromeScaffold.kt` — extend `readerMoreRows(...)` (currently supplies only `MoreActionId.DETAILS` + `SHARE`, ReaderChromeScaffold.kt:255–258) to ALSO supply the **`MoreRow.Toggle(id = MoreActionId.BILINGUAL, on = enabled, onToggle = …)`** row (or `MoreRow.Disabled` "Configure AI provider first" when not configured — `MoreRow.Disabled` exists for exactly this, MoreRow.kt:65–72). Threaded via new nullable params so #132/#134-only callers stay valid (the scaffold's established nullable-default pattern). This is the WI-9 entry-wiring edit.
- `VReaderApp.kt` / `AppContainer` — **provide `AiProviderStore` INTO `AppContainer` itself** (it is NOT provided today — verified, only a comment names it at VReaderApp.kt:66) using the #116 `KeystoreSecretCipher` + a DataStore under the same convention as `readerSettingsStore`, PLUS provide `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, an `AiSettingsViewModel` factory (for the Variant A sheet), and a `BilingualViewModel` factory. **Extracted into the shared DI WI (WI-4b).** No `feat:#136` dependency remains — #131 owns the `AiProviderStore`-into-`AppContainer` wiring.

**NOT modified:** `reader/chrome/ReaderBottomChrome.kt` gets **no** bilingual/Translate slot — the design's entry is the More-menu toggle (#134) + the top-chrome pill (#132), NOT a bottom-chrome slot. `ReaderBottomChrome`'s existing `extraSlot` is untouched.

### Files OUT of scope for v1

- **`Azw3ReaderActivity.kt` / `reader/foliate/`** — foliate WebView interlinear IS feasible but deferred (bundle-patch JS + secure-bridge additions touch the security-sensitive #126 surface). Once WI-0 proves the EPUB JS pipeline, the foliate host reuses `EpubBilingualJs` with a bundle adapter.
- **`PdfReaderActivity.kt`** — no reflowable text layer. Out (`pdfPageRange` Kind reserved only).
- **Backup collect/restore of `PerBookSettingsOverride` bilingual fields** — contract fields exist; wiring is a small additive follow-up (§7). Device-local until then.
- **Style control** — descoped v1 (user decision, §3). Keep provider/model/**granularity**, DROP the bilingual "Style" control.
- **Sentence-granularity interlinear RENDER** — not depicted (H2); design-gated. v1 renders the depicted paragraph pattern; Sentence selection falls back to paragraph render (cache still granularity-keyed).
- **The iOS #82 readiness sheet (feature-flag + consent gates)** — `reader-ai-readiness.md` is iOS-specific and implementation-deferred; Android has no flag/consent, so the Variant A provider-list sheet is the whole AI-config surface. Out.
- **"Translate entire book…" batch, re-translate/style-swap picker, cost/token estimation, term-overrides** — iOS/`vreader-ai-android.jsx` extras not in the authoritative sheet. Out.
- **Streaming translation progress** — the design's "38%" is chapter-level N-of-M chunk progress, not token streaming. v1 shows N-of-M.

## 3. Prior art / project precedent / rejected alternatives

### The render-host decision (settled v2, CONFIRMED round-2)

**How iOS does interlinear:** iOS renders EPUB/AZW3 in a WKWebView it fully controls. `EPUBBilingualOrchestrator` injects JS that (1) enumerates leaf blocks posting `[{bid,text}]` to Swift, (2) after translation injects a translation node after each block. TXT/MD render in a text path where the renderer interleaves translation runs. The mechanism = **the app inserts translation nodes between source nodes** — which is exactly the Android additive-item contract (H2) for TXT/MD and the DOM-inject contract for EPUB.

**Android EPUB feasibility (round-2 re-verified):** the transformed API JAR on the resolved Readium 3.3.0 AAR (build.gradle.kts:111) exposes public `evaluateJavascript`, `getCurrentLocator()`, `firstVisibleElementLocator(...)`, `submitPreferences(...)`; `ReaderActivity.navigator: EpubNavigatorFragment?` holds the concrete fragment (ReaderActivity.kt:110). EPUB interlinear via JS injection is feasible with the public API — **no Readium fork.** Not reopened.

**WI-0 — Readium bilingual spike (gates WI-7b; round-2 M1):** a throwaway harness that, against a real EPUB on the emulator, must PROVE each go/no-go criterion: (a) enumeration deterministic + idempotent with stable node IDs (repeat apply = no duplicate nodes); (b) clear wins over every older inject (a late inject checks the session token and no-ops); (c) recreation restores from cache for every case (href away/back, same-href `submitPreferences` reflow, internal page-fragment recreation, activity recreation) via `cachedDirect(expectedCount)` (zero provider calls) with an identified PRODUCTION re-apply signal per case; (d) locator/visible-source preservation across injection (stated permissible pagination delta); (e) enumerated block count vs segmenter count measured — divergence → the direct-block path (`prefetchDirect`/`cachedDirect`, H2) is the recovery, proven end-to-end. **Race contract:** single actor/mutex OR monotonic navigator-session token; token/mutex check after every suspended JS/AI call; clear before publication teardown. **No deterministic re-apply signal for a recreation case (c) = explicit NO-GO** → EPUB drops to a tracked follow-up, box D ships **TXT/MD-only** with the honest reason (a specific spike finding), never the false "requires a fork."

**Rejected alternatives:**
1. **Readium interlinear via decorations only** — REJECTED (decorations style existing text; they cannot insert translation paragraphs).
2. **Forking Readium** — REJECTED + unnecessary (public `evaluateJavascript` seam exists).
3. **AZW3 foliate host first** — REJECTED for v1 (deferred; touches the security-sensitive #126 bridge).
4. **Eager whole-book pre-translation** — REJECTED (cost/latency). Lazily prefetch current+next + cache.
5. **One `BilingualInterlinearBody` per chunk (v2)** — REJECTED (round-2 H1): a chunk is not a segment.
6. **A Compose body as the EPUB render surface (v2)** — REJECTED (round-2 M2): Compose cannot render inside Readium's WebView.
7. **Splitting a chunk's source `Text` into per-segment `Text` nodes to interleave translations (v3)** — REJECTED (round-3 H2): breaks the live one-`TextLayoutResult` + one-selection-registration-per-chunk model. Replaced by additive `LazyColumn` items at chunk boundaries, source `Text` never split.
8. **Deriving `aiConfigured` from `profiles.isEmpty()` (the iOS Variant A note's derivation)** — REJECTED for Android: `activeId` can be null with profiles present, and key usability needs the active profile's token to decrypt (H3). Android uses `BilingualAiReadiness.resolve` = active-profile + decrypts-non-empty.
9. **Spinning AI-config reachability out as a separate feature #136** — REJECTED / CLOSED (2026-07-12): the design proved the ONLY designed Android AI-config reader surface is bilingual-coupled Variant A; there is no designed standalone entry, so it is not separable. #131 owns it.

### The setup-sheet resolution (rule 51) + Style descope (round-2 H3, USER DECISION)

There are **two committed, differently-shaped** `BilingualSetupSheet`s:
- `vreader-bilingual.jsx` → **language grid + Granularity + preview strip + Translation-engine strip (Set up/Change) + Cancel/Translate**. No Style, no provider/model card, no term-overrides, no cost.
- `vreader-ai-android.jsx` → **Languages (From/To) + Provider card + Style (Literal/Natural/Literary) + Keep-term-overrides toggle + cost footer**. No language grid, no Granularity, no preview.

**Resolution:** this plan reproduces the **`vreader-bilingual.jsx` sheet EXACTLY**. **Style is DESCOPED for v1** (user decision): keep provider/model/**granularity**, DROP the bilingual "Style" control. Consequently store/VM carry no `style`, the chunk contract has no `style` param, and the cache key's `promptVersion` has no `s=` component.

**Box-D parity note (do NOT claim full box-D parity):** the box-D checklist lists provider/model/**style**. Because Style is descoped, **WI-9 flips box D to done ONLY for provider/model/granularity + a descope note**; a follow-up tracker/checklist amendment records the Style descope. If Style is later wanted, that needs an updated committed design (a single sheet showing BOTH Style AND Granularity is not depicted anywhere — the one Style design gate below).

### The AI-config path (rule 51) — Variant A is the committed design

The canonical decision (`reader-ai-provider-entry.md`, Variant A) + its component canvas (`vreader-ai-provider-entry.jsx`) ARE the committed design; #131 reproduces only what they depict (a `‹ Bilingual`-titled push sheet hosting the #118 provider list + the canonical editor, pop-back-on-first-save). No AI-config sheet or nav is invented. The iOS #82 readiness additions (flag/consent) are explicitly **out** on Android (no such subsystems exist). This is a designed surface — it is NOT a design gate.

### Other precedents applied

- **#118 provider seam**: reuse `AiProviderStore.snapshot()` (`snapshot.active`) + `store.apiKey(profile)` + `AiProviderFactory.create` (default of an injected factory param) + `AiClient.chat`. #118's AI files are unchanged; #131 wires `AiProviderStore` into `AppContainer` and reuses `AiProviderListScreen`/`AiProviderEditSheet`/`AiSettingsViewModel` verbatim for the Variant A sheet.
- **Room additive-migration pattern** (#122/#123/#127/#128/#135): version bump + `MIGRATION_n_(n+1)` appended to `ALL_MIGRATIONS` + exact-DDL + `VReaderDatabaseMigrationTest` PRAGMA guard. `@PrimaryKey` + `@Upsert` is the project DAO pattern (`BookDao`). Baseline v8.
- **DataStore JSON-in-Preferences** for `PerBookBilingualStore` (the `ReaderSettingsStore`/`AiProviderStore` pattern).
- **Pure-logic port**: iOS `ChapterSegmenter`/`ChapterTranslationChunker`/`TranslationChunkContract`/`ChapterTranslationService.translatePreSegmented`/`ChapterTranslationPrefetcher.translatedSegmentsDirect`+`cachedSegmentsDirect` are pure/heavily-unit-tested — direct Kotlin ports with the same test vectors (all verified to exist).
- **Single-flight job registry**: iOS `prefetchTasks: [TranslationUnitID: Task]` (`BilingualReadingViewModel.swift:141`) — ported as `prefetchTasks: Map<TranslationUnitId, Job>` (M2).
- **Entry point via #132/#134 (VERIFIED)**: the More-menu bilingual toggle (`MoreActionId.BILINGUAL` reserved; `MoreRow.Toggle`/`MoreRow.Disabled`) + top-chrome pill are landed; #131 mounts the pill + wires the toggle (§4).

## 4. Work-item sequencing

**13 WIs/PRs (round-3 Low-1 fix — corrected count):** the list is exactly **WI-0, WI-1, WI-2, WI-3, WI-4a, WI-4b, WI-5, WI-6, WI-7a, WI-7b, WI-AIP, WI-8, WI-9** = **13 WIs**. (v3 had 12: WI-0,1,2,3,4a,4b,5,6,7a,7b,8,9. Folding in the Variant A "AI Providers" sheet adds **WI-AIP**, making 13. The prior "11 WIs" claim in the plan header and `docs/features.md` was wrong on two counts and is corrected here.) Each WI = one PR. Build order: **foundation/cache → service/direct-block APIs → shared DI/factory (incl. `AiProviderStore` in `AppContainer`) → VM state/prefetch → host-specific renderers (TXT/MD + EPUB) + the Variant A AI Providers sheet → entry wiring.**

**Dependencies (round-3 Medium-4 — dependency honesty; #136 folded in):**

- **`Deps: [feat:#132, feat:#134]`.** **#132 (top chrome) and #134 (More menu) are VERIFIED.** **#129 (TXT/MD reader) is VERIFIED** — `TxtReaderActivity` is a straight edit, not a blocker. **There is NO external AI-reachability blocker** — the former #136 is CLOSED (GH #1976, not-planned) and its scope is #131-owned.
- **WI-4b is foundational and gates the behavioral chain.** WI-4b now provides `AiProviderStore` into `AppContainer` PLUS the bilingual services + factories. Per the audit's Medium-4, WI-4b transitively gates WI-6 (needs the prefetcher/DI), WI-7b (needs DI), WI-AIP (needs `AiProviderStore` + `AiSettingsViewModel` from `AppContainer`), and WI-8 (needs DI). **Chosen resolution: injected seams so the behavioral work proceeds against fakes before WI-4b lands, AND WI-4b is sequenced early.** Concretely: the VM (WI-5/WI-6) takes an injected `ChapterTranslationPrefetcher` (fake in tests) and an injected `AiProviderSnapshot` provider (fake); the TXT/MD host Compose/unit work (WI-8) and the Variant A sheet (WI-AIP) take injected VM/store/`AiSettingsViewModel` seams — so unit/Compose tests do not wait on `AppContainer`. **WI-4b is built right after WI-4a (before WI-6/WI-7b/WI-AIP/WI-8) so the production wiring lands before the host integrations that mount it.** This is stated honestly: the *production run-through* of WI-6/WI-7b/WI-AIP/WI-8 depends on WI-4b; their *unit/Compose gates* depend only on the injected seams. No external feature gates any of this.

**WI-0 (spike): Readium EPUB bilingual injection — go/no-go + race contract (M1).** Harness + criteria (a)–(e) and the race contract in §3. Output: a go/no-go on EPUB-in-v1 (no-go = box D ships TXT/MD-only, tracked) + the concrete `EpubChapterTextProvider` / `EpubBilingualJs` / `EpubBilingualController` surfaces + the EPUB direct-block ownership sequence (Medium-1). Deps: none (uses the existing #106 Readium host). Not TDD-gated (throwaway spike); feeds WI-7b.

**WI-1 (foundational): value types + pure segmentation/chunk/contract.** `TranslationUnitId`, `TranslationGranularity`, `BilingualLanguages`, **`ChapterSegmenter` (with `paragraphRanges`/`sentenceRanges` returning half-open UTF-16 `(start, endExclusive)` spans — H1)**, `TranslationChunker`, `TranslationChunkContract` (no `style`), `ChapterTranslationError`. Pure; ported iOS vectors. Deps: none.

**WI-2 (foundational): Room translation cache.** `ChapterTranslationEntity` (PK = `lookupKey`, `sourceParagraphCount` column) + `Dao` (`@Upsert`) + `ChapterTranslationStore`; `VReaderDatabase` **8→9 `MIGRATION_8_9`** appended after `MIGRATION_7_8`. Robolectric migration round-trip from v8 + full-chain + upsert/get/delete-by-lookupKey + FK-CASCADE + exact-DDL guard. Deps: none.

**WI-3 (foundational): `ChapterTranslationService`** against a fake `AiClient`. Both `cachedTranslation` overloads (incl. the `expectedSegmentCount` divergence restore — H2) + `translate` + `translatePreSegmented`. **Dual-cancellation (native + typed `Cancelled`) BEFORE generic mapping (M2).** Deps: WI-1, WI-2. Tests: cache hit → zero client calls; miss → translate + write; decode fail → per-segment fallback; one-chunk fail → source-only that chunk (others translated, NOT cached); all-chunks fail → throw; native-cancel → `Cancelled` (no write); typed-`Cancelled`-from-chunk → `Cancelled` (no write); ensureActive-before-write; `AiError` mapping incl. `Config`/`InsecureUrl` → `ProviderFailed`; `translatePreSegmented` full-success caches under the enumerate count; partial degrade NOT cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` returns on stored-count match, null on mismatch, needs no provider.

**WI-4a (foundational): `ChapterTextProvider` (TXT/MD) + `ChapterTranslationPrefetcher` + `BilingualAiReadiness`.** `TxtChapterTextProvider` builds the document-global segment `(start, endExclusive)` ranges once (H1), groups into windows, resolves `unitContaining(charOffsetUTF16)` via segment-start binary search, `sourceSegments(unit)`. Prefetcher: `prefetch` + `prefetchDirect` + `cachedDirect`; resolves active profile from `snapshot()`, decrypts snapshot-consistent, builds client via the injected factory param (default `AiProviderFactory::create`), constructs `AiRequest` with **`model = profile.model.ifBlank { profile.kind.defaultModel }` (M3)**. Readiness = active profile with non-empty decrypted key; **cipher failure → not-ready, never a crash.** Fake store + fake factory. Deps: WI-1, WI-3. Tests (all half-open-range-based): unit resolution + clamp + empty; **one-chunk document (no trailing newline) → its segment translation renders, not dropped (H1)**; **final-chunk anchor → renders (H1)**; **exact-boundary → correct anchor (H1)**; **EOF anchor (`segEndExclusive == text.length`) → last chunk, no clamp-collapse (H1)**; paragraph spanning MANY chunks → one segment/one unit, anchored to the last chunk (Low-2); multiple SENTENCES in one chunk → distinct sentence segments (Low-2); a >4000-char paragraph hard-split across chunks → one segment; CR/LF/CRLF; MD markers; locator→unit mapping; `unitAfter` end→null; **source-byte parity while disabled**; cache-hit-no-profile still returns (#306); no-profile miss → `ProviderFailed`; `prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls; **blank `profile.model` → `AiRequest.model == kind.defaultModel` (M3 regression)**; readiness true/false; empty-key → false; no-active-with-profiles-present → false (H3); cipher-throw → readiness false (no crash).

**WI-4b (foundational — shared DI/factory, incl. `AiProviderStore` in `AppContainer`): AppContainer bilingual + AI-config graph.** `AppContainer` **now constructs `AiProviderStore`** (DataStore + #116 `KeystoreSecretCipher`, following the `readerSettingsStore` convention — this is #131's change, not an external feature's) and provides `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, an `AiSettingsViewModel` factory (for WI-AIP), and the `BilingualViewModel` factory. Deps: **WI-4a** (no external dep — #136 closed). Tests: container resolves the bilingual + AI-config graph; `AiProviderStore` resolves and round-trips a profile; the prefetcher's injected factory defaults to `AiProviderFactory::create`.

**WI-5 (behavioral): `PerBookBilingualStore` + `BilingualViewModel` state core.** Store per book (enabled/targetLanguage/granularity — no style); VM setters (persist + first-enable `needsSetupSheet`); `aiConfigured` from `BilingualAiReadiness.resolve` over an injected snapshot; language/granularity change clears cache-shaped state + bumps generation. Injected prefetcher/snapshot seams (Medium-4). Turbine tests: first-enable raises sheet; re-enable persisted does not; disable clears; language change resets; granularity change resets + re-keys; `aiConfigured` true/false from readiness; round-trip through store; no style field. Deps: WI-1 (+ store).

**WI-6 (behavioral): VM prefetch trigger + generation/cancellation + single-flight (M2).** `onPositionChanged(charOffsetUTF16)` derives current unit (TXT/MD only), dedupes, prefetches current+next; a monotonic position-request sequence checked after every suspension; **per-unit single-flight `prefetchTasks: Map<TranslationUnitId, Job>` (a new request cancels/joins the prior — M2)**; a captured language/granularity/provider snapshot per launch; generation bumps on disable/language/granularity/unit-change discard stale; **BOTH `CancellationException` AND typed `ChapterTranslationError.Cancelled` handled BEFORE generic error mapping (M2)**; a cancelled stale request does NOT surface as `errorUnit`; `Offline`→`unavailableUnits`; transient failure leaves unit unfetched + clears anchor to retry; `retryUnit` routes through the registry. The EPUB `onEpubBlocksEnumerated` entry is present but EPUB prefetch is owned by the controller (Medium-1); the VM's position-driven `prefetch` dispatches TXT/MD units only. Fake prefetcher (Medium-4 seam). Deps: WI-4a, WI-4b, WI-5. Tests: current+next on unit change; same-unit no-op; cancel-mid discards stale (no `errorUnit`); typed-`Cancelled` discards (not `errorUnit`); rapid re-trigger same unit → single-flight, no double-write; offline→unavailable; failure→retry-able; `retryUnit` re-fetches; granularity change cancels + re-fetches under the new key.

**WI-7a (behavioral): Compose UI — setup sheet + interlinear body (TXT/MD) + pill.** Reproduce `vreader-bilingual.jsx` (setup sheet: language grid / granularity / preview / engine strip configured+unconfigured; body: the **additive translation items** per the H2 render contract — translated / loading N%+dimmed / error+Retry / offline source-only; pill). Consumes the host-neutral `BilingualRenderState` DTO. Light+dark. Compose UI tests each state, incl. **paragraph interlinear renders a translation item after a paragraph (depicted)** and **Sentence selection falls back to paragraph render (H2 gate)**. Deps: WI-5 (state shape). NO Style control; the unconfigured "Set up" CTA renders and (in WI-9) routes to the Variant A sheet.

**WI-7b (behavioral, CONDITIONAL — only if WI-0 = go): EPUB render adapter (DOM injection, NOT Compose — M2) + direct-block ownership (M1).** `EpubBilingualJs` (enum/inject/clear JS builders, CSP-safe escaping) + `EpubBilingualController` (the serialization actor / session token AND the **single-owner enumerate→cachedDirect/prefetchDirect→guarded-commit sequence — Medium-1**) + `EpubChapterTextProvider`, wired into `ReaderActivity`, driving DOM from the shared `BilingualRenderState` DTO. Uses `prefetchDirect`/`cachedDirect` for the count-divergence path (H2). Depends on WI-6 (VM state) and WI-4b (DI); the WI-7a UI dependency is only the shared `BilingualRenderState`/value types. Connected test on a real EPUB (seeded cache): enable → injects; disable → cleared; reflow/href-change/fragment-recreation/activity-recreation → re-applies from cache (zero provider calls) via `cachedDirect`; count-divergence handled (direct path); **the regular TXT/MD prefetch path is never invoked for an EPUB unit (Medium-1)**. Unit tests: JS escaping/CSP-safe insertion, RTL/CJK style, empty translations, loading cleanup, idempotent replacement, source-only fallback, stale-session-token commit discarded (no `errorUnit`). Deps: WI-0, WI-3, WI-4a, WI-4b, WI-6, (shared types from WI-7a). (If WI-0 = no-go, dropped; box D ships TXT/MD-only, tracked.)

**WI-AIP (behavioral — the folded-in Variant A AI Providers sheet): `ReaderAiProvidersSheet`.** The scoped in-reader "AI Providers" push sheet (nav bar `‹ Bilingual` + "AI Providers" title) reproducing `vreader-ai-provider-entry.jsx` `AIProvidersSheet`/`NavSheet`, hosting ONLY the #118 `AiProviderListScreen` (empty + populated) + the canonical `AiProviderEditSheet`, driven by the #118 `AiSettingsViewModel` (from WI-4b's `AppContainer` factory). Empty state carries the bilingual-context copy ("Bilingual mode needs a provider to translate" / "Add provider" CTA). On first Save → the provider becomes the bilingual engine (`store.setActive(savedId)`) + pop the whole stack back to the bilingual sheet (engine strip now "configured / Change…"). `‹ Bilingual` without adding → unconfigured, no state mutated. No consent/flag surface (Android has none). Deps: WI-4b (for `AiProviderStore` + `AiSettingsViewModel` in `AppContainer`), WI-7a (bilingual sheet host). Tests (Compose + connected): empty → Add → Save → pop-to-bilingual with strip configured; `‹ Bilingual` without adding → strip unconfigured, snapshot unchanged; "Change…" → populated list, current provider checked, tap row → `setActive`; editor reused verbatim (no divergent form).

**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into the `items(count = document.chunkCount)` loop as **additive translation items after the anchor chunk, source chunks byte-unchanged (H2)** + position-change (`charOffsetUTF16`) + setup-sheet. `originalFormat`-gated (TXT/MD). Uses WI-4b's DI. **#129 VERIFIED — straight edit.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2)**; **highlights/annotation-washes/read-aloud-wash still key off source chunks (H2)**; a translation item is non-selectable, does not perturb source offsets (H2); disable → source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders exactly one translation after its last chunk (H1/Low-2)**; **one-chunk/final-chunk anchors render (H1)**; MD source mapping. Deps: WI-6, WI-7a, WI-4b.

**WI-9 (behavioral): entry wiring + acceptance.** Mount `BilingualPill` in #132's VERIFIED top chrome; extend `readerMoreRows(...)` to supply the #134 VERIFIED More-menu `MoreActionId.BILINGUAL` toggle (`MoreRow.Toggle` `on`/`onToggle`, or `MoreRow.Disabled` "Configure AI provider first" when not configured) wired to the VM; **wire the setup sheet's "Set up"/"Change…" affordance → the #131-owned `ReaderAiProvidersSheet` (Variant A)**. Full acceptance across EPUB (if WI-7b landed) + TXT/MD, including the fresh-user path `unconfigured → Set up (→ Variant A AI Providers sheet) → add provider → return → enable → translate` (now #131-owned end-to-end). **Flip box D to done ONLY for provider/model/granularity + the Style-descope note; file the follow-up checklist amendment; do NOT claim full box-D parity.** The DONE flip **no longer waits on #136** (closed). Update `docs/architecture.md` (bilingual pipeline + the new `chapter_translations` schema + `AiProviderStore` + bilingual services in `AppContainer` + the Variant A AI Providers sheet). → DONE. Deps: WI-8, WI-AIP, WI-7b (if go), feat:#132, feat:#134.

## 5. Test catalogue

JVM/Robolectric (`android/app/src/test/...bilingual/`): `ChapterSegmenterTest` (paragraph blank-line; sentence CJK `。！？` vs Latin; empty→[]; single; **`paragraphRanges`/`sentenceRanges` return correct half-open UTF-16 `(start, endExclusive)` spans**); `TranslationChunkerTest` (packs to budget; oversize→own chunk+subSplit; empty→[]); `TranslationChunkContractTest` (prompt shape; strict JSON decode; code-fence strip; count mismatch→`CountMismatch`; non-array→`NotAStringArray`); `ChapterTranslationServiceTest` (cache hit 0 calls; miss→translate→write; decode-fail per-segment fallback; one-chunk-fail partial-not-cached; all-fail→throw; **native-cancel→Cancelled no write; typed-`Cancelled`→Cancelled no write (M2)**; ensureActive-before-write; offline/timeout/429/http/config/insecure→error mapping; very long chapter N-of-M; stale-cache count-mismatch re-translates; `translatePreSegmented` caches under enumerate count on full success; partial degrade not cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` hit/miss with no provider); `ChapterTranslationErrorMappingTest`; `TxtChapterTextProviderTest` (**one-chunk document → renders (H1); final-chunk anchor → renders (H1); exact-boundary → correct anchor (H1); EOF anchor → last chunk, no clamp-collapse (H1)**; paragraph spanning MANY chunks → one segment/unit anchored to last chunk (Low-2); multiple SENTENCES in one chunk → distinct segments (Low-2); >4000-char paragraph → one segment across hard-split chunks; CR/LF/CRLF; MD markers; locator→unit mapping; `unitAfter` end→null; source-byte parity while disabled); `ChapterTranslationPrefetcherTest` (snapshot-consistent profile+key; injected-factory used; `AiRequest` built from profile; **blank `profile.model` → `kind.defaultModel` (M3 regression)**; cache-hit-no-profile #306; no-profile miss→ProviderFailed; `prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls; CJK↔English + Latin round-trip via fake; cipher-throw→ProviderFailed not crash); `BilingualAiReadinessTest` (active+key→true; **no-active-with-profiles-present→false (H3); activeId-null→false (H3)**; empty key→false; cipher-throw→false, no crash); `PerBookBilingualStoreTest` (enabled/lang/granularity round-trip; no style field); `BilingualViewModelTest` (Turbine: first-enable sheet; re-enable no-sheet; disable clears; language reset; granularity reset + re-key; `aiConfigured` from readiness; prefetch current+next; same-unit no-op; **cancel-mid discards (no errorUnit); typed-Cancelled discards (M2); rapid re-trigger same unit single-flight, no double-write (M2)**; offline→unavailable; error→errorUnit+retry; `retryUnit`); `EpubBilingualJsTest` (JS escaping / CSP-safe insertion; RTL/CJK style; empty translations; clear idempotent; inject idempotent replacement; source-only fallback — WI-7b if go); `EpubBilingualControllerTest` (**enumerate→cachedDirect/prefetchDirect→guarded commit; stale-session-token commit discarded, no errorUnit; single-owner (regular TXT/MD prefetch never runs for EPUB unit) — Medium-1** — WI-7b if go).

Room migration: `VReaderDatabaseMigrationTest` (extend) **v8→v9 + full-chain from v8** + FK-CASCADE + `lookupKey`-as-PK; `ChapterTranslationDaoTest` (upsert-by-PK replaces; get/delete-by-lookupKey).

Compose UI (`androidTest/...bilingual/`): `BilingualSetupSheetUiTest` (language grid, granularity, preview, engine configured vs unconfigured driven by `aiConfigured`; no Style control present; light+dark); `BilingualInterlinearBodyUiTest` (**additive translation item after a paragraph anchor chunk (depicted); paragraph interlinear translated incl. CJK font + RTL Arabic; Sentence selection → paragraph-render fallback (H2 gate)**; loading N%+dimmed; error+Retry; offline source-only; empty translation→source-only no crash); `ReaderAiProvidersSheetUiTest` (**empty state with bilingual-context copy + Add CTA; populated list + current-provider checked; `‹ Bilingual` back label; editor reused (WI-AIP)**); `BilingualPillUiTest`.

Connected (`androidTest/...reader/`): `TxtReaderBilingualConnectedTest` (API 35, fake `AiClient` via injected factory): enable→setup→confirm→interlinear from seeded Room cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2); highlights/annotation-washes/read-aloud-wash still key off source chunks (H2); translation item non-selectable + no source-offset perturbation (H2)**; disable→source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders one translation (H1/Low-2); one-chunk/final-chunk anchors render (H1)**; TXT/MD gated (PDF inert); very long chapter scroll responsive; cancellation leaves no partial cache row. `ReaderAiProvidersConnectedTest` (WI-AIP + WI-9): `unconfigured → Set up → Variant A sheet → add provider → Save → pop-to-bilingual configured → enable → translate`; `‹ Bilingual` without adding → unconfigured, snapshot unchanged; "Change…" → populated, current checked. `EpubReaderBilingualConnectedTest` (only if WI-0=go): enable→inject on a real EPUB; disable→clear; href-change/fragment-recreation/activity-recreation→re-apply from cache (zero provider calls); count-divergence handled via `prefetchDirect`/`cachedDirect`; regular prefetch never runs for EPUB unit (Medium-1).

Edge cases: empty translation, failed, partial per-chunk, CJK↔English + Latin + RTL, provider error/timeout/429/config/insecure, native + typed cancellation mid-translation + before-write, single-flight overlap, very long chapters, offline (cache-first + silent source-only), cipher-decrypt failure → not-ready (no crash), enumerate↔segment count divergence (direct path), one-chunk/final-chunk/EOF anchors (H1), blank model (M3).

## 6. Risks + mitigations

- **Live-translation verification is AI-credential-gated (the box-D caveat).** The whole pipeline is verified without live creds via a deterministic **fake `AiClient`** injected through the prefetcher's `clientFactory` param (default `AiProviderFactory::create`; tests override). WI-3/4a/8 prove segment→chunk→decode→cache→interleave end-to-end incl. every error/edge path. Connected tests seed the Room cache and assert render-from-cache with zero client calls. An optional live smoke confirms wire format but is NOT a gate. The fresh-user `unconfigured → Set up → add provider` reachability leg is now #131-owned (WI-AIP + WI-9) and verified by `ReaderAiProvidersConnectedTest`.
- **Final-chunk translation drop (round-3 H1).** Fixed by `endExclusive = if (i+1<chunkCount) offsetForChunk(i+1) else text.length` + explicit half-open `(start, endExclusive)` computations everywhere; one-chunk/final-chunk/exact-boundary/EOF tests. `offsetForChunk`'s clamp (TxtDocument.kt:17) is never relied on for the final end.
- **Enabled render breaking the per-chunk layout/selection model (round-3 H2).** Fixed by the additive-item render contract: source chunk `Text` is NEVER split; translations are separate, non-selectable, unregistered `LazyColumn` items after the anchor chunk. Enabled-mode tests assert selection/highlight/wash/annotation parity with disabled. Sentence-granularity render is design-gated (only paragraph interlinear is depicted); Sentence selection falls back to paragraph render, granularity still cache-keyed.
- **TXT/MD segment↔render pairing (round-2 H1).** Both sides read the SAME segment `(start, endExclusive)` array over `TxtDocument.text`, so 1:1 holds by construction — no chapter model invented; a paragraph split across many chunks is translated + rendered once (anchored at its last chunk). Granularity is in the cache key.
- **EPUB direct-block flow (round-3 Medium-1).** The `EpubBilingualController` is the single owner: `enumeratedBlocks → cachedDirect (zero-provider restore) else prefetchDirect → session-token-guarded commit into BilingualRenderState/translationsByUnit`. The VM's position-driven regular prefetch is TXT/MD-only, so the two paths never write the same canonical cache row. Every suspended step is token-guarded; a stale token discards silently.
- **EPUB count divergence (round-2 H2).** The direct-block path (`prefetchDirect` → `translatePreSegmented`, cached by enumerate count, restored by `cachedDirect(expectedCount)` with zero provider calls) — iOS Bugs #268/#330/#343 parity.
- **EPUB JS-injection race (round-2 M1).** WI-0's contract (single actor/mutex OR monotonic navigator-session token; token check after every suspended call; clear before publication teardown; identified production re-apply signal per recreation case). No deterministic re-apply signal = explicit NO-GO → TXT/MD-only ship.
- **Cancellation + single-flight (round-3 Medium-2).** Both service and VM handle native `CancellationException` AND typed `ChapterTranslationError.Cancelled` before generic mapping (iOS `ChapterTranslationService.swift:359–364`); a per-unit `prefetchTasks: Map<TranslationUnitId, Job>` cancels/joins a prior request so rapid retry/navigation can't run overlapping translations or Room writes; a cancelled stale request never surfaces as `errorUnit`. `ensureActive()` before the Room write.
- **Blank model (round-3 Medium-3).** The prefetcher builds `model = profile.model.ifBlank { profile.kind.defaultModel }` (matches `AiChatViewModel.kt:61`; both wire clients serialize `request.model` directly, `OpenAiCompatibleProvider.kt:39`/`AnthropicProvider.kt:37`). Blank-model regression test.
- **AI-config readiness (H3).** `BilingualAiReadiness.resolve` = active profile + decrypts-non-empty; `activeId` can be null with profiles present; cipher failure → not-ready (no crash). No consent/flag gate (Android has none).
- **Cost/latency of translating on scroll.** Lazy current+next prefetch + disk cache; N-of-M progress; cancellation on navigate-away/generation-bump/single-flight supersede.
- **Provider JSON non-compliance.** `TranslationChunkContract.decode` + per-segment fallback — never drops a paragraph.
- **DataStore per-book key growth.** One Preferences entry per book keyed by fingerprint; scales like `ReaderSettingsStore`/`AiProviderStore`.
- **Dependency honesty (round-3 Medium-4).** WI-4b (DI, incl. `AiProviderStore` in `AppContainer`) is foundational and gates the production run-through of WI-6/WI-7b/WI-AIP/WI-8; those WIs' unit/Compose gates proceed against injected fakes, and WI-4b is sequenced before them. No external feature gates the chain (#136 closed).

## 7. Backward compat

- **Room migration additive.** New `chapter_translations` (FK CASCADE, `lookupKey` PK, `sourceParagraphCount`). Existing rows untouched. Against this checkout **8→9, `MIGRATION_8_9`** appended after `MIGRATION_7_8` (VReaderDatabase.kt:224–228); migration test extended from v8 guards it.
- **Reader unchanged when bilingual off** — the TXT/MD `items(count = document.chunkCount)` source loop is **byte-identical** unless `enabled && format∈{txt,md} && translation present` (translations are additive, non-selectable overlay items — H2). `ReaderBottomChrome` is not modified. EPUB render adapter inert unless bilingual is on.
- **`AppContainer` gains `AiProviderStore`** (previously not provided — VReaderApp.kt:66 comment only) plus the bilingual services + `AiSettingsViewModel` factory; all additive lazy singletons following the `readerSettingsStore` pattern. #118 AI files (`AiProviderStore`, `AiProviderListScreen`, `AiProviderEditSheet`, `AiSettingsViewModel`) are consumed unchanged.
- **#118 AI provider files unchanged** — the prefetcher/readiness/Variant A sheet are new consumers.
- **Backup contract already compatible** — `PerBookSettingsOverride.bilingualEnabled/TargetLanguage/Granularity` exist (no `bilingualStyle`), no translation-cache backup section (device-local, re-derivable). #131 writes the three fields locally; backup collect/restore is a small additive follow-up (no contract change), out of v1; config device-local until then.
- **#132/#134/#129 landed** — the top-chrome pill mount + More-menu toggle (`readerMoreRows` extension) + `TxtReaderActivity` edit land on VERIFIED surfaces (rule 48 one-writer-per-file satisfied).

## Design gates (rule 51 — for `needs-design` filing)

1. **"Bilingual mode" setup sheet with BOTH Style AND Granularity in one Android sheet** (unchanged — Style stays descoped v1) — `vreader-bilingual.jsx` depicts Granularity (no Style); `vreader-ai-android.jsx` depicts Style (no Granularity); no committed bundle shows both together. v1 reproduces the granularity-only `vreader-bilingual.jsx` sheet and DROPS Style (user descope, §3). If Style is wanted as an Android user control, file `Design needed: bilingual setup sheet (Style + Granularity) for feature #131`. The box-D Style parity gap is tracked by the WI-9 follow-up checklist amendment.
2. **`Design needed: sentence-granularity bilingual interlinear render for feature #131`** — `vreader-bilingual.jsx` `BilingualPageContent` (lines 200–277) depicts ONLY paragraph interlinear (one translation `<p>` per source paragraph); a translation-after-each-sentence render (grouped when several sentences share a line-chunk) is depicted nowhere. v1 ships the depicted **paragraph** interlinear render + the setup-sheet Granularity control (both options selectable, as depicted); selecting **Sentence** falls back to the depicted paragraph render (granularity still carried in the cache key so no wrong-shape row is served). When the sentence-interlinear render is designed, it is a render-only follow-up (the additive-item render contract already accommodates per-line sentence grouping).

*(REMOVED: the v3 "#136 dependency" design-gate line — #136 is closed and the Variant A AI Providers sheet IS the committed design, reproduced by WI-AIP, not a gate.)*

## Revision history

- v1 (2026-07-10): Gate-1 draft (Plan agent). Gate-2 Codex audit pending.
- v2 (2026-07-11): Gate-2 round-1 REDESIGN resolved — Readium-feasibility corrected, entry-point rebased on box F, setup-sheet design-gated, DI/cache/concurrency fixed.
- v3 (2026-07-12): Gate-2 round-2 findings resolved — TXT/MD document-global segment model (H1); EPUB translatePreSegmented + count-keyed cache + direct-block prefetch (H2); #136 AI-provider-reachability spun out as a hard dependency (GH #1976) + Style descoped v1 (H3); WI-0 go/no-go + navigator-race contract (M1); EPUB DOM-injection adapter not Compose body (M2); DI/factory WI reordered (M3); Room 8→9 MIGRATION_8_9 (M4); deps/WI-count corrected (L1/L2). Gate-2 round-3 = block-recommended.
- **v4 (2026-07-12): Gate-2 round-3 (block-recommended) findings resolved AND the AI-config path folded in.**
  - **AI-config FOLDED IN (#136 CLOSED, GH #1976 not-planned; user decision 2026-07-12):** the design proved the ONLY designed Android AI-config reader surface is the bilingual-coupled **Variant A** "AI Providers" sheet (`reader-ai-provider-entry.md`); it is not separable, so #131 now owns it end-to-end. Added **WI-AIP** (`ReaderAiProvidersSheet`, reusing #118 `AiProviderListScreen`/`AiProviderEditSheet`/`AiSettingsViewModel` verbatim, `‹ Bilingual` push, pop-back-on-first-Save); WI-4b now provides `AiProviderStore` into `AppContainer` (verified not provided today — VReaderApp.kt:66 comment only) plus the bilingual services + `AiSettingsViewModel` factory; removed `feat:#136` from Deps (now `[feat:#132, feat:#134]`, no external AI-reachability blocker); the DONE flip no longer waits on #136; `aiConfigured` derivation kept as the correct active-profile+decrypts-non-empty gate (H3), NOT `profiles.isEmpty()` (the iOS note's derivation), with no consent/flag gate (Android has none).
  - **H1 (round-3 High-1) final-chunk math:** `endExclusive = if (i+1<chunkCount) offsetForChunk(i+1) else text.length`; explicit half-open `(start, endExclusive)` computations (not `IntRange`); one-chunk/final-chunk/exact-boundary/EOF tests.
  - **H2 (round-3 High-2) additive-item render contract:** translations are additive `LazyColumn` items at chunk (line) boundaries; the source chunk `Text` is NEVER split; per-chunk one-`TextLayoutResult`/one-selection-registration preserved (TxtReaderActivity.kt:1043/1059/1062–1066); enabled-mode selection/highlight/wash/annotation/MD tests; sentence-granularity render flagged as a rule-51 design gate (only paragraph interlinear is depicted), paragraph ships.
  - **M1 (round-3 Medium-1) EPUB direct-block ownership/API:** `EpubBilingualController` single owner; `enumeratedBlocks → cachedDirect else prefetchDirect → session-token-guarded commit into BilingualRenderState/translationsByUnit`; regular prefetch is TXT/MD-only so the two paths never write the same canonical row.
  - **M2 (round-3 Medium-2) dual-cancellation + single-flight:** service AND VM handle native `CancellationException` AND typed `ChapterTranslationError.Cancelled` before generic mapping (iOS `ChapterTranslationService.swift:359–364`); per-unit `prefetchTasks: Map<TranslationUnitId, Job>` cancels/joins a prior; a cancelled stale request never surfaces as `errorUnit`.
  - **M3 (round-3 Medium-3) blank-model fallback:** `model = profile.model.ifBlank { profile.kind.defaultModel }` (matches `AiChatViewModel.kt:61`; clients serialize `request.model` directly); blank-model regression test.
  - **M4 (round-3 Medium-4) dependency honesty:** WI-4b (DI incl. `AiProviderStore`) is foundational and gates the production run-through of WI-6/WI-7b/WI-AIP/WI-8; those WIs' unit/Compose gates use injected fakes; WI-4b sequenced before them; no external feature gates the chain.
  - **Low fixes:** WI count corrected to **13** (added WI-AIP; the "11 WIs" claim was wrong — Low-1); chunk semantics corrected — a chunk is ONE LINE, holds multiple SENTENCES, a paragraph spans MANY chunks; removed the "a chunk can hold multiple paragraphs" claim (Low-2). Awaiting Gate-2 round-4 audit.
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
  1000	    // feature #124 WI-4 — a tap (LazyColumn-local point) → host hit-tests an existing highlight to edit.
  1001	    onTapAt: (androidx.compose.ui.geometry.Offset) -> Unit = {},
  1002	) {
  1003	    val isMarkdown = format == BookFormat.md
  1004	    val wash = VReaderColors.Accent.copy(alpha = 0.18f)
  1005	    val selectionAccent = Color(0x575C8FC4)   // design selection bg rgba(92,143,196,0.34)
  1006	    val selection by (selectionController?.selection ?: flowOf(null)).collectAsState(null)
  1007	    // the pointerInput block keys on selectionController (stable), so without this it would capture the
  1008	    // INITIAL onTapAt/onSelectionFinalized closures (stale highlightsList → tap-to-edit never hits).
  1009	    val currentOnTap by androidx.compose.runtime.rememberUpdatedState(onTapAt)
  1010	    val currentOnFinalize by androidx.compose.runtime.rememberUpdatedState(onSelectionFinalized)
  1011	    LazyColumn(
  1012	        Modifier
  1013	            .fillMaxSize()
  1014	            .onGloballyPositioned { selectionController?.setLazyCoords(it) }
  1015	            .then(
  1016	                if (selectionController != null) {
  1017	                    // ONE detector distinguishes a TAP (edit an existing highlight) from a LONG-PRESS+drag
  1018	                    // (new selection) — two separate pointerInput detectors conflict over the same down event.
  1019	                    Modifier.pointerInput(selectionController) {
  1020	                        awaitEachGesture {
  1021	                            val down = awaitFirstDown(requireUnconsumed = false)
  1022	                            val longPress = awaitLongPressOrCancellation(down.id)
  1023	                            if (longPress != null) {
  1024	                                // long-press → selection; finalize only on a COMPLETED drag/up (not a cancel).
  1025	                                selectionController.beginAt(longPress.position)
  1026	                                val completed = drag(longPress.id) { change -> selectionController.extendTo(change.position); change.consume() }
  1027	                                if (completed) currentOnFinalize() else selectionController.clear()
  1028	                            } else if (!down.isConsumed) {
  1029	                                // null also means cancel (e.g. a scroll won) — only a TAP leaves the down
  1030	                                // unconsumed; a scroll consumes it, so it won't be misread as tap-to-edit.
  1031	                                currentOnTap(down.position)
  1032	                            }
  1033	                        }
  1034	                    }
  1035	                } else {
  1036	                    Modifier
  1037	                },
  1038	            ),
  1039	        state = listState,
  1040	        contentPadding = PaddingValues(horizontal = marginDp.dp, vertical = 16.dp),
  1041	    ) {
  1042	        // Count-based: indices on demand (a newline-dense 14MB file can be 100k+ chunks).
  1043	        items(count = document.chunkCount, key = { it }) { i ->
  1044	            val raw = document.textForChunk(i).toString()
  1045	            // .md → styled markdown spans (no read-aloud span wash — markers shift offsets, plan §OOS).
  1046	            // .txt → raw verbatim, with the spoken-sentence span washed when read-aloud is active.
  1047	            val span = if (isMarkdown) null else highlightSpan(i)
  1048	            val text = when {
  1049	                isMarkdown -> mapper.renderedText(i)   // #125: the mapper is the single render owner
  1050	                span != null -> buildAnnotatedString {
  1051	                    append(raw)
  1052	                    val a = span.first.coerceIn(0, raw.length); val b = (span.last + 1).coerceIn(a, raw.length)
  1053	                    if (b > a) addStyle(SpanStyle(background = wash), a, b)
  1054	                }
  1055	                else -> AnnotatedString(raw)
  1056	            }
  1057	            // annotation washes drawn BEHIND the text (getPathForRange) — separate from the read-aloud span.
  1058	            val washes = washesForChunk(i)
  1059	            var layout by remember(i) { mutableStateOf<TextLayoutResult?>(null) }
  1060	            var coords by remember(i) { mutableStateOf<androidx.compose.ui.layout.LayoutCoordinates?>(null) }
  1061	            if (selectionController != null) {
  1062	                LaunchedEffect(i, layout, coords) {
  1063	                    val l = layout; val c = coords
  1064	                    if (l != null && c != null) selectionController.registerChunk(i, l, c)
  1065	                }
  1066	                DisposableEffect(selectionController, i) { onDispose { selectionController.unregisterChunk(i) } }
  1067	            }
  1068	            // read `selection` (a State) so a selection change recomposes + redraws the accent.
  1069	            val selRange = if (selection != null) selectionController?.selectionForChunk(i) else null
  1070	            Text(
  1071	                text = text,
  1072	                // merge over the material default (the pre-#129 explicit-param behavior) so platform
  1073	                // text defaults (letterSpacing etc.) are kept — only the Display settings change.
  1074	                style = androidx.compose.material3.LocalTextStyle.current.merge(textStyle),
  1075	                onTextLayout = { layout = it },
  1076	                modifier = Modifier
  1077	                    .onGloballyPositioned { coords = it }
  1078	                    .drawBehind {
  1079	                        layout?.let { l ->
  1080	                            drawWashes(l, washes)
  1081	                            selRange?.let { drawRangeFill(l, it, selectionAccent) }
  1082	                        }
  1083	                    },
  1084	            )
  1085	        }
  1086	    }
  1087	}

exec
/bin/zsh -lc "rg -n \"firstVisibleItemIndex|scrollToItem|animateScrollToItem|layoutInfo|visibleItemsInfo|chunkForOffset|offsetForChunk|LazyListState|listState\" android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt android/app/src/main/kotlin/com/vreader/app/reader | head -240 && nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt && nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt | sed -n '42,78p' && nl -ba android/app/src/main/kotlin/com/vreader/app/ai/OpenAiCompatibleProvider.kt | sed -n '25,52p' && nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AnthropicProvider.kt | sed -n '25,52p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:8:// ResumeResolver → Canonical → chunkForOffset.
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:27:// (chunkForOffset), returning Succeeded (sheet dismisses) or Failed (out-of-range → sheet stays open). The
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:45:import androidx.compose.foundation.lazy.LazyListState
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:46:import androidx.compose.foundation.lazy.rememberLazyListState
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:220:                        val listState = rememberLazyListState(initialFirstVisibleItemIndex = s.initialIndex)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:223:                            flushPosition = { savePosition(s.book, s.document, listState.firstVisibleItemIndex) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:226:                        LaunchedEffect(listState, s.document) {
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:227:                            snapshotFlow { listState.firstVisibleItemIndex }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:252:                        val spokenChunk = if (tts.phase == TtsPhase.speaking) s.document.chunkForOffset(tts.charStart) else -1
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:256:                            if (spokenChunk >= 0 && listState.layoutInfo.visibleItemsInfo.none { it.index == spokenChunk }) {
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:257:                                runCatching { listState.animateScrollToItem(spokenChunk) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:358:                        val liveOffset = s.document.offsetForChunk(listState.firstVisibleItemIndex)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:411:                                    ttsScope.launch { listState.scrollToItem(s.document.chunkForOffset(target)) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:421:                                    listState.scrollToItem(s.document.chunkForOffset(target))
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:454:                                                ttsScope.launch { runCatching { listState.scrollToItem(s.document.chunkForOffset(target)) } }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:473:                                        s.document.offsetForChunk(listState.firstVisibleItemIndex),
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:481:                                            listState.scrollToItem(s.document.chunkForOffset(target))
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:513:                                    s.document, listState, s.book.originalFormat, chunkMapper,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:519:                                            val cs = s.document.offsetForChunk(chunkIndex)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:520:                                            val ce = if (chunkIndex + 1 < s.document.chunkCount) s.document.offsetForChunk(chunkIndex + 1) else s.document.text.length
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:613:        container.cachedOffset(key)?.let { return document.chunkForOffset(it) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:619:        return document.chunkForOffset(offset)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:624:        val offset = document.offsetForChunk(topIndex)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:988:    document: TxtDocument, listState: LazyListState, format: BookFormat,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1039:        state = listState,
android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:17:    fun offsetForChunk(index: Int): Int {
android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:23:    fun chunkForOffset(offsetUtf16: Int): Int {
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderScreen.kt:42:import androidx.compose.foundation.lazy.LazyListState
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderScreen.kt:112:internal fun PdfReaderBody(document: PdfDocument, listState: LazyListState, backdrop: Color) {
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderScreen.kt:116:            state = listState,
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderScreen.kt:124:            page = listState.firstVisibleItemIndex + 1,
android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:58:        return Hit(hit.key, hit.value, rendered, doc.offsetForChunk(hit.key) + localSource)
android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:65:        val base = doc.offsetForChunk(hit.chunkIndex)
android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:132:        val endChunk = doc.chunkForOffset((r.endExclusive - 1).coerceAtLeast(0)).coerceIn(0, doc.chunkCount - 1)
android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:134:        val base = doc.offsetForChunk(endChunk)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:8:// ResumeResolver → Canonical → chunkForOffset.
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:27:// (chunkForOffset), returning Succeeded (sheet dismisses) or Failed (out-of-range → sheet stays open). The
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:45:import androidx.compose.foundation.lazy.LazyListState
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:46:import androidx.compose.foundation.lazy.rememberLazyListState
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:220:                        val listState = rememberLazyListState(initialFirstVisibleItemIndex = s.initialIndex)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:223:                            flushPosition = { savePosition(s.book, s.document, listState.firstVisibleItemIndex) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:226:                        LaunchedEffect(listState, s.document) {
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:227:                            snapshotFlow { listState.firstVisibleItemIndex }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:252:                        val spokenChunk = if (tts.phase == TtsPhase.speaking) s.document.chunkForOffset(tts.charStart) else -1
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:256:                            if (spokenChunk >= 0 && listState.layoutInfo.visibleItemsInfo.none { it.index == spokenChunk }) {
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:257:                                runCatching { listState.animateScrollToItem(spokenChunk) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:358:                        val liveOffset = s.document.offsetForChunk(listState.firstVisibleItemIndex)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:411:                                    ttsScope.launch { listState.scrollToItem(s.document.chunkForOffset(target)) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:421:                                    listState.scrollToItem(s.document.chunkForOffset(target))
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:454:                                                ttsScope.launch { runCatching { listState.scrollToItem(s.document.chunkForOffset(target)) } }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:473:                                        s.document.offsetForChunk(listState.firstVisibleItemIndex),
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:481:                                            listState.scrollToItem(s.document.chunkForOffset(target))
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:513:                                    s.document, listState, s.book.originalFormat, chunkMapper,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:519:                                            val cs = s.document.offsetForChunk(chunkIndex)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:520:                                            val ce = if (chunkIndex + 1 < s.document.chunkCount) s.document.offsetForChunk(chunkIndex + 1) else s.document.text.length
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:613:        container.cachedOffset(key)?.let { return document.chunkForOffset(it) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:619:        return document.chunkForOffset(offset)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:624:        val offset = document.offsetForChunk(topIndex)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:988:    document: TxtDocument, listState: LazyListState, format: BookFormat,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1039:        state = listState,
android/app/src/main/kotlin/com/vreader/app/reader/TxtSourceOffsets.kt:12:        doc.offsetForChunk(chunkIndex) + offsetInChunk
android/app/src/main/kotlin/com/vreader/app/reader/TxtSourceOffsets.kt:22:        var i = doc.chunkForOffset(range.startInclusive).coerceIn(0, doc.chunkCount - 1)
android/app/src/main/kotlin/com/vreader/app/reader/TxtSourceOffsets.kt:24:            val base = doc.offsetForChunk(i)
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:32:import androidx.compose.foundation.lazy.rememberLazyListState
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:135:                        val listState = rememberLazyListState(initialFirstVisibleItemIndex = s.initialPage)
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:142:                        SideEffect { flushPosition = { savePage(s.book, listState.firstVisibleItemIndex) } }
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:143:                        LaunchedEffect(listState) {
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:144:                            snapshotFlow { listState.firstVisibleItemIndex }
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:180:                        val livePage = listState.firstVisibleItemIndex
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:193:                            // the existing resume/save page-scroll seam (listState.firstVisibleItemIndex).
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:195:                                jumpScope.launch { listState.scrollToItem(pdfAnnotationPage(item, s.document.pageCount)) }
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:198:                            body = { PdfReaderBody(s.document, listState, backdrop) },
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:217:                                    jumpScope.launch { listState.scrollToItem(target) }
     1	// Purpose: feature #118 WI-1 (#110 Phase 3) — persists saved AI provider profiles + the active
     2	// selection. Profile metadata (name/kind/baseUrl/model/temperature/maxTokens) lives in DataStore
     3	// as a JSON list; the API key is kept ONLY as a SecretCipher token (the #116 KeystoreSecretCipher).
     4	// Reuses the #116 WebDavServerStore DataStore+SecretCipher credential pattern, adding an active-id
     5	// and a request-start `snapshot()` (a chat/test reads one consistent profile, not live mid-request
     6	// store reads). The key + auth headers are NEVER logged.
     7	package com.vreader.app.ai
     8	
     9	import androidx.datastore.core.DataStore
    10	import androidx.datastore.preferences.core.Preferences
    11	import androidx.datastore.preferences.core.edit
    12	import androidx.datastore.preferences.core.stringPreferencesKey
    13	import com.vreader.app.backup.net.SecretCipher
    14	import kotlinx.coroutines.flow.Flow
    15	import kotlinx.coroutines.flow.first
    16	import kotlinx.coroutines.flow.map
    17	import kotlinx.serialization.Serializable
    18	import kotlinx.serialization.json.Json
    19	
    20	/** A saved AI provider. `encryptedApiKey` is a [SecretCipher] token, never plaintext. */
    21	@Serializable
    22	data class AiProviderProfile(
    23	    val id: String,
    24	    val name: String,
    25	    val kind: AiProviderKind,
    26	    val baseUrl: String,
    27	    val model: String,
    28	    val temperature: Double = 0.7,
    29	    val maxTokens: Int = 2048,
    30	    val encryptedApiKey: String,
    31	)
    32	
    33	/** A consistent point-in-time view: the profiles + which is active. */
    34	data class AiProviderSnapshot(val profiles: List<AiProviderProfile>, val activeId: String?) {
    35	    val active: AiProviderProfile? get() = profiles.firstOrNull { it.id == activeId }
    36	}
    37	
    38	@Serializable
    39	private data class AiStoreState(val profiles: List<AiProviderProfile> = emptyList(), val activeId: String? = null)
    40	
    41	class AiProviderStore(
    42	    private val dataStore: DataStore<Preferences>,
    43	    private val cipher: SecretCipher,
    44	    private val json: Json = Json { ignoreUnknownKeys = true; encodeDefaults = true },
    45	) {
    46	    /** One consistent profiles + active-id view (read once at request start). */
    47	    suspend fun snapshot(): AiProviderSnapshot = read(dataStore.data.first()).toSnapshot()
    48	
    49	    fun observe(): Flow<AiProviderSnapshot> = dataStore.data.map { read(it).toSnapshot() }
    50	
    51	    suspend fun list(): List<AiProviderProfile> = snapshot().profiles
    52	
    53	    suspend fun activeProfile(): AiProviderProfile? = snapshot().active
    54	
    55	    /**
    56	     * Insert/update a profile by [id]. [apiKey] is the PLAINTEXT to encrypt; pass null on an edit
    57	     * that leaves the key unchanged (the existing ciphertext is kept). A brand-new id REQUIRES a
    58	     * key. The first profile added becomes active. Returns the saved profile (key encrypted).
    59	     */
    60	    suspend fun upsert(
    61	        id: String,
    62	        name: String,
    63	        kind: AiProviderKind,
    64	        baseUrl: String,
    65	        model: String,
    66	        temperature: Double,
    67	        maxTokens: Int,
    68	        apiKey: String?,
    69	    ): AiProviderProfile {
    70	        lateinit var saved: AiProviderProfile
    71	        dataStore.edit { prefs ->
    72	            val cur = read(prefs)
    73	            val existing = cur.profiles.firstOrNull { it.id == id }
    74	            val encrypted = when {
    75	                apiKey != null -> cipher.encrypt(apiKey)
    76	                existing != null -> existing.encryptedApiKey  // unchanged on edit
    77	                else -> throw IllegalArgumentException("a new provider ($id) requires an API key")
    78	            }
    79	            saved = AiProviderProfile(id, name, kind, baseUrl, model, temperature, maxTokens, encrypted)
    80	            val next = cur.profiles.filterNot { it.id == id } + saved
    81	            val activeId = cur.activeId ?: id  // first provider becomes active
    82	            prefs[KEY] = json.encodeToString(AiStoreState(next, activeId))
    83	        }
    84	        return saved
    85	    }
    86	
    87	    /** Remove a profile. If it was active, the active selection moves to the first remaining (or null). */
    88	    suspend fun delete(id: String) {
    89	        dataStore.edit { prefs ->
    90	            val cur = read(prefs)
    91	            val next = cur.profiles.filterNot { it.id == id }
    92	            val activeId = if (cur.activeId == id) next.firstOrNull()?.id else cur.activeId
    93	            prefs[KEY] = json.encodeToString(AiStoreState(next, activeId))
    94	        }
    95	    }
    96	
    97	    /** Select the active provider (no-op if the id isn't present). */
    98	    suspend fun setActive(id: String) {
    99	        dataStore.edit { prefs ->
   100	            val cur = read(prefs)
   101	            if (cur.profiles.any { it.id == id }) prefs[KEY] = json.encodeToString(cur.copy(activeId = id))
   102	        }
   103	    }
   104	
   105	    /** Decrypt the key from a CAPTURED [profile] — snapshot-consistent (no live store read). The
   106	     *  chat/test request path uses THIS with a profile from a single [snapshot], so it can't pair
   107	     *  snapshot metadata with a concurrently-edited/deleted key. */
   108	    fun apiKey(profile: AiProviderProfile): String = cipher.decrypt(profile.encryptedApiKey)
   109	
   110	    /** The decrypted API key for [id] via a live read, or null if absent. Convenience for UI flows
   111	     *  that aren't mid-request; the request path should prefer [apiKey] (profile). */
   112	    suspend fun apiKey(id: String): String? =
   113	        list().firstOrNull { it.id == id }?.let { cipher.decrypt(it.encryptedApiKey) }
   114	
   115	    private fun read(prefs: Preferences): AiStoreState {
   116	        val raw = prefs[KEY] ?: return AiStoreState()
   117	        return runCatching { json.decodeFromString<AiStoreState>(raw) }.getOrDefault(AiStoreState())
   118	    }
   119	
   120	    private fun AiStoreState.toSnapshot() = AiProviderSnapshot(profiles, activeId)
   121	
   122	    companion object {
   123	        private val KEY = stringPreferencesKey("ai_providers_json")
   124	    }
   125	}
    42	    fun refreshProvider() = viewModelScope.launch {
    43	        val active = withContext(clientDispatcher) { store.activeProfile() }
    44	        if (active?.id != activeProviderId) {
    45	            activeProviderId = active?.id
    46	            chatGen++            // invalidate any in-flight answer started under the previous provider
    47	            streamJob?.cancel()
    48	            _state.update { it.copy(streaming = false, streamingText = "") }
    49	        }
    50	        _state.update { it.copy(unconfigured = active == null, providerName = active?.name) }
    51	    }
    52	
    53	    fun send(prompt: String) {
    54	        val s = _state.value
    55	        if (s.unconfigured || prompt.isBlank() || s.streaming) return
    56	        val gen = ++chatGen
    57	        _state.update { it.copy(mode = AiChatMode.chat, messages = it.messages + ChatMessage(true, prompt), streaming = true, streamingText = "", error = null) }
    58	        streamJob = viewModelScope.launch {
    59	            val (profile, key) = activeClient() ?: run { _state.update { it.copy(streaming = false, unconfigured = true) }; return@launch }
    60	            val history = _state.value.messages.map { AiMessage(if (it.fromUser) AiRole.user else AiRole.assistant, it.text) }
    61	            val request = AiRequest(profile.model.ifBlank { profile.kind.defaultModel }, history, profile.temperature, profile.maxTokens, system = CHAT_SYSTEM)
    62	            val sb = StringBuilder()
    63	            try {
    64	                factory(profile, key).streamChat(request).collect { chunk ->
    65	                    if (gen != chatGen) return@collect  // superseded by a provider swap / newer send
    66	                    sb.append(chunk.deltaText)
    67	                    _state.update { it.copy(streamingText = sb.toString()) }
    68	                }
    69	                if (gen == chatGen) _state.update { it.copy(messages = it.messages + ChatMessage(false, sb.toString()), streaming = false, streamingText = "") }
    70	            } catch (e: AiError) {
    71	                if (gen == chatGen) _state.update { it.copy(streaming = false, streamingText = "", error = e.message) }
    72	            }
    73	        }
    74	    }
    75	
    76	    /** Stop a streaming answer; keep whatever streamed so far as the assistant message. */
    77	    fun stop() {
    78	        streamJob?.cancel()
    25	    apiKey: String,
    26	    model: String,
    27	    temperature: Double,
    28	    maxTokens: Int,
    29	    dispatcher: CoroutineDispatcher = Dispatchers.IO,
    30	) : BaseHttpAiClient(baseUrl, apiKey, model, temperature, maxTokens, dispatcher) {
    31	
    32	    override val endpointPath = "/chat/completions"
    33	
    34	    override fun applyAuth(conn: HttpURLConnection) {
    35	        conn.setRequestProperty("Authorization", "Bearer $apiKey")  // never logged
    36	    }
    37	
    38	    override fun requestBody(request: AiRequest, stream: Boolean): String = buildJsonObject {
    39	        put("model", request.model)
    40	        put("temperature", request.temperature)
    41	        put("max_tokens", request.maxTokens)
    42	        put("stream", stream)
    43	        putJsonArray("messages") {
    44	            request.system?.let { addJsonObject { put("role", "system"); put("content", it) } }
    45	            request.messages.forEach { m ->
    46	                addJsonObject { put("role", m.role.name); put("content", m.content) }
    47	            }
    48	        }
    49	    }.toString()
    50	
    51	    override fun parseDelta(event: SseEvent): DeltaParse {
    52	        val data = event.data
    25	    maxTokens: Int,
    26	    dispatcher: CoroutineDispatcher = Dispatchers.IO,
    27	) : BaseHttpAiClient(baseUrl, apiKey, model, temperature, maxTokens, dispatcher) {
    28	
    29	    override val endpointPath = "/v1/messages"
    30	
    31	    override fun applyAuth(conn: HttpURLConnection) {
    32	        conn.setRequestProperty("x-api-key", apiKey)  // never logged
    33	        conn.setRequestProperty("anthropic-version", ANTHROPIC_VERSION)
    34	    }
    35	
    36	    override fun requestBody(request: AiRequest, stream: Boolean): String = buildJsonObject {
    37	        put("model", request.model)
    38	        put("max_tokens", request.maxTokens)
    39	        put("temperature", request.temperature)
    40	        put("stream", stream)
    41	        request.system?.let { put("system", it) }  // top-level, not a message
    42	        putJsonArray("messages") {
    43	            request.messages.forEach { m ->
    44	                // Anthropic accepts user/assistant only; a stray system message folds to user.
    45	                val role = if (m.role == AiRole.assistant) "assistant" else "user"
    46	                addJsonObject { put("role", role); put("content", m.content) }
    47	            }
    48	        }
    49	    }.toString()
    50	
    51	    override fun parseDelta(event: SseEvent): DeltaParse {
    52	        // Prefer the event-type line; fall back to the data's own `type` (some servers omit event:).

exec
/bin/zsh -lc "nl -ba dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx | sed -n '70,110p;190,285p' && nl -ba dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md | sed -n '35,190p' && nl -ba dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx | sed -n '1,280p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
    70	                  }}>{l.k}</span>
    71	                </button>
    72	              );
    73	            })}
    74	          </div>
    75	        </div>
    76	
    77	        {/* granularity */}
    78	        <div style={{ marginTop: 22 }}>
    79	          <SectionLabel theme={t}>Granularity</SectionLabel>
    80	          <div style={{
    81	            display: 'flex', marginTop: 10, borderRadius: 12,
    82	            background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
    83	            padding: 3,
    84	          }}>
    85	            {[
    86	              { k: 'paragraph', label: 'Paragraph', sub: 'Translate after each ¶' },
    87	              { k: 'sentence',  label: 'Sentence',  sub: 'Translate after each sentence' },
    88	            ].map(o => (
    89	              <button key={o.k} onClick={() => update('granularity', o.k)} style={{
    90	                flex: 1, padding: '10px 10px', borderRadius: 10, border: 'none',
    91	                background: v.granularity === o.k ? (t.isDark ? '#3a3530' : '#fff') : 'transparent',
    92	                color: t.ink, fontFamily: 'inherit', cursor: 'pointer',
    93	                boxShadow: v.granularity === o.k ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
    94	                textAlign: 'center',
    95	              }}>
    96	                <div style={{ fontSize: 13, fontWeight: 600 }}>{o.label}</div>
    97	                <div style={{ fontSize: 10.5, color: t.sub, marginTop: 1 }}>{o.sub}</div>
    98	              </button>
    99	            ))}
   100	          </div>
   101	        </div>
   102	
   103	        {/* AI provider strip */}
   104	        <div style={{ marginTop: 22 }}>
   105	          <SectionLabel theme={t}>Translation engine</SectionLabel>
   106	          <div style={{
   107	            marginTop: 8, padding: '12px 14px', borderRadius: 12,
   108	            background: aiConfigured
   109	              ? (t.isDark ? 'rgba(255,255,255,0.04)' : '#fff')
   110	              : `${t.accent}10`,
   190	      }}>{sample}</div>
   191	    </div>
   192	  );
   193	}
   194	
   195	// ────────────────────────────────────────────────────
   196	// Paragraph-interlinear renderer
   197	// Used by the reader when bilingual mode is on. Renders source + translation
   198	// stacked, one source paragraph followed by its translation.
   199	// ────────────────────────────────────────────────────
   200	function BilingualPageContent({ page, theme, fontFamily, fontSize, lineHeight, margin,
   201	                                pageDir, animating, pageIdx, lang = 'Chinese' }) {
   202	  const t = theme;
   203	  const ff = fontFamily === 'serif'
   204	    ? '"Source Serif 4", Georgia, "Times New Roman", serif'
   205	    : '"Inter", -apple-system, system-ui, sans-serif';
   206	  const translatedFF = (lang === 'Chinese' || lang === 'Japanese' || lang === 'Korean')
   207	    ? '"Songti SC", "Source Han Serif", serif'
   208	    : ff;
   209	  const isRTL = lang === 'Arabic';
   210	
   211	  const animTransform = animating
   212	    ? `translateX(${pageDir > 0 ? -8 : 8}%) ` : 'translateX(0) ';
   213	  const animOpacity = animating ? 0 : 1;
   214	
   215	  // Mock translations for the sample P&P paragraphs (matches vreader-data.jsx PP_PAGES)
   216	  const TRANSLATIONS = {
   217	    Chinese: {
   218	      'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.':
   219	        '凡是有钱的单身汉，总想娶位太太，这已经成了一条举世公认的真理。',
   220	      'However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families, that he is considered as the rightful property of some one or other of their daughters.':
   221	        '这样的单身汉，每逢新搬到一个地方，四邻八舍虽然完全不了解他的性情如何，见解如何，可是，既然这样的一条真理早已在人们心目中根深蒂固，因此人们总是把他看作自己某一个女儿理所应得的一笔财产。',
   222	    },
   223	  };
   224	  const fallback = (en) => '【' + (lang === 'Chinese' ? '译文' : lang) + '】 ' + en.slice(0, 60) + '…';
   225	
   226	  return (
   227	    <div style={{
   228	      position: 'absolute', top: 76, bottom: 56, left: margin, right: margin,
   229	      overflow: 'hidden', transform: animTransform, opacity: animOpacity,
   230	      transition: 'transform 0.28s cubic-bezier(0.32, 0.72, 0, 1), opacity 0.22s ease-out',
   231	      direction: isRTL ? 'ltr' : 'ltr', // source is always LTR
   232	    }}>
   233	      {(pageIdx === 0 || page.chapter !== PP_PAGES[(pageIdx - 1 + PP_PAGES.length) % PP_PAGES.length].chapter) && (
   234	        <div style={{
   235	          fontFamily: '"Source Serif 4", Georgia, serif',
   236	          fontSize: 13, color: t.sub, letterSpacing: 2,
   237	          textTransform: 'uppercase', textAlign: 'center',
   238	          marginBottom: 18, marginTop: 8, fontWeight: 500,
   239	        }}>{page.chapter}</div>
   240	      )}
   241	      {page.paragraphs.map((para, i) => {
   242	        const tr = (TRANSLATIONS[lang] && TRANSLATIONS[lang][para]) || fallback(para);
   243	        return (
   244	          <div key={i} style={{ marginBottom: lineHeight * fontSize * 0.55 }}>
   245	            <p style={{
   246	              fontFamily: ff, fontSize, lineHeight, color: t.ink, margin: 0,
   247	              textIndent: i === 0 ? 0 : `${fontSize * 1.4}px`,
   248	              textAlign: 'justify', hyphens: 'auto',
   249	            }}>
   250	              {i === 0 && (
   251	                <span style={{
   252	                  fontFamily: '"Source Serif 4", Georgia, serif',
   253	                  fontSize: fontSize * 2.6, lineHeight: 0.85,
   254	                  float: 'left', marginRight: 6, marginTop: 4,
   255	                  color: t.accent, fontWeight: 600,
   256	                }}>{para[0]}</span>
   257	              )}
   258	              {i === 0 ? para.slice(1) : para}
   259	            </p>
   260	            <p style={{
   261	              fontFamily: translatedFF,
   262	              fontSize: fontSize * 0.88, lineHeight: 1.55,
   263	              color: t.sub, margin: '6px 0 0',
   264	              paddingLeft: fontSize * 1.0, paddingRight: isRTL ? 0 : 0,
   265	              direction: isRTL ? 'rtl' : 'ltr',
   266	              textAlign: isRTL ? 'right' : 'left',
   267	              borderLeft: isRTL ? 'none' : `2px solid ${t.accent}55`,
   268	              borderRight: isRTL ? `2px solid ${t.accent}55` : 'none',
   269	              paddingLeft: isRTL ? 0 : fontSize * 0.7,
   270	              paddingRight: isRTL ? fontSize * 0.7 : 0,
   271	            }}>{tr}</p>
   272	          </div>
   273	        );
   274	      })}
   275	    </div>
   276	  );
   277	}
   278	
   279	// ────────────────────────────────────────────────────
   280	// The "EN ↔ 中" pill shown in the reader top chrome when bilingual is on
   281	// ────────────────────────────────────────────────────
   282	function BilingualPill({ theme, lang }) {
   283	  const t = theme;
   284	  const glyph = (BILINGUAL_LANGS.find(l => l.k === lang) || BILINGUAL_LANGS[0]).glyph;
   285	  return (
    35	---
    36	
    37	## Three approaches
    38	
    39	### A — Scoped AI Providers sheet, pushed in the bilingual flow  ·  CANONICAL
    40	
    41	"Set up" pushes a **navigation level inside the same bottom sheet** — same frame,
    42	same height, slide-left push. Nav bar: `‹ Bilingual` leading, **AI Providers**
    43	title. The body is *only* the `AISettingsSection` provider list — nothing else
    44	from `SettingsView`.
    45	
    46	- **Zero providers** → the list shows an empty state (sparkle tile, one line of
    47	  copy naming *why* the user is here — "Bilingual mode needs a provider to
    48	  translate") and a single **Add provider** CTA.
    49	- **Add provider** presents the canonical `AIProviderEditSheet`
    50	  (`vreader-ai-provider-fields.jsx`) as its own modal sheet — full height,
    51	  unchanged from the Library path. Kind / Name / Endpoint / Sampling / API Key /
    52	  Test Connection all intact.
    53	- **On the first Save**, the new provider becomes the bilingual engine default
    54	  and the stack **pops all the way back to Bilingual**. The engine strip now reads
    55	  *"Claude · configured" / "Change…"*, ready for **Turn on bilingual mode**. That
    56	  return is the payoff — the user lands exactly where they started, with the one
    57	  thing they were missing now filled in.
    58	- Tapping `‹ Bilingual` *without* adding returns to Bilingual still unconfigured —
    59	  no state mutated, no penalty for backing out.
    60	
    61	**Why A wins**
    62	
    63	- **Reuses the canonical editor.** No second, diverging "add a provider" form to
    64	  maintain. Test Connection, keychain storage, endpoint hints — all the work
    65	  already shipped in `AIProviderEditSheet` comes for free.
    66	- **Keeps the reader context.** A scoped sheet, not the whole app-settings tree.
    67	  The user never sees Cloud & Sync, OPDS catalogs, Book sources, TTS, replacement
    68	  rules — none of which they came for.
    69	- **Closes the loop.** The user's actual goal is "turn on bilingual"; A returns
    70	  them to that goal with the blocker removed. B and C both leak that thread.
    71	- **One surface for both entry points.** "Change…" (when already configured) lands
    72	  on the *same* list, current provider checked — so add-first and change-later
    73	  share a destination.
    74	
    75	The extra navigation level (list → editor) looks like a cost when there are zero
    76	providers, but it isn't: the empty state is a one-tap shortcut into the editor.
    77	When the user *does* already have providers (added from Library, or for the AI
    78	chat assistant), the list is the correct landing — "Set up" should let them pick,
    79	not silently create a duplicate.
    80	
    81	### B — Deep-link into the full `SettingsView`, scrolled to the AI section
    82	
    83	Present the entire app `SettingsView` modally over the reader, auto-scrolled and
    84	briefly highlighting the AI section.
    85	
    86	- **Pro:** one surface, verbatim reuse of the Library path, no new navigation
    87	  container.
    88	- **Why not canonical:** it dumps a reader-context user into the *whole* app
    89	  configuration — Cloud, OPDS, sources, TTS, Chinese conversion, About — to do one
    90	  narrow thing. And the return is ambiguous: closing `SettingsView` drops the user
    91	  back to the reader with the bilingual sheet already gone, so the "I was turning
    92	  on bilingual" thread is lost. They have to re-open More → toggle bilingual again.
    93	
    94	### C — Inline expansion inside the bilingual sheet
    95	
    96	"Set up" expands the engine strip *in place* into a minimal provider-+-key form;
    97	no navigation at all.
    98	
    99	- **Pro:** the tightest possible loop — the user never leaves the bilingual sheet.
   100	- **Why not canonical:** the real provider model is not "provider + key". It's
   101	  kind, name, base URL (with append-path hints), model, sampling, keychain-stored
   102	  key, and a live connection test. A bilingual half-sheet can't host that without
   103	  either cramping it or shipping a stripped-down form that **diverges from
   104	  `AIProviderEditSheet`** — at which point a key saved here wouldn't be testable,
   105	  and two "add provider" surfaces would drift. Held in reserve for a future
   106	  "express setup" only if we ever ship a genuinely one-field provider kind.
   107	
   108	---
   109	
   110	## Navigation model (precise)
   111	
   112	```
   113	   More ▸ Bilingual mode (first toggle on)
   114	        └─ BilingualSetupSheet        [bottom sheet · height 620]
   115	             engine strip: "No AI provider configured"  [ Set up ]
   116	                                   │  onOpenSettings
   117	                                   ▼   (push, slide-left, same sheet frame)
   118	           AIProvidersSheet           [nav bar: ‹ Bilingual · "AI Providers"]
   119	             ├─ empty  → [ Add provider ] ─┐
   120	             └─ list   → tap a row sets it │  (present modal, full height)
   121	                                   ▼        ▼
   122	                          AIProviderEditSheet   [vreader-ai-provider-fields.jsx]
   123	                                   │  Save
   124	                                   ▼   (provider becomes bilingual engine,
   125	                                        pop the whole stack)
   126	           BilingualSetupSheet  ← engine strip now "Claude · configured" / Change…
   127	```
   128	
   129	- The AI Providers view is a **push within the bilingual sheet**, NOT a modal over
   130	  the reader and NOT the full `SettingsView`.
   131	- The editor is a **modal on top** (tall form deserves full height).
   132	- "Change…" on an already-configured strip opens the **same** `AIProvidersSheet`,
   133	  populated, current provider checked.
   134	
   135	---
   136	
   137	## States — covered exhaustively in the canvas
   138	
   139	**Trigger**
   140	- The bilingual sheet, engine unconfigured, "Set up" highlighted (start point) —
   141	  paper + dark.
   142	
   143	**A · canonical**
   144	- AI Providers — empty (no providers) + bilingual-context note + Add CTA.
   145	- Add Provider — the canonical `AIProviderEditSheet`, pushed.
   146	- AI Providers — populated, new provider "In use" checked, Done.
   147	- Return to Bilingual — engine configured, "Change…", ready to turn on (payoff).
   148	- Empty + populated in dark.
   149	- Reached via "Change…" — multiple providers, switching the selected one.
   150	
   151	**B · alternative** — full `SettingsView` deep-link, AI section highlighted —
   152	paper + dark.
   153	
   154	**C · alternative** — inline expansion in the bilingual strip — paper + dark.
   155	
   156	**D · anatomy** — the nav-stack diagram + engine-strip before/after, true size.
   157	
   158	---
   159	
   160	## Production wiring
   161	
   162	- New reader-scoped presentation: a lightweight nav container hosting **only**
   163	  `AISettingsSection`'s provider list — call it `ReaderAIProvidersView`. It is NOT
   164	  `SettingsView`; it reuses the same `AIProviderListView` + `AIProviderEditSheet`
   165	  cells.
   166	- `BilingualSetupSheet.onOpenSettings` → presents `ReaderAIProvidersView` as a
   167	  push inside the bilingual sheet's own `NavigationStack` (so `‹ Bilingual` is a
   168	  real back, not a dismiss).
   169	- On `AIProviderEditSheet` Save when launched from this flow: set the saved
   170	  provider as the bilingual mode engine (`BilingualConfig.engineProviderID`) and
   171	  dismiss back to the bilingual sheet (pop to root).
   172	- `aiConfigured` on the engine strip is derived from
   173	  `AISettingsViewModel.providers.isEmpty == false`; the strip's CTA label is
   174	  `Set up` when empty, `Change…` otherwise (already shipped by #301).
   175	- The Library `SettingsView → AI provider` row is unchanged; it still opens the
   176	  full list. This adds a *second*, scoped entry — it does not move the first.
   177	
   178	## Cross-references
   179	
   180	| File | Role |
   181	|---|---|
   182	| `VReader AI Provider Entry Canvas.html` | Canvas of every state across themes. Source of truth. |
   183	| `vreader-ai-provider-entry.jsx` | `AIProvidersSheet`, `BilingualEngineStrip`, `EngineStripInline`, `NavFlowDiagram` — #1380 |
   184	| `vreader-ai-provider-fields.jsx` | `EditorSheet` (`AIProviderEditSheet`) — reused unchanged for the add/edit step (#1363) |
   185	| `vreader-bilingual.jsx` | `BilingualSetupSheet` — the surface whose "Set up" button this wires (#790) |
   186	| `design-notes/feature-60-followups.md` | Parent bilingual feature notes (#60 / #56) |
     1	// In-reader AI Providers entry — issue #1380.
     2	//
     3	// Wires the bilingual setup sheet's "Set up" button (shown when no AI provider
     4	// is configured, per Bug #301) to an actual AI Providers surface — which does
     5	// not exist in-reader today (the reader's showSettings sheet is display/fonts
     6	// only; the full SettingsView with AISettingsSection is Library-only).
     7	//
     8	// CANONICAL (A): a scoped "AI Providers" sheet PUSHED inside the bilingual
     9	//   flow (nav bar: ‹ Bilingual · "AI Providers"), hosting only the provider
    10	//   list. Empty → "Add provider" → the canonical AIProviderEditSheet
    11	//   (vreader-ai-provider-fields.jsx, reused unchanged). On first Save the
    12	//   provider becomes the bilingual engine and the stack pops back to Bilingual,
    13	//   whose engine strip now reads "configured / Change…".
    14	//
    15	// ALTERNATIVES shown for comparison:
    16	//   B — deep-link into the full SettingsView, scrolled to the AI section.
    17	//   C — inline expansion of the engine strip inside the bilingual sheet.
    18	//
    19	// Reuses: Sheet vocabulary, SectionLabel, Icons, THEMES tokens. The provider
    20	// tile keeps the fixed #8c2f2f brand color used by the shipped AI Provider row.
    21	
    22	const AIPE_BRAND = '#8c2f2f';           // AI provider tile (theme-independent)
    23	const AIPE_MONO  = 'ui-monospace, "SF Mono", "Menlo", monospace';
    24	const AIPE_SERIF = '"Source Serif 4", Georgia, serif';
    25	
    26	// ────────────────────────────────────────────────────
    27	// NavSheet — bottom sheet with an iOS-style navigation bar (back + centered
    28	// title + trailing). This is the "push within the sheet" presentation: same
    29	// grabber + frame as Sheet, but a real back affordance instead of a grabber-
    30	// only modal. Title is absolutely centered so a wide back label can't shove it.
    31	// ────────────────────────────────────────────────────
    32	function NavSheet({ theme, height = 620, title, backLabel = 'Bilingual', onBack, trailing, children }) {
    33	  const t = theme || THEMES.paper;
    34	  return (
    35	    <div style={{
    36	      position: 'absolute', inset: 0, zIndex: 200,
    37	      display: 'flex', flexDirection: 'column', justifyContent: 'flex-end',
    38	      background: 'rgba(0,0,0,0.35)',
    39	    }}>
    40	      <div style={{
    41	        background: t.isDark ? '#222020' : '#fcf8f0',
    42	        height, borderTopLeftRadius: 22, borderTopRightRadius: 22,
    43	        boxShadow: '0 -8px 28px rgba(0,0,0,0.25)',
    44	        display: 'flex', flexDirection: 'column', overflow: 'hidden',
    45	      }}>
    46	        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
    47	          <div style={{
    48	            width: 36, height: 5, borderRadius: 3,
    49	            background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)',
    50	          }}/>
    51	        </div>
    52	        <div style={{
    53	          position: 'relative', display: 'flex', alignItems: 'center',
    54	          padding: '13px 16px 12px',
    55	          borderBottom: `0.5px solid ${t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'}`,
    56	        }}>
    57	          <button onClick={onBack} style={{
    58	            display: 'flex', alignItems: 'center', gap: 1, zIndex: 1,
    59	            background: 'none', border: 'none', padding: 0, cursor: 'pointer',
    60	            color: t.accent, fontFamily: 'inherit', fontSize: 15, fontWeight: 500,
    61	            whiteSpace: 'nowrap',
    62	          }}>
    63	            <Icons.ChevronL size={19} color={t.accent} stroke={2.2}/>
    64	            <span>{backLabel}</span>
    65	          </button>
    66	          <div style={{
    67	            position: 'absolute', left: 0, right: 0, textAlign: 'center',
    68	            fontFamily: AIPE_SERIF, fontSize: 17, fontWeight: 600, color: t.ink,
    69	            pointerEvents: 'none',
    70	          }}>{title}</div>
    71	          <div style={{ marginLeft: 'auto', zIndex: 1 }}>{trailing}</div>
    72	        </div>
    73	        <div style={{ flex: 1, overflow: 'auto' }} className="hide-scroll">{children}</div>
    74	      </div>
    75	    </div>
    76	  );
    77	}
    78	
    79	// ────────────────────────────────────────────────────
    80	// Bilingual engine strip — standalone replica of the strip inside
    81	// BilingualSetupSheet, so the canvas can show the before ("Set up") and after
    82	// ("Change…") states and the flow's payoff. justChanged adds a brief accent
    83	// ring on the freshly-configured return.
    84	// ────────────────────────────────────────────────────
    85	function BilingualEngineStrip({ theme, configured, providerName = 'Claude', onSetup, justChanged = false }) {
    86	  const t = theme;
    87	  return (
    88	    <div>
    89	      <SectionLabel theme={t}>Translation engine</SectionLabel>
    90	      <div style={{
    91	        marginTop: 8, padding: '12px 14px', borderRadius: 12,
    92	        background: configured ? (t.isDark ? 'rgba(255,255,255,0.04)' : '#fff') : `${t.accent}10`,
    93	        border: configured ? `0.5px solid ${t.rule}` : `0.5px solid ${t.accent}55`,
    94	        boxShadow: justChanged ? `0 0 0 2px ${t.accent}66` : 'none',
    95	        display: 'flex', alignItems: 'center', gap: 12,
    96	        transition: 'box-shadow 0.3s',
    97	      }}>
    98	        <div style={{
    99	          width: 28, height: 28, borderRadius: 14, flexShrink: 0,
   100	          background: configured ? `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)` : 'rgba(0,0,0,0.08)',
   101	          display: 'flex', alignItems: 'center', justifyContent: 'center',
   102	        }}>
   103	          <Icons.Sparkle size={14} color={configured ? '#fff' : t.sub} stroke={2}/>
   104	        </div>
   105	        <div style={{ flex: 1, minWidth: 0 }}>
   106	          <div style={{ fontSize: 13.5, color: t.ink, fontWeight: 600 }}>
   107	            {configured ? `${providerName} · with this book’s context` : 'No AI provider configured'}
   108	          </div>
   109	          <div style={{ fontSize: 11.5, color: t.sub, marginTop: 1 }}>
   110	            {configured
   111	              ? 'Translations cached per paragraph, one page ahead.'
   112	              : 'Bilingual mode needs an AI provider to translate.'}
   113	          </div>
   114	        </div>
   115	        <button onClick={onSetup} style={{
   116	          padding: '5px 11px', borderRadius: 100, border: 'none',
   117	          background: configured ? (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)') : t.accent,
   118	          color: configured ? t.ink : '#fff',
   119	          fontFamily: 'inherit', fontSize: 11.5, fontWeight: 600, cursor: 'pointer',
   120	          flexShrink: 0,
   121	        }}>{configured ? 'Change…' : 'Set up'}</button>
   122	      </div>
   123	    </div>
   124	  );
   125	}
   126	
   127	// ────────────────────────────────────────────────────
   128	// Provider list row — matches the shipped SettingsRow vocabulary.
   129	// ────────────────────────────────────────────────────
   130	function ProviderRow({ theme, name, model, selected, onClick, last }) {
   131	  const t = theme;
   132	  return (
   133	    <div onClick={onClick} style={{
   134	      display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px',
   135	      borderBottom: last ? 'none' : `0.5px solid ${t.rule}`, cursor: 'pointer',
   136	    }}>
   137	      <div style={{
   138	        width: 30, height: 30, borderRadius: 8, flexShrink: 0, background: AIPE_BRAND,
   139	        display: 'flex', alignItems: 'center', justifyContent: 'center',
   140	      }}>
   141	        <Icons.Sparkle size={17} color="#fff" stroke={1.8}/>
   142	      </div>
   143	      <div style={{ flex: 1, minWidth: 0 }}>
   144	        <div style={{ fontSize: 15, color: t.ink }}>{name}</div>
   145	        <div style={{ fontSize: 11, color: t.sub, marginTop: 1, fontFamily: AIPE_MONO }}>{model}</div>
   146	      </div>
   147	      {selected ? (
   148	        <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexShrink: 0 }}>
   149	          <span style={{ fontSize: 10.5, fontWeight: 600, color: t.accent, letterSpacing: 0.4, textTransform: 'uppercase', whiteSpace: 'nowrap' }}>In use</span>
   150	          <Icons.Check size={16} color={t.accent} stroke={2.6}/>
   151	        </div>
   152	      ) : (
   153	        <Icons.Chevron size={13} color={t.sub} stroke={2}/>
   154	      )}
   155	    </div>
   156	  );
   157	}
   158	
   159	// ────────────────────────────────────────────────────
   160	// AI Providers sheet body — empty + populated.
   161	// ────────────────────────────────────────────────────
   162	function AIProvidersSheetBody({ theme, providers, selectedId, onAdd, onSelect }) {
   163	  const t = theme;
   164	  const empty = !providers || providers.length === 0;
   165	  return (
   166	    <div style={{ padding: '14px 18px 28px' }}>
   167	      {/* why-you're-here context — the bilingual thread, kept visible */}
   168	      <div style={{
   169	        display: 'flex', alignItems: 'center', gap: 10,
   170	        padding: '10px 12px', borderRadius: 10,
   171	        background: `${t.accent}10`, border: `0.5px solid ${t.accent}33`,
   172	        marginBottom: 18,
   173	      }}>
   174	        <div style={{
   175	          width: 22, height: 22, borderRadius: 11, flexShrink: 0,
   176	          background: `${t.accent}1f`, display: 'flex', alignItems: 'center', justifyContent: 'center',
   177	        }}>
   178	          <Icons.Translate size={13} color={t.accent} stroke={1.9}/>
   179	        </div>
   180	        <div style={{ fontSize: 11.5, color: t.ink, lineHeight: 1.35 }}>
   181	          Choose the provider <b style={{ fontWeight: 600 }}>bilingual mode</b> will use to translate this book.
   182	        </div>
   183	      </div>
   184	
   185	      {empty ? (
   186	        <div style={{ textAlign: 'center', padding: '24px 12px 8px' }}>
   187	          <div style={{
   188	            width: 54, height: 54, borderRadius: 27, margin: '0 auto 14px',
   189	            background: `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)`,
   190	            display: 'flex', alignItems: 'center', justifyContent: 'center',
   191	            boxShadow: `0 6px 18px ${t.accent}44`,
   192	          }}>
   193	            <Icons.Sparkle size={26} color="#fff" stroke={1.7}/>
   194	          </div>
   195	          <div style={{ fontFamily: AIPE_SERIF, fontSize: 18, fontWeight: 600, color: t.ink }}>
   196	            No providers yet
   197	          </div>
   198	          <div style={{ fontSize: 12.5, color: t.sub, lineHeight: 1.5, maxWidth: 268, margin: '6px auto 20px' }}>
   199	            Add Claude, OpenAI, or any OpenAI-compatible endpoint. Your API key is stored in the device keychain — never synced.
   200	          </div>
   201	          <button onClick={onAdd} style={{
   202	            display: 'inline-flex', alignItems: 'center', gap: 7,
   203	            padding: '11px 20px', borderRadius: 100, border: 'none',
   204	            background: t.accent, color: '#fff',
   205	            fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer',
   206	            boxShadow: `0 4px 14px ${t.accent}55`,
   207	          }}>
   208	            <Icons.Plus size={17} color="#fff" stroke={2.2}/>Add provider
   209	          </button>
   210	        </div>
   211	      ) : (
   212	        <div>
   213	          <SectionLabel theme={t}>Providers</SectionLabel>
   214	          <div style={{
   215	            marginTop: 8, borderRadius: 14, overflow: 'hidden',
   216	            background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
   217	            boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
   218	          }}>
   219	            {providers.map((p) => (
   220	              <ProviderRow key={p.id} theme={t} name={p.name} model={p.model}
   221	                selected={p.id === selectedId} onClick={() => onSelect && onSelect(p.id)}/>
   222	            ))}
   223	            <div onClick={onAdd} style={{
   224	              display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px', cursor: 'pointer',
   225	            }}>
   226	              <div style={{
   227	                width: 30, height: 30, borderRadius: 8, flexShrink: 0,
   228	                background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)',
   229	                display: 'flex', alignItems: 'center', justifyContent: 'center',
   230	              }}>
   231	                <Icons.Plus size={18} color={t.accent} stroke={2.2}/>
   232	              </div>
   233	              <div style={{ flex: 1, fontSize: 15, color: t.accent, fontWeight: 500 }}>Add provider</div>
   234	            </div>
   235	          </div>
   236	          <div style={{ fontSize: 11.5, color: t.sub, lineHeight: 1.45, padding: '10px 4px 0' }}>
   237	            Tap a provider to use it for translating this book.
   238	          </div>
   239	        </div>
   240	      )}
   241	    </div>
   242	  );
   243	}
   244	
   245	function AIProvidersSheet({ theme, providers = [], selectedId, onBack, onAdd, onSelect, trailing, height = 620 }) {
   246	  return (
   247	    <NavSheet theme={theme} height={height} title="AI Providers" backLabel="Bilingual" onBack={onBack} trailing={trailing}>
   248	      <AIProvidersSheetBody theme={theme} providers={providers} selectedId={selectedId} onAdd={onAdd} onSelect={onSelect}/>
   249	    </NavSheet>
   250	  );
   251	}
   252	
   253	// ────────────────────────────────────────────────────
   254	// ALTERNATIVE C — inline expansion of the engine strip.
   255	// Collapsed = the unconfigured strip; expanded = a minimal provider+key form
   256	// in place. Shows why it can't host the real editor without diverging.
   257	// ────────────────────────────────────────────────────
   258	function EngineStripInline({ theme, expanded }) {
   259	  const t = theme;
   260	  const seg = ['Claude', 'OpenAI', 'Custom'];
   261	  return (
   262	    <div>
   263	      <SectionLabel theme={t}>Translation engine</SectionLabel>
   264	      <div style={{
   265	        marginTop: 8, borderRadius: 12, overflow: 'hidden',
   266	        background: `${t.accent}10`, border: `0.5px solid ${t.accent}55`,
   267	      }}>
   268	        <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px' }}>
   269	          <div style={{
   270	            width: 28, height: 28, borderRadius: 14, flexShrink: 0, background: 'rgba(0,0,0,0.08)',
   271	            display: 'flex', alignItems: 'center', justifyContent: 'center',
   272	          }}>
   273	            <Icons.Sparkle size={14} color={t.sub} stroke={2}/>
   274	          </div>
   275	          <div style={{ flex: 1, minWidth: 0 }}>
   276	            <div style={{ fontSize: 13.5, color: t.ink, fontWeight: 600 }}>No AI provider configured</div>
   277	            <div style={{ fontSize: 11.5, color: t.sub, marginTop: 1 }}>
   278	              {expanded ? 'Add one below to translate.' : 'Bilingual mode needs an AI provider to translate.'}
   279	            </div>
   280	          </div>

exec
/bin/zsh -lc "nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt | sed -n '1,300p' && nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt | sed -n '1,360p' && rg -n \"class AiSettingsViewModel|fun save|upsert|onSave|saved\" android/app/src/main/kotlin/com/vreader/app/ai android/app/src/test/kotlin/com/vreader/app/ai android/app/src/androidTest/kotlin/com/vreader/app/ai" in /Users/ll/workspace/vreader
 succeeded in 0ms:
     1	// Purpose: feature #118 WI-3 (#110 Phase 3) — the AI provider list (the gate), design surface A
     2	// from vreader-ai-android.jsx `AiProviderList`: unconfigured onboards to a single Add action;
     3	// configured shows the active provider + per-provider status (model, or the rejection reason).
     4	// Reuses the shared form vocabulary (NavScreen / SettingsCard / GroupHeader / StatusDot / tokens —
     5	// mapped from this surface's own design file). Stateless: a pure function of the list + callbacks.
     6	package com.vreader.app.ai
     7	
     8	import androidx.compose.foundation.background
     9	import androidx.compose.foundation.clickable
    10	import androidx.compose.foundation.layout.Box
    11	import androidx.compose.foundation.layout.Column
    12	import androidx.compose.foundation.layout.Row
    13	import androidx.compose.foundation.layout.fillMaxWidth
    14	import androidx.compose.foundation.layout.height
    15	import androidx.compose.foundation.layout.heightIn
    16	import androidx.compose.foundation.layout.padding
    17	import androidx.compose.foundation.layout.size
    18	import androidx.compose.foundation.shape.CircleShape
    19	import androidx.compose.foundation.shape.RoundedCornerShape
    20	import androidx.compose.material.icons.Icons
    21	import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
    22	import androidx.compose.material.icons.filled.Add
    23	import androidx.compose.material.icons.filled.AutoAwesome
    24	import androidx.compose.material3.Icon
    25	import androidx.compose.material3.Text
    26	import androidx.compose.runtime.Composable
    27	import androidx.compose.ui.Alignment
    28	import androidx.compose.ui.Modifier
    29	import androidx.compose.ui.draw.clip
    30	import androidx.compose.ui.graphics.Color
    31	import androidx.compose.ui.platform.testTag
    32	import androidx.compose.ui.text.font.FontWeight
    33	import androidx.compose.ui.text.style.TextAlign
    34	import androidx.compose.ui.unit.dp
    35	import androidx.compose.ui.unit.sp
    36	import com.vreader.app.backup.BackupFonts
    37	import com.vreader.app.backup.GroupFooter
    38	import com.vreader.app.backup.GroupHeader
    39	import com.vreader.app.backup.LocalBackupTokens
    40	import com.vreader.app.backup.NavScreen
    41	import com.vreader.app.backup.SettingsCard
    42	import com.vreader.app.backup.StatusDot
    43	import com.vreader.app.backup.VSpace
    44	
    45	@Composable
    46	fun AiProviderListScreen(
    47	    state: AiProviderListState,
    48	    onBack: () -> Unit = {},
    49	    onAdd: () -> Unit = {},
    50	    onEdit: (String) -> Unit = {},
    51	) {
    52	    val t = LocalBackupTokens.current
    53	    val addButton: @Composable () -> Unit = {
    54	        Box(
    55	            Modifier.size(44.dp).clip(RoundedCornerShape(22.dp)).clickable(onClickLabel = "Add provider", onClick = onAdd),
    56	            contentAlignment = Alignment.Center,
    57	        ) { Icon(Icons.Filled.Add, contentDescription = "Add provider", tint = t.tint, modifier = Modifier.size(22.dp)) }
    58	    }
    59	    NavScreen(title = "AI Providers", large = true, onBack = onBack, trailing = addButton) {
    60	        Column(Modifier.padding(horizontal = 18.dp).padding(bottom = 32.dp)) {
    61	            if (state.unconfigured) {
    62	                AiEmptyState(onAdd)
    63	            } else {
    64	                GroupHeader("Providers")
    65	                SettingsCard {
    66	                    state.providers.forEachIndexed { i, p ->
    67	                        ProviderRow(p, last = i == state.providers.lastIndex, onEdit = onEdit)
    68	                    }
    69	                }
    70	                GroupFooter("The selected provider is used for translation, chat, and summaries. Tap one to edit or test it.")
    71	            }
    72	        }
    73	    }
    74	}
    75	
    76	@Composable
    77	private fun AiEmptyState(onAdd: () -> Unit) {
    78	    val t = LocalBackupTokens.current
    79	    Column(Modifier.fillMaxWidth().padding(top = 36.dp), horizontalAlignment = Alignment.CenterHorizontally) {
    80	        Box(Modifier.size(64.dp).clip(CircleShape).background(t.chipBg), contentAlignment = Alignment.Center) {
    81	            Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = t.tint, modifier = Modifier.size(30.dp))
    82	        }
    83	        VSpace(18)
    84	        Text("Connect an AI provider", color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 21.sp, textAlign = TextAlign.Center)
    85	        VSpace(8)
    86	        Text(
    87	            "One key unlocks bilingual translation, chat about a book, and chapter summaries. Your key is stored on-device only.",
    88	            color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 14.sp, lineHeight = 22.sp, textAlign = TextAlign.Center,
    89	        )
    90	        VSpace(18)
    91	        Box(
    92	            Modifier.fillMaxWidth().clip(RoundedCornerShape(13.dp)).background(t.tint)
    93	                .clickable(onClickLabel = "Add a provider", onClick = onAdd).testTag("ai-add-provider").padding(vertical = 14.dp),
    94	            contentAlignment = Alignment.Center,
    95	        ) { Text("Add a provider", color = Color.White, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.SemiBold) }
    96	        GroupFooter("Works with Anthropic, OpenAI-compatible endpoints, and local models.")
    97	    }
    98	}
    99	
   100	@Composable
   101	private fun ProviderRow(p: AiProviderRow, last: Boolean, onEdit: (String) -> Unit) {
   102	    val t = LocalBackupTokens.current
   103	    Box {
   104	        Row(
   105	            Modifier.fillMaxWidth().heightIn(min = 60.dp).clickable(onClick = { onEdit(p.id) })
   106	                .testTag("provider-${p.id}").padding(horizontal = 14.dp),
   107	            verticalAlignment = Alignment.CenterVertically,
   108	        ) {
   109	            // active = filled accent circle; inactive = hollow ring (sep ring + card-coloured core)
   110	            Box(
   111	                Modifier.size(20.dp).clip(CircleShape).background(if (p.active) t.tint else t.sep),
   112	                contentAlignment = Alignment.Center,
   113	            ) {
   114	                if (!p.active) Box(Modifier.size(16.5.dp).clip(CircleShape).background(t.card))
   115	            }
   116	            Column(Modifier.weight(1f).padding(start = 12.dp)) {
   117	                Text(p.name, color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.5.sp, fontWeight = FontWeight.Medium)
   118	                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 2.dp)) {
   119	                    StatusDot(if (p.statusOk) t.green else t.red)
   120	                    Text(
   121	                        p.detail, color = if (p.statusOk) t.sec else t.red,
   122	                        fontFamily = BackupFonts.Mono, fontSize = 11.5.sp, modifier = Modifier.padding(start = 6.dp),
   123	                    )
   124	                }
   125	            }
   126	            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = t.ter, modifier = Modifier.size(18.dp))
   127	        }
   128	        if (!last) Box(Modifier.fillMaxWidth().padding(start = 46.dp).height(0.5.dp).background(t.sep).align(Alignment.BottomStart))
   129	    }
   130	}
     1	// Purpose: feature #118 WI-3 (#110 Phase 3) — the add/edit AI provider form (the committed
     2	// EditorSheet contract from vreader-ai-provider-fields.jsx): Provider Type (segmented) · Name ·
     3	// Endpoint (Base URL + Model, blank → kind default, with the path-append hint) · Sampling
     4	// (Temperature slider + Max Tokens stepper) · API Key (secure; edit shows Delete Key) · Connection
     5	// (Test — enabled once a key is available, idle/testing/ok/fail). Reuses the shared form
     6	// vocabulary; stateless: a pure function of AiEditState + callbacks.
     7	package com.vreader.app.ai
     8	
     9	import androidx.compose.foundation.background
    10	import androidx.compose.foundation.clickable
    11	import androidx.compose.foundation.gestures.detectTapGestures
    12	import androidx.compose.foundation.layout.Box
    13	import androidx.compose.foundation.layout.Column
    14	import androidx.compose.foundation.layout.Row
    15	import androidx.compose.foundation.layout.fillMaxSize
    16	import androidx.compose.foundation.layout.fillMaxWidth
    17	import androidx.compose.foundation.layout.height
    18	import androidx.compose.foundation.layout.heightIn
    19	import androidx.compose.foundation.layout.padding
    20	import androidx.compose.foundation.layout.size
    21	import androidx.compose.foundation.layout.sizeIn
    22	import androidx.compose.foundation.shape.CircleShape
    23	import androidx.compose.foundation.shape.RoundedCornerShape
    24	import androidx.compose.foundation.text.BasicTextField
    25	import androidx.compose.material3.Text
    26	import androidx.compose.runtime.Composable
    27	import androidx.compose.runtime.getValue
    28	import androidx.compose.runtime.mutableIntStateOf
    29	import androidx.compose.runtime.remember
    30	import androidx.compose.runtime.setValue
    31	import androidx.compose.ui.Alignment
    32	import androidx.compose.ui.Modifier
    33	import androidx.compose.ui.draw.clip
    34	import androidx.compose.ui.graphics.Color
    35	import androidx.compose.ui.graphics.SolidColor
    36	import androidx.compose.ui.input.pointer.pointerInput
    37	import androidx.compose.ui.layout.onSizeChanged
    38	import androidx.compose.ui.platform.LocalDensity
    39	import androidx.compose.ui.platform.testTag
    40	import androidx.compose.ui.text.TextStyle
    41	import androidx.compose.ui.text.font.FontWeight
    42	import androidx.compose.ui.text.input.PasswordVisualTransformation
    43	import androidx.compose.ui.text.input.VisualTransformation
    44	import androidx.compose.ui.unit.dp
    45	import androidx.compose.ui.unit.sp
    46	import com.vreader.app.backup.AppSheet
    47	import com.vreader.app.backup.BackupFonts
    48	import com.vreader.app.backup.GroupFooter
    49	import com.vreader.app.backup.GroupHeader
    50	import com.vreader.app.backup.LocalBackupTokens
    51	import com.vreader.app.backup.SettingsCard
    52	import com.vreader.app.backup.VSpace
    53	
    54	@Composable
    55	fun AiProviderEditSheet(
    56	    state: AiEditState,
    57	    onKind: (AiProviderKind) -> Unit = {},
    58	    onName: (String) -> Unit = {},
    59	    onBaseUrl: (String) -> Unit = {},
    60	    onModel: (String) -> Unit = {},
    61	    onTemperature: (Double) -> Unit = {},
    62	    onMaxTokens: (Int) -> Unit = {},
    63	    onApiKey: (String) -> Unit = {},
    64	    onDeleteKey: () -> Unit = {},
    65	    onTest: () -> Unit = {},
    66	    onSave: () -> Unit = {},
    67	    onCancel: () -> Unit = {},
    68	) {
    69	    val t = LocalBackupTokens.current
    70	    Box(Modifier.fillMaxSize()) {
    71	        AppSheet(
    72	            title = if (state.editMode) "Edit Provider" else "Add Provider",
    73	            leading = {
    74	                Box(Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).clickable(onClick = onCancel), contentAlignment = Alignment.CenterStart) {
    75	                    Text("Cancel", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 15.sp)
    76	                }
    77	            },
    78	            trailing = {
    79	                Box(Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).clickable(enabled = state.canSave, onClick = onSave).testTag("ai-save"), contentAlignment = Alignment.CenterEnd) {
    80	                    Text("Save", color = if (state.canSave) t.tint else t.ter, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
    81	                }
    82	            },
    83	        ) {
    84	            Column(Modifier.padding(horizontal = 18.dp).padding(top = 16.dp, bottom = 32.dp)) {
    85	                GroupHeader("Provider Type")
    86	                Segmented(state.kind, onKind)
    87	
    88	                VSpace(20)
    89	                GroupHeader("Name")
    90	                SettingsCard { Field("", state.name, "e.g. OpenRouter", onName) }
    91	
    92	                VSpace(20)
    93	                GroupHeader("Endpoint")
    94	                SettingsCard {
    95	                    Field("Base URL", state.baseUrl, state.kind.defaultBaseUrl, onBaseUrl, mono = true)
    96	                    Divider()
    97	                    Field("Model", state.model, state.kind.defaultModel, onModel)
    98	                }
    99	                GroupFooter(state.kind.endpointPathHint + "  Leave blank to use the default.")
   100	
   101	                VSpace(20)
   102	                GroupHeader("Sampling")
   103	                SettingsCard {
   104	                    TemperatureRow(state.temperature, onTemperature)
   105	                    Divider()
   106	                    MaxTokensRow(state.maxTokens, onMaxTokens)
   107	                }
   108	
   109	                VSpace(20)
   110	                GroupHeader("API Key")
   111	                SettingsCard {
   112	                    if (state.editMode && state.keyAlreadySaved && state.apiKey.isBlank()) {
   113	                        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
   114	                            Text("••••••••••••••", color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 16.sp, modifier = Modifier.weight(1f))
   115	                            Box(Modifier.size(19.dp).clip(CircleShape).background(t.green))
   116	                        }
   117	                        Divider()
   118	                        Box(Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable(onClick = onDeleteKey).padding(horizontal = 14.dp), contentAlignment = Alignment.CenterStart) {
   119	                            Text("Delete Key", color = t.red, fontFamily = BackupFonts.Sans, fontSize = 15.sp)
   120	                        }
   121	                    } else {
   122	                        Field("", state.apiKey, "Enter API Key", onApiKey, secure = true)
   123	                    }
   124	                }
   125	                if (!state.editMode) GroupFooter("Stored in the Android Keystore when you tap Save — but you can test it below first.")
   126	
   127	                VSpace(20)
   128	                GroupHeader("Connection")
   129	                SettingsCard {
   130	                    Row(Modifier.fillMaxWidth().padding(14.dp)) { TestChip(state.test, state.canTest, onTest) }
   131	                    if (state.test == AiConnTest.ok || state.test == AiConnTest.fail) TestResult(state.test, state.testMessage)
   132	                }
   133	                if (!state.canTest) GroupFooter("Enter an API key above to test — no need to save first.")
   134	            }
   135	        }
   136	    }
   137	}
   138	
   139	@Composable
   140	private fun Segmented(value: AiProviderKind, onChange: (AiProviderKind) -> Unit) {
   141	    val t = LocalBackupTokens.current
   142	    Row(Modifier.fillMaxWidth().padding(top = 8.dp).clip(RoundedCornerShape(12.dp)).background(t.codeBg).padding(3.dp)) {
   143	        AiProviderKind.entries.forEach { k ->
   144	            val on = k == value
   145	            Box(
   146	                Modifier.weight(1f).clip(RoundedCornerShape(10.dp)).background(if (on) t.card else Color.Transparent)
   147	                    .clickable { onChange(k) }.testTag("kind-${k.name}").padding(vertical = 9.dp),
   148	                contentAlignment = Alignment.Center,
   149	            ) {
   150	                Text(k.displayName, color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 13.5.sp, fontWeight = if (on) FontWeight.SemiBold else FontWeight.Medium)
   151	            }
   152	        }
   153	    }
   154	}
   155	
   156	@Composable
   157	private fun Field(label: String, value: String, placeholder: String, onChange: (String) -> Unit, mono: Boolean = false, secure: Boolean = false) {
   158	    val t = LocalBackupTokens.current
   159	    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
   160	        if (label.isNotEmpty()) Text(label, color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 15.sp, modifier = Modifier.padding(end = 10.dp))
   161	        BasicTextField(
   162	            value = value, onValueChange = onChange, singleLine = true,
   163	            textStyle = TextStyle(color = t.ink, fontFamily = if (mono) BackupFonts.Mono else BackupFonts.Sans, fontSize = if (mono) 13.5.sp else 15.sp),
   164	            cursorBrush = SolidColor(t.tint),
   165	            visualTransformation = if (secure) PasswordVisualTransformation() else VisualTransformation.None,
   166	            modifier = Modifier.weight(1f).testTag("field-${label.ifBlank { placeholder }}"),
   167	            decorationBox = { inner ->
   168	                Box(Modifier.fillMaxWidth(), contentAlignment = if (label.isEmpty()) Alignment.CenterStart else Alignment.CenterEnd) {
   169	                    if (value.isEmpty()) Text(placeholder, color = t.placeholder, fontFamily = if (mono) BackupFonts.Mono else BackupFonts.Sans, fontSize = if (mono) 13.5.sp else 15.sp)
   170	                    inner()
   171	                }
   172	            },
   173	        )
   174	    }
   175	}
   176	
   177	@Composable
   178	private fun Divider() {
   179	    val t = LocalBackupTokens.current
   180	    Box(Modifier.fillMaxWidth().padding(start = 14.dp).height(0.5.dp).background(t.sep))
   181	}
   182	
   183	@Composable
   184	private fun TemperatureRow(value: Double, onChange: (Double) -> Unit) {
   185	    val t = LocalBackupTokens.current
   186	    val density = LocalDensity.current
   187	    var trackPx by remember { mutableIntStateOf(0) }  // measured track width, in px
   188	    Column(Modifier.fillMaxWidth().padding(14.dp)) {
   189	        Row(verticalAlignment = Alignment.CenterVertically) {
   190	            Text("Temperature", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 15.sp, modifier = Modifier.weight(1f))
   191	            Text("%.1f".format(value), color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.sp)
   192	        }
   193	        // Custom track + thumb (0.0–2.0); tap maps x → value using the MEASURED width.
   194	        val frac = (value / 2.0).toFloat().coerceIn(0f, 1f)
   195	        Box(
   196	            Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 4.dp).height(22.dp).testTag("temperature-slider")
   197	                .onSizeChanged { trackPx = it.width }
   198	                .pointerInput(Unit) {
   199	                    detectTapGestures { offset -> if (trackPx > 0) onChange(((offset.x / trackPx) * 2.0).coerceIn(0.0, 2.0)) }
   200	                },
   201	            contentAlignment = Alignment.CenterStart,
   202	        ) {
   203	            Box(Modifier.fillMaxWidth().height(4.dp).clip(RoundedCornerShape(2.dp)).background(t.sep))
   204	            Box(Modifier.fillMaxWidth(frac).height(4.dp).clip(RoundedCornerShape(2.dp)).background(t.tint))
   205	            val trackDp = with(density) { trackPx.toDp() }
   206	            val startPad = (trackDp * frac - 11.dp).coerceIn(0.dp, (trackDp - 22.dp).coerceAtLeast(0.dp))
   207	            Box(Modifier.padding(start = startPad).size(22.dp).clip(CircleShape).background(Color.White))
   208	        }
   209	    }
   210	}
   211	
   212	@Composable
   213	private fun MaxTokensRow(value: Int, onChange: (Int) -> Unit) {
   214	    val t = LocalBackupTokens.current
   215	    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
   216	        Text("Max Tokens: $value", color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.sp, modifier = Modifier.weight(1f))
   217	        Row(Modifier.clip(RoundedCornerShape(8.dp)).background(t.codeBg)) {
   218	            Box(Modifier.size(width = 42.dp, height = 30.dp).clickable(onClickLabel = "decrease", onClick = { onChange((value - 256).coerceAtLeast(256)) }).testTag("tokens-dec"), contentAlignment = Alignment.Center) {
   219	                Text("−", color = t.ink, fontSize = 19.sp)
   220	            }
   221	            Box(Modifier.size(width = 0.5.dp, height = 30.dp).background(t.sep))
   222	            Box(Modifier.size(width = 42.dp, height = 30.dp).clickable(onClickLabel = "increase", onClick = { onChange((value + 256).coerceAtMost(8192)) }).testTag("tokens-inc"), contentAlignment = Alignment.Center) {
   223	                Text("+", color = t.ink, fontSize = 19.sp)
   224	            }
   225	        }
   226	    }
   227	}
   228	
   229	@Composable
   230	private fun TestChip(test: AiConnTest, enabled: Boolean, onTest: () -> Unit) {
   231	    val t = LocalBackupTokens.current
   232	    val label = if (test == AiConnTest.testing) "Testing…" else "Test Connection"
   233	    Box(
   234	        Modifier.clip(RoundedCornerShape(100.dp)).background(if (enabled) t.chipBg else Color.Transparent)
   235	            .clickable(enabled = enabled && test != AiConnTest.testing, onClick = onTest).testTag("ai-test")
   236	            .padding(horizontal = 15.dp, vertical = 8.dp),
   237	    ) {
   238	        Text(label, color = if (enabled) t.tint else t.ter, fontFamily = BackupFonts.Sans, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
   239	    }
   240	}
   241	
   242	@Composable
   243	private fun TestResult(test: AiConnTest, message: String) {
   244	    val t = LocalBackupTokens.current
   245	    val ok = test == AiConnTest.ok
   246	    val fallback = if (ok) "Connected — the provider responded successfully." else "Failed: 401 Unauthorized — check your API key."
   247	    Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, bottom = 14.dp), verticalAlignment = Alignment.Top) {
   248	        Box(Modifier.size(16.dp).clip(CircleShape).background(if (ok) t.green else t.red))
   249	        Text(message.ifBlank { fallback }, color = if (ok) t.green else t.red, fontFamily = BackupFonts.Sans, fontSize = 13.sp, lineHeight = 19.sp, modifier = Modifier.padding(start = 7.dp).testTag("ai-test-result"))
   250	    }
   251	}
android/app/src/test/kotlin/com/vreader/app/ai/AiChatViewModelTest.kt:52:    private suspend fun configure() = store.upsert("p1", "Claude", AiProviderKind.anthropicNative, "", "claude-sonnet-4-6", 0.7, 2048, "k")
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:1:// Purpose: feature #118 WI-1 (#110 Phase 3) — persists saved AI provider profiles + the active
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:20:/** A saved AI provider. `encryptedApiKey` is a [SecretCipher] token, never plaintext. */
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:58:     * key. The first profile added becomes active. Returns the saved profile (key encrypted).
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:60:    suspend fun upsert(
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:70:        lateinit var saved: AiProviderProfile
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:79:            saved = AiProviderProfile(id, name, kind, baseUrl, model, temperature, maxTokens, encrypted)
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:80:            val next = cur.profiles.filterNot { it.id == id } + saved
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:84:        return saved
android/app/src/test/kotlin/com/vreader/app/ai/AiProviderStoreTest.kt:45:        store.upsert(id, "Provider $id", kind, kind.defaultBaseUrl, kind.defaultModel, 0.7, 2048, key)
android/app/src/test/kotlin/com/vreader/app/ai/AiProviderStoreTest.kt:47:    @Test fun upsert_storesCiphertext_firstBecomesActive() = runTest {
android/app/src/test/kotlin/com/vreader/app/ai/AiProviderStoreTest.kt:66:        store.upsert("p1", "Renamed", AiProviderKind.openAiCompatible, "https://x/", "gpt-4o-mini", 0.9, 1024, apiKey = null)
android/app/src/test/kotlin/com/vreader/app/ai/AiSettingsViewModelTest.kt:29:class AiSettingsViewModelTest {
android/app/src/test/kotlin/com/vreader/app/ai/AiSettingsViewModelTest.kt:82:        store.upsert("p1", "Claude", AiProviderKind.anthropicNative, "", "claude-sonnet-4-6", 0.7, 2048, "k")
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsUiState.kt:40:    /** canSave = name non-empty AND a key is available — entered now, or already saved on edit (a
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsUiState.kt:44:    /** Test is enabled once a key is available (entered now, or already saved in edit mode). */
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt:66:    onSave: () -> Unit = {},
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt:79:                Box(Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).clickable(enabled = state.canSave, onClick = onSave).testTag("ai-save"), contentAlignment = Alignment.CenterEnd) {
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:20:class AiSettingsViewModel(
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:85:    fun save() {
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:89:            store.upsert(

exec
/bin/zsh -lc "nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt | sed -n '1,145p' && nl -ba android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt | sed -n '1,300p' && rg -n \"AiProviderStore|AiSettingsViewModel|SecretCipher|KeystoreSecretCipher|DataStore\" android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt android/app/src/main/kotlin/com/vreader/app | head -200" in /Users/ll/workspace/vreader
 succeeded in 0ms:
     1	// Purpose: feature #118 WI-3 (#110 Phase 3) — drives the AI provider list + editor: observes the
     2	// AiProviderStore for the list, owns the editor form state, runs Test Connection against the LIVE
     3	// form (a transient AiClient built from the form + key, no save first), and saves/deletes. v1 list
     4	// status is ok+model (persisted per-provider test status is a follow-on). The key is never logged.
     5	package com.vreader.app.ai
     6	
     7	import androidx.lifecycle.ViewModel
     8	import androidx.lifecycle.viewModelScope
     9	import kotlinx.coroutines.CoroutineDispatcher
    10	import kotlinx.coroutines.Dispatchers
    11	import kotlinx.coroutines.flow.MutableStateFlow
    12	import kotlinx.coroutines.flow.SharingStarted
    13	import kotlinx.coroutines.flow.StateFlow
    14	import kotlinx.coroutines.flow.map
    15	import kotlinx.coroutines.flow.stateIn
    16	import kotlinx.coroutines.launch
    17	import kotlinx.coroutines.withContext
    18	import java.util.UUID
    19	
    20	class AiSettingsViewModel(
    21	    private val store: AiProviderStore,
    22	    private val clientDispatcher: CoroutineDispatcher = Dispatchers.IO,
    23	    private val factory: (AiProviderProfile, String) -> AiClient = { p, key -> AiProviderFactory.create(p, key) },
    24	) : ViewModel() {
    25	
    26	    val listState: StateFlow<AiProviderListState> = store.observe()
    27	        .map { snap ->
    28	            AiProviderListState(
    29	                snap.profiles.map { p ->
    30	                    AiProviderRow(p.id, p.name, active = p.id == snap.activeId, statusOk = true, detail = p.model.ifBlank { p.kind.defaultModel })
    31	                }
    32	            )
    33	        }
    34	        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AiProviderListState())
    35	
    36	    private val _edit = MutableStateFlow<AiEditState?>(null)
    37	    val editState: StateFlow<AiEditState?> = _edit
    38	
    39	    // Bumped whenever the editor opens/closes or a new test starts — an in-flight test result is
    40	    // only applied if its generation still matches, so a stale Ok/Fail can't land on a different
    41	    // form (the user closed it, opened another provider, or re-tested).
    42	    private var testGen = 0
    43	
    44	    fun openAdd() { testGen++; _edit.value = AiEditState(editMode = false) }
    45	
    46	    fun openEdit(id: String) = viewModelScope.launch {
    47	        val p = store.list().firstOrNull { it.id == id } ?: return@launch
    48	        testGen++
    49	        _edit.value = AiEditState(
    50	            editMode = true, id = p.id, kind = p.kind, name = p.name, baseUrl = p.baseUrl, model = p.model,
    51	            temperature = p.temperature, maxTokens = p.maxTokens, keyAlreadySaved = true,
    52	        )
    53	    }
    54	
    55	    fun close() { testGen++; _edit.value = null }
    56	
    57	    fun update(transform: (AiEditState) -> AiEditState) { _edit.value = _edit.value?.let(transform) }
    58	
    59	    fun test() {
    60	        val s = _edit.value ?: return
    61	        if (!s.canTest) return
    62	        val gen = ++testGen
    63	        update { it.copy(test = AiConnTest.testing, testMessage = "") }
    64	        viewModelScope.launch {
    65	            // Key lookup + client creation + the network call all off the main thread.
    66	            val result = withContext(clientDispatcher) {
    67	                val key = if (s.apiKey.isNotBlank()) s.apiKey else s.id?.let { store.apiKey(it) } ?: ""
    68	                val profile = AiProviderProfile(
    69	                    id = s.id ?: "transient", name = s.name, kind = s.kind, baseUrl = s.effectiveBaseUrl,
    70	                    model = s.effectiveModel, temperature = s.temperature, maxTokens = s.maxTokens, encryptedApiKey = "",
    71	                )
    72	                runCatching { factory(profile, key).testConnection() }
    73	                    .getOrElse { AiTestResult.Fail(AiError.Offline, it.message ?: "failed") }
    74	            }
    75	            if (gen != testGen) return@launch  // superseded by a newer test / form open / close
    76	            update {
    77	                when (result) {
    78	                    is AiTestResult.Ok -> it.copy(test = AiConnTest.ok, testMessage = "Connected — the provider responded successfully.")
    79	                    is AiTestResult.Fail -> it.copy(test = AiConnTest.fail, testMessage = result.message)
    80	                }
    81	            }
    82	        }
    83	    }
    84	
    85	    fun save() {
    86	        val s = _edit.value ?: return
    87	        if (!s.canSave) return
    88	        viewModelScope.launch {
    89	            store.upsert(
    90	                id = s.id ?: UUID.randomUUID().toString(),
    91	                name = s.name, kind = s.kind, baseUrl = s.baseUrl, model = s.model,
    92	                temperature = s.temperature, maxTokens = s.maxTokens,
    93	                apiKey = s.apiKey.ifBlank { null },  // blank on edit = keep existing
    94	            )
    95	            _edit.value = null
    96	        }
    97	    }
    98	
    99	    fun delete() {
   100	        val id = _edit.value?.id ?: return
   101	        viewModelScope.launch { store.delete(id); _edit.value = null }
   102	    }
   103	
   104	    fun setActive(id: String) = viewModelScope.launch { store.setActive(id) }
   105	}
     1	// Purpose: Application + manual DI container — feature #106 WI-8. Holds the
     2	// process-singleton Room database, repository, and importer so the Library
     3	// ViewModel gets shared instances (a Hilt module is a Phase-3 follow-on; manual
     4	// wiring at the app edge keeps the foundation bar dependency-light — rule 50 §5).
     5	package com.vreader.app
     6	
     7	import android.app.Application
     8	import android.content.Context
     9	import com.vreader.app.data.BookImporter
    10	import com.vreader.app.data.LibraryRepository
    11	import com.vreader.app.data.VReaderDatabase
    12	import com.vreader.app.reader.BookOpener
    13	import com.vreader.app.search.BookTextExtractor
    14	import com.vreader.app.search.EpubTextExtractor
    15	import com.vreader.app.search.asSearcher
    16	import com.vreader.app.search.SearchIndexCoordinator
    17	import com.vreader.app.search.TxtMdTextExtractor
    18	import com.vreader.app.annotations.AnnotationsRepository
    19	import com.vreader.app.stats.ReadingStatsRepository
    20	import com.vreader.app.stats.ReadingTimeTracker
    21	import com.vreader.app.stats.clock.SystemDateClock
    22	import com.vreader.app.stats.clock.SystemElapsedClock
    23	import kotlinx.coroutines.CoroutineScope
    24	import kotlinx.coroutines.Dispatchers
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
    86	    private val epubTextExtractor: EpubTextExtractor by lazy { EpubTextExtractor(bookOpener) }
    87	    private val txtMdTextExtractor: TxtMdTextExtractor by lazy { TxtMdTextExtractor() }
    88	    val searchIndexCoordinator: SearchIndexCoordinator by lazy {
    89	        SearchIndexCoordinator(
    90	            repository = repository,
    91	            searchDao = database.searchDao(),
    92	            extractorFor = { fmt: BookFormat ->
    93	                when (fmt) {
    94	                    BookFormat.epub -> epubTextExtractor
    95	                    BookFormat.txt, BookFormat.md -> txtMdTextExtractor
    96	                    BookFormat.pdf, BookFormat.azw3 -> null   // metadata-only — never indexed
    97	                }
    98	            },
    99	            scope = appScope,
   100	            ioDispatcher = Dispatchers.IO,
   101	        )
   102	    }
   103	
   104	    /** Idempotent — starts the single search-index collector (the coordinator's own AtomicBoolean
   105	     *  makes a repeat call a no-op). Called once from [VReaderApp.onCreate]. */
   106	    fun startSearchIndexing() = searchIndexCoordinator.startSearchIndexing()
   107	
   108	    // feature #128 WI-6 — the query pipeline. SearchRepository turns a raw query into an observable
   109	    // Flow of first-hit-per-book text hits (grows as indexing completes); RecentSearchesStore is a
   110	    // device-local DataStore under noBackupFilesDir (the readerSettingsStore precedent — recents are
   111	    // per-device, NOT in the backup contract). The SearchViewModel factory wires the metadata filter,
   112	    // the text-hit Flow, the completeness gate, and recent-recording for the WI-7 screen.
   113	    val searchRepository: com.vreader.app.search.SearchRepository by lazy {
   114	        com.vreader.app.search.SearchRepository(database.searchDao())
   115	    }
   116	    private val recentSearchesDataStore: androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences> by lazy {
   117	        androidx.datastore.preferences.core.PreferenceDataStoreFactory.create {
   118	            File(appContext.noBackupFilesDir, "recent_searches.preferences_pb")
   119	        }
   120	    }
   121	    val recentSearchesStore: com.vreader.app.search.RecentSearchesStore by lazy {
   122	        com.vreader.app.search.RecentSearchesStore(recentSearchesDataStore)
   123	    }
   124	
   125	    /**
   126	     * feature #133 WI-10 — the per-reader-session in-book-search ViewModel for a TXT/MD host. Wires the
   127	     * WI-6 [InBookSearchRepository] (FTS DAO page/count/resume + the WI-4 [TxtMdInBookHitResolver] over the
   128	     * already-decoded [decodedText]) behind the WI-8 [InBookSearchViewModel], gated by the WI-7
   129	     * [IndexStateGate] over the DAO's `observeIndexState` Flow and fed the GLOBAL recents store.
   130	     *
   131	     * The EPUB engine seam is NEVER invoked for a TXT/MD host (the repository dispatches only the TXT/MD
   132	     * branch for `txt`/`md`), so `epubEngineFor` is an error-throwing guard — a call would be a wiring bug.
   133	     * ONE [InBookSearchRepository] per session (the VM's `closeAllEpubCursors` lifecycle contract holds
   134	     * uniformly even though TXT has no cursors). [coroutineScope] is the VM's `viewModelScope` in production
   135	     * (the VM cancels its child collectors on `onCleared`).
   136	     */
   137	    fun inBookSearchViewModel(
   138	        bookKey: String,
   139	        format: BookFormat,
   140	        decodedText: String,
   141	        contentSHA256: String,
   142	        fileByteCount: Long,
   143	        coroutineScope: CoroutineScope,
   144	    ): com.vreader.app.search.InBookSearchViewModel {
   145	        val searchDao = database.searchDao()
   146	        val repository = com.vreader.app.search.InBookSearchRepository(
   147	            dispatcher = Dispatchers.Default,
   148	            fts = com.vreader.app.search.InBookFtsDeps(
   149	                matchingChunksPage = { ftsQuery, afterSectionIndex, afterChunkOrdinal, afterId, limit ->
   150	                    searchDao.matchingChunksPage(bookKey, ftsQuery, afterSectionIndex, afterChunkOrdinal, afterId, limit)
   151	                },
   152	                chunkAtOrAfter = { ftsQuery, atSectionIndex, atChunkOrdinal, atId ->
   153	                    searchDao.chunkAtOrAfter(bookKey, ftsQuery, atSectionIndex, atChunkOrdinal, atId)
   154	                },
   155	                // The resolver re-derives the chunk boundaries from the ALREADY-decoded reader text (no I/O);
   156	                // memoized per session inside the resolver (built once).
   157	                resolverFor = {
   158	                    com.vreader.app.search.TxtMdInBookHitResolver(
   159	                        contentSHA256 = contentSHA256,
   160	                        fileByteCount = fileByteCount,
   161	                        format = format.name,
   162	                        decodedText = decodedText,
   163	                    )
   164	                },
   165	            ),
   166	            // TXT/MD never reaches the EPUB branch — a call here is a dispatch bug, fail fast.
   167	            epubEngineFor = { error("EPUB in-book search engine requested on a TXT/MD host") },
   168	        )
   169	        return com.vreader.app.search.InBookSearchViewModel(
   170	            bookKey = bookKey,
   171	            format = format,
   172	            searcher = repository.asSearcher(),
   173	            indexStateGate = com.vreader.app.search.IndexStateGate(Dispatchers.Default),
   174	            indexStateFlow = searchDao.observeIndexState(bookKey),
   175	            // For a settled-`indexed` TXT/MD row the gate consults this to decide Ready vs definitive
   176	            // NoResults. `hasOccurrence` carries no query, so we report Ready (true) and let the actual
   177	            // `page(...)` be the source of truth: a settled book with zero matches runs one fast FTS query
   178	            // and the repository returns NoResults — the SAME UI outcome the gate's occurrence short-circuit
   179	            // would give, without threading the live query through a shared mutable seam (no race). The gate
   180	            // is only consulted on a settled-indexed row, so this never fires while Indexing/missing/failed.
   181	            hasOccurrence = { true },
   182	            recentsFlow = recentSearchesStore.recents(),
   183	            recordQuery = { q -> recentSearchesStore.record(q) },
   184	            dispatcher = Dispatchers.Default,
   185	            coroutineScope = coroutineScope,
   186	        )
   187	    }
   188	
   189	    /**
   190	     * feature #133 WI-11 — the per-reader-session in-book-search ViewModel for the EPUB host. EPUB search does
   191	     * NOT use the #128 FTS index at all (a chunk-level, location-less index cannot yield a jumpable position);
   192	     * instead the WI-6 [InBookSearchRepository]'s EPUB branch runs Readium's OWN `SearchService` over the LIVE
   193	     * [publication] via the WI-5 [EpubInBookSearchEngine] production constructor (which wraps the real
   194	     * publication behind the `PublicationSearchSource` seam), returning navigable Readium `Locator`s the host
   195	     * jumps to with `navigator.go`.
   196	     *
   197	     * EPUB bypasses the WI-7 index-state gate entirely: the [indexStateFlow] emits `null` (missing) and
   198	     * [hasOccurrence] reports Ready, so the gate resolves to Ready and the engine's own `isSearchable` probe
   199	     * is the real capability check (an un-searchable publication → the repository's [InBookSearchOutcome.Unsupported]
   200	     * → the WI-8 VM's `hidesSearchEntry`, so the host omits the Search icon). The TXT/MD FTS branch is NEVER
   201	     * invoked for an EPUB host, so its factories are error-throwing guards (a call would be a wiring bug).
   202	     *
   203	     * ONE [InBookSearchRepository] per session (so the live Readium `SearchIterator` behind
   204	     * `SearchCursor.Epub` is held once and disposed via `closeAllEpubCursors` on dismiss / `onCleared`).
   205	     * [coroutineScope] is the host's `lifecycleScope` in production (the VM cancels its child collectors on
   206	     * `onCleared`).
   207	     */
   208	    fun epubInBookSearchViewModel(
   209	        bookKey: String,
   210	        publication: org.readium.r2.shared.publication.Publication,
   211	        coroutineScope: CoroutineScope,
   212	    ): com.vreader.app.search.InBookSearchViewModel {
   213	        val repository = com.vreader.app.search.InBookSearchRepository(
   214	            dispatcher = Dispatchers.Default,
   215	            // The EPUB host never reaches the FTS branch (the repository dispatches only the EPUB branch for
   216	            // `epub`), so the TXT/MD deps are error-throwing guards — a call here is a wiring bug, fail fast.
   217	            fts = com.vreader.app.search.InBookFtsDeps(
   218	                matchingChunksPage = { _, _, _, _, _ -> error("FTS matchingChunksPage requested on an EPUB host") },
   219	                chunkAtOrAfter = { _, _, _, _ -> error("FTS chunkAtOrAfter requested on an EPUB host") },
   220	                resolverFor = { error("FTS resolver requested on an EPUB host") },
   221	            ),
   222	            // The LIVE wiring: build the WI-5 engine over the real Readium publication (its production
   223	            // constructor wraps the publication behind the `PublicationSearchSource` seam). One engine per
   224	            // repository/session; the repository memoizes it per bookKey.
   225	            epubEngineFor = { com.vreader.app.search.EpubInBookSearchEngine(publication) },
   226	        )
   227	        return com.vreader.app.search.InBookSearchViewModel(
   228	            bookKey = bookKey,
   229	            format = BookFormat.epub,
   230	            searcher = repository.asSearcher(),
   231	            indexStateGate = com.vreader.app.search.IndexStateGate(Dispatchers.Default),
   232	            // EPUB bypasses the FTS index-state gate: a `null` (missing) row + `hasOccurrence == true` resolve
   233	            // the gate to Ready, so the engine's own `isSearchable` probe is the capability check.
   234	            indexStateFlow = kotlinx.coroutines.flow.flowOf(null),
   235	            hasOccurrence = { true },
   236	            recentsFlow = recentSearchesStore.recents(),
   237	            recordQuery = { q -> recentSearchesStore.record(q) },
   238	            dispatcher = Dispatchers.Default,
   239	            coroutineScope = coroutineScope,
   240	        )
   241	    }
   242	
   243	    /** Builds a [com.vreader.app.search.SearchViewModel] wired to the live library, in-text repository,
   244	     *  recents, collections, and the settled-completeness gate. */
   245	    fun searchViewModel(): com.vreader.app.search.SearchViewModel =
   246	        com.vreader.app.search.SearchViewModel(
   247	            libraryFlow = repository.observeLibrary(),
   248	            textHitsFor = { q -> searchRepository.textHits(q) },
   249	            recentsFlow = recentSearchesStore.recents(),
   250	            collectionsFlow = collectionRepository.observeCollections(),
   251	            indexCompleteFlow = database.searchDao().observeUnsettledIndexableCount()
   252	                .map { it == 0 },
   253	            recordQuery = { q -> recentSearchesStore.record(q) },
   254	        )
   255	
   256	    /** In-memory last reading char-offset per fingerprintKey. Written synchronously on
   257	     *  save so a fast rotation / reopen restores the LATEST position without waiting for
   258	     *  the async Room write to commit; Room remains the durable store across process death. */
   259	    private val lastOffsets = java.util.concurrent.ConcurrentHashMap<String, Int>()
   260	    fun cacheOffset(fingerprintKey: String, charOffsetUtf16: Int) { lastOffsets[fingerprintKey] = charOffsetUtf16 }
   261	    fun cachedOffset(fingerprintKey: String): Int? = lastOffsets[fingerprintKey]
   262	
   263	    /** In-memory last PDF page index per fingerprintKey — a TYPED cache distinct from the
   264	     *  char-offset one (feature #115; a PDF position is a page, not a UTF-16 offset). */
   265	    private val lastPages = java.util.concurrent.ConcurrentHashMap<String, Int>()
   266	    fun cachePage(fingerprintKey: String, page: Int) { lastPages[fingerprintKey] = page }
   267	    fun cachedPage(fingerprintKey: String): Int? = lastPages[fingerprintKey]
   268	}
   269	
   270	class VReaderApp : Application() {
   271	    lateinit var container: AppContainer
   272	        private set
   273	
   274	    override fun onCreate() {
   275	        super.onCreate()
   276	        container = AppContainer(this)
   277	        // feature #128 WI-5 — eagerly start the cross-book search-index collector (idempotent).
   278	        container.startSearchIndexing()
   279	    }
   280	}
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:64:    // feature #129 — reader display settings. A device-local DataStore (the OpdsSourceStore /
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:65:    // AiProviderStore precedent), global (not per-book), process-singleton so a settings change
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:68:    private val readerSettingsDataStore: androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences> by lazy {
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:69:        androidx.datastore.preferences.core.PreferenceDataStoreFactory.create {
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:74:        com.vreader.app.reader.settings.ReaderSettingsStore(readerSettingsDataStore)
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:110:    // device-local DataStore under noBackupFilesDir (the readerSettingsStore precedent — recents are
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:116:    private val recentSearchesDataStore: androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences> by lazy {
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:117:        androidx.datastore.preferences.core.PreferenceDataStoreFactory.create {
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:122:        com.vreader.app.search.RecentSearchesStore(recentSearchesDataStore)
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:113:            // until the DataStore's first emission — the composition is GATED on it (like the reflowable
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:2:// DataStore (the OpdsSourceStore / AiProviderStore JSON-in-Preferences precedent). Global, device-
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:8:import androidx.datastore.core.DataStore
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:32:    private val dataStore: DataStore<Preferences>,
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:208:                // the DataStore's first emission; the reader body is withheld until then (Gate-4 Medium:
android/app/src/main/kotlin/com/vreader/app/opds/OpdsSourceStore.kt:2:// username live in DataStore as a JSON list; the optional password is kept ONLY as a SecretCipher
android/app/src/main/kotlin/com/vreader/app/opds/OpdsSourceStore.kt:4:// WebDavServerStore DataStore+cipher pattern. `clientFor(source)` builds an origin-scoped #117
android/app/src/main/kotlin/com/vreader/app/opds/OpdsSourceStore.kt:8:import androidx.datastore.core.DataStore
android/app/src/main/kotlin/com/vreader/app/opds/OpdsSourceStore.kt:12:import com.vreader.app.backup.net.KeystoreSecretCipher
android/app/src/main/kotlin/com/vreader/app/opds/OpdsSourceStore.kt:13:import com.vreader.app.backup.net.SecretCipher
android/app/src/main/kotlin/com/vreader/app/opds/OpdsSourceStore.kt:21:/** A saved OPDS catalog. `encryptedPassword` is a [SecretCipher] token (blank when no auth). */
android/app/src/main/kotlin/com/vreader/app/opds/OpdsSourceStore.kt:33:    private val dataStore: DataStore<Preferences>,
android/app/src/main/kotlin/com/vreader/app/opds/OpdsSourceStore.kt:34:    private val cipher: SecretCipher = KeystoreSecretCipher(ALIAS),
android/app/src/main/kotlin/com/vreader/app/backup/net/WebDavServerStore.kt:2:// name / wifiOnly live in DataStore as a JSON list; the password is kept only as a SecretCipher
android/app/src/main/kotlin/com/vreader/app/backup/net/WebDavServerStore.kt:8:import androidx.datastore.core.DataStore
android/app/src/main/kotlin/com/vreader/app/backup/net/WebDavServerStore.kt:18:/** A saved server. `encryptedPassword` is a [SecretCipher] token, never plaintext. */
android/app/src/main/kotlin/com/vreader/app/backup/net/WebDavServerStore.kt:30:    private val dataStore: DataStore<Preferences>,
android/app/src/main/kotlin/com/vreader/app/backup/net/WebDavServerStore.kt:31:    private val cipher: SecretCipher,
android/app/src/main/kotlin/com/vreader/app/search/RecentSearchesStore.kt:2:// Stores an MRU list of recent query strings as JSON in a Preferences DataStore under
android/app/src/main/kotlin/com/vreader/app/search/RecentSearchesStore.kt:4:// OpdsSourceStore precedent). `record` is atomic (DataStore.edit) so concurrent records never lose an
android/app/src/main/kotlin/com/vreader/app/search/RecentSearchesStore.kt:12:import androidx.datastore.core.DataStore
android/app/src/main/kotlin/com/vreader/app/search/RecentSearchesStore.kt:21:    private val dataStore: DataStore<Preferences>,
android/app/src/main/kotlin/com/vreader/app/search/RecentSearchesStore.kt:28:     * Records [query] as the most-recent search. Atomic (DataStore.edit) so overlapping records keep a
android/app/src/main/kotlin/com/vreader/app/backup/net/SecretCipher.kt:2:// The store keeps a password only as a SecretCipher token (never plaintext); the production
android/app/src/main/kotlin/com/vreader/app/backup/net/SecretCipher.kt:19:interface SecretCipher {
android/app/src/main/kotlin/com/vreader/app/backup/net/SecretCipher.kt:29:class KeystoreSecretCipher(private val alias: String = DEFAULT_ALIAS) : SecretCipher {
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:64:    // feature #129 — reader display settings. A device-local DataStore (the OpdsSourceStore /
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:65:    // AiProviderStore precedent), global (not per-book), process-singleton so a settings change
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:68:    private val readerSettingsDataStore: androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences> by lazy {
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:69:        androidx.datastore.preferences.core.PreferenceDataStoreFactory.create {
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:74:        com.vreader.app.reader.settings.ReaderSettingsStore(readerSettingsDataStore)
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:110:    // device-local DataStore under noBackupFilesDir (the readerSettingsStore precedent — recents are
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:116:    private val recentSearchesDataStore: androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences> by lazy {
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:117:        androidx.datastore.preferences.core.PreferenceDataStoreFactory.create {
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:122:        com.vreader.app.search.RecentSearchesStore(recentSearchesDataStore)
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderFactory.kt:3:// AiProviderStore.snapshot(), decrypts via apiKey(profile), and calls this — so the client is built
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:2:// AiProviderStore for the list, owns the editor form state, runs Test Connection against the LIVE
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:20:class AiSettingsViewModel(
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:21:    private val store: AiProviderStore,
android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt:2:// ACTIVE provider from one AiProviderStore snapshot, streams a chat answer (accumulating deltas),
android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt:24:    private val store: AiProviderStore,
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:2:// selection. Profile metadata (name/kind/baseUrl/model/temperature/maxTokens) lives in DataStore
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:3:// as a JSON list; the API key is kept ONLY as a SecretCipher token (the #116 KeystoreSecretCipher).
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:4:// Reuses the #116 WebDavServerStore DataStore+SecretCipher credential pattern, adding an active-id
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:9:import androidx.datastore.core.DataStore
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:13:import com.vreader.app.backup.net.SecretCipher
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:20:/** A saved AI provider. `encryptedApiKey` is a [SecretCipher] token, never plaintext. */
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:41:class AiProviderStore(
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:42:    private val dataStore: DataStore<Preferences>,
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:43:    private val cipher: SecretCipher,
android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsSourcesViewModel.kt:4:// #118 AiSettingsViewModel test path), and saves/deletes. The password is never logged.
android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsSourcesViewModel.kt:50:    // closed form). Mirrors AiSettingsViewModel.testGen.

exec
/bin/zsh -lc "nl -ba dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md | sed -n '180,315p' && rg -n \"Dependencies|Depends|WI count|13 work|13 WI|Work items|WI-AIP|WI-4b\" dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md docs/features.md | head -100" in /Users/ll/workspace/vreader
 succeeded in 0ms:
   180	
   181	```
   182	enumeratedBlocks = navigator.evaluateJavascript(EpubBilingualJs.enumScript)   // [{id,text}] for current resource
   183	        │  (session token S captured before the call; re-checked after)
   184	        ▼
   185	count = enumeratedBlocks.size
   186	restore = prefetcher.cachedDirect(unit, expectedCount = count, targetLanguage)  // zero-provider cache restore
   187	        │
   188	        ├─ hit  → segments = restore
   189	        └─ miss → segments = prefetcher.prefetchDirect(unit, sourceSegments = enumeratedBlocks.texts, targetLanguage)
   190	        │  (token re-checked after each suspension; a stale token → discard, no commit, no error surfaced)
   191	        ▼
   192	if token S still current:  commit segments → BilingualRenderState[unit] / translationsByUnit[unit]  (single writer)
   193	        ▼
   194	EpubBilingualJs.injectScript per (blockId, translation)  via navigator.evaluateJavascript   // token-guarded
   195	```
   196	
   197	- The VM exposes `onEpubBlocksEnumerated(unit, blocks)` as the controller's entry into VM render state, but the **controller owns the enumerate→cachedDirect/prefetchDirect→guarded-commit sequence**; the VM never initiates an EPUB prefetch itself (its position-driven `prefetch` dispatches only `txtDocSegmentWindow`/`mdDocSegmentWindow` units). A stale session token at any commit point discards silently (no `errorUnit`).
   198	- WI-7b's connected test asserts: enable → inject; disable → clear; reflow/href-change/fragment-recreation/activity-recreation → re-apply from cache via `cachedDirect` (zero provider calls); count-divergence handled via `prefetchDirect`; and that the regular TXT/MD prefetch path is never invoked for an EPUB unit.
   199	
   200	### Cancellation + single-flight (round-3 Medium-2, BINDING)
   201	
   202	- **Dual-cancellation across the service/VM boundary:** both the service AND the VM handle **BOTH** native `CancellationException` **AND** the typed `ChapterTranslationError.Cancelled` **before** generic error mapping — matching iOS `ChapterTranslationService.swift:359–364` (which catches `is CancellationError` and `ChapterTranslationError.cancelled` separately, both re-throwing `cancelled`). A cancelled stale request MUST NOT surface as `errorUnit` (it is discarded).
   203	- **Per-unit single-flight job registry (VM):** a `prefetchTasks: MutableMap<TranslationUnitId, Job>` (iOS `prefetchTasks: [TranslationUnitID: Task]`, `BilingualReadingViewModel.swift:141`, cancelled/removed on disable/unit-change at :165). A NEW request for a unit **cancels-or-joins** the prior job (a stale prior is cancelled and awaited so it cannot run overlapping translations or Room writes), keyed by unit. Rapid retry/navigation cannot run overlapping translations for the same unit. `retryUnit(unit)` goes through the same registry. Tests: a mid-flight cancel discards (no `errorUnit`, no partial cache row); a rapid re-trigger for the same unit does not double-write.
   204	
   205	### Modified files
   206	
   207	- `data/VReaderDatabase.kt` — add `ChapterTranslationEntity` to `@Database entities`, bump `version` **8 → 9** (the live DB is v8, migrations `MIGRATION_1_2`..`MIGRATION_7_8`, `ALL_MIGRATIONS` ends at `MIGRATION_7_8` — verified VReaderDatabase.kt:29,224–228), add **`MIGRATION_8_9`** (CREATE TABLE `chapter_translations` + `bookKey` index + FK→`books.fingerprintKey` CASCADE, DDL exactly matching Room's generated schema), **append `MIGRATION_8_9` to `ALL_MIGRATIONS` after `MIGRATION_7_8`**, add `abstract fun chapterTranslationDao()`. Purely additive.
   208	- `reader/TxtReaderActivity.kt` — own a `BilingualViewModel`; collect state; render translations as **additive items after the anchor chunk in the existing `items(count = document.chunkCount, key = { it })` loop (TxtReaderActivity.kt:1043), source chunks byte-unchanged (H2)**; on position change call `vm.onPositionChanged(charOffsetUTF16)`. Strictly gated to `originalFormat ∈ {txt, md}`; disabled = body byte-unchanged (overlay-only). **Owned by #129 (VERIFIED, merged) — a straight edit, rule 48 one-writer-per-file satisfied.**
   209	- `reader/ReaderActivity.kt` (Readium EPUB) — WI-0-gated: attach `EpubBilingualController` to `navigator.evaluateJavascript`; re-apply on the identified production re-apply signal; clear on teardown BEFORE publication teardown. `navigator: EpubNavigatorFragment?` is the verified live field (ReaderActivity.kt:110).
   210	- `reader/chrome/ReaderChromeScaffold.kt` — extend `readerMoreRows(...)` (currently supplies only `MoreActionId.DETAILS` + `SHARE`, ReaderChromeScaffold.kt:255–258) to ALSO supply the **`MoreRow.Toggle(id = MoreActionId.BILINGUAL, on = enabled, onToggle = …)`** row (or `MoreRow.Disabled` "Configure AI provider first" when not configured — `MoreRow.Disabled` exists for exactly this, MoreRow.kt:65–72). Threaded via new nullable params so #132/#134-only callers stay valid (the scaffold's established nullable-default pattern). This is the WI-9 entry-wiring edit.
   211	- `VReaderApp.kt` / `AppContainer` — **provide `AiProviderStore` INTO `AppContainer` itself** (it is NOT provided today — verified, only a comment names it at VReaderApp.kt:66) using the #116 `KeystoreSecretCipher` + a DataStore under the same convention as `readerSettingsStore`, PLUS provide `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, an `AiSettingsViewModel` factory (for the Variant A sheet), and a `BilingualViewModel` factory. **Extracted into the shared DI WI (WI-4b).** No `feat:#136` dependency remains — #131 owns the `AiProviderStore`-into-`AppContainer` wiring.
   212	
   213	**NOT modified:** `reader/chrome/ReaderBottomChrome.kt` gets **no** bilingual/Translate slot — the design's entry is the More-menu toggle (#134) + the top-chrome pill (#132), NOT a bottom-chrome slot. `ReaderBottomChrome`'s existing `extraSlot` is untouched.
   214	
   215	### Files OUT of scope for v1
   216	
   217	- **`Azw3ReaderActivity.kt` / `reader/foliate/`** — foliate WebView interlinear IS feasible but deferred (bundle-patch JS + secure-bridge additions touch the security-sensitive #126 surface). Once WI-0 proves the EPUB JS pipeline, the foliate host reuses `EpubBilingualJs` with a bundle adapter.
   218	- **`PdfReaderActivity.kt`** — no reflowable text layer. Out (`pdfPageRange` Kind reserved only).
   219	- **Backup collect/restore of `PerBookSettingsOverride` bilingual fields** — contract fields exist; wiring is a small additive follow-up (§7). Device-local until then.
   220	- **Style control** — descoped v1 (user decision, §3). Keep provider/model/**granularity**, DROP the bilingual "Style" control.
   221	- **Sentence-granularity interlinear RENDER** — not depicted (H2); design-gated. v1 renders the depicted paragraph pattern; Sentence selection falls back to paragraph render (cache still granularity-keyed).
   222	- **The iOS #82 readiness sheet (feature-flag + consent gates)** — `reader-ai-readiness.md` is iOS-specific and implementation-deferred; Android has no flag/consent, so the Variant A provider-list sheet is the whole AI-config surface. Out.
   223	- **"Translate entire book…" batch, re-translate/style-swap picker, cost/token estimation, term-overrides** — iOS/`vreader-ai-android.jsx` extras not in the authoritative sheet. Out.
   224	- **Streaming translation progress** — the design's "38%" is chapter-level N-of-M chunk progress, not token streaming. v1 shows N-of-M.
   225	
   226	## 3. Prior art / project precedent / rejected alternatives
   227	
   228	### The render-host decision (settled v2, CONFIRMED round-2)
   229	
   230	**How iOS does interlinear:** iOS renders EPUB/AZW3 in a WKWebView it fully controls. `EPUBBilingualOrchestrator` injects JS that (1) enumerates leaf blocks posting `[{bid,text}]` to Swift, (2) after translation injects a translation node after each block. TXT/MD render in a text path where the renderer interleaves translation runs. The mechanism = **the app inserts translation nodes between source nodes** — which is exactly the Android additive-item contract (H2) for TXT/MD and the DOM-inject contract for EPUB.
   231	
   232	**Android EPUB feasibility (round-2 re-verified):** the transformed API JAR on the resolved Readium 3.3.0 AAR (build.gradle.kts:111) exposes public `evaluateJavascript`, `getCurrentLocator()`, `firstVisibleElementLocator(...)`, `submitPreferences(...)`; `ReaderActivity.navigator: EpubNavigatorFragment?` holds the concrete fragment (ReaderActivity.kt:110). EPUB interlinear via JS injection is feasible with the public API — **no Readium fork.** Not reopened.
   233	
   234	**WI-0 — Readium bilingual spike (gates WI-7b; round-2 M1):** a throwaway harness that, against a real EPUB on the emulator, must PROVE each go/no-go criterion: (a) enumeration deterministic + idempotent with stable node IDs (repeat apply = no duplicate nodes); (b) clear wins over every older inject (a late inject checks the session token and no-ops); (c) recreation restores from cache for every case (href away/back, same-href `submitPreferences` reflow, internal page-fragment recreation, activity recreation) via `cachedDirect(expectedCount)` (zero provider calls) with an identified PRODUCTION re-apply signal per case; (d) locator/visible-source preservation across injection (stated permissible pagination delta); (e) enumerated block count vs segmenter count measured — divergence → the direct-block path (`prefetchDirect`/`cachedDirect`, H2) is the recovery, proven end-to-end. **Race contract:** single actor/mutex OR monotonic navigator-session token; token/mutex check after every suspended JS/AI call; clear before publication teardown. **No deterministic re-apply signal for a recreation case (c) = explicit NO-GO** → EPUB drops to a tracked follow-up, box D ships **TXT/MD-only** with the honest reason (a specific spike finding), never the false "requires a fork."
   235	
   236	**Rejected alternatives:**
   237	1. **Readium interlinear via decorations only** — REJECTED (decorations style existing text; they cannot insert translation paragraphs).
   238	2. **Forking Readium** — REJECTED + unnecessary (public `evaluateJavascript` seam exists).
   239	3. **AZW3 foliate host first** — REJECTED for v1 (deferred; touches the security-sensitive #126 bridge).
   240	4. **Eager whole-book pre-translation** — REJECTED (cost/latency). Lazily prefetch current+next + cache.
   241	5. **One `BilingualInterlinearBody` per chunk (v2)** — REJECTED (round-2 H1): a chunk is not a segment.
   242	6. **A Compose body as the EPUB render surface (v2)** — REJECTED (round-2 M2): Compose cannot render inside Readium's WebView.
   243	7. **Splitting a chunk's source `Text` into per-segment `Text` nodes to interleave translations (v3)** — REJECTED (round-3 H2): breaks the live one-`TextLayoutResult` + one-selection-registration-per-chunk model. Replaced by additive `LazyColumn` items at chunk boundaries, source `Text` never split.
   244	8. **Deriving `aiConfigured` from `profiles.isEmpty()` (the iOS Variant A note's derivation)** — REJECTED for Android: `activeId` can be null with profiles present, and key usability needs the active profile's token to decrypt (H3). Android uses `BilingualAiReadiness.resolve` = active-profile + decrypts-non-empty.
   245	9. **Spinning AI-config reachability out as a separate feature #136** — REJECTED / CLOSED (2026-07-12): the design proved the ONLY designed Android AI-config reader surface is bilingual-coupled Variant A; there is no designed standalone entry, so it is not separable. #131 owns it.
   246	
   247	### The setup-sheet resolution (rule 51) + Style descope (round-2 H3, USER DECISION)
   248	
   249	There are **two committed, differently-shaped** `BilingualSetupSheet`s:
   250	- `vreader-bilingual.jsx` → **language grid + Granularity + preview strip + Translation-engine strip (Set up/Change) + Cancel/Translate**. No Style, no provider/model card, no term-overrides, no cost.
   251	- `vreader-ai-android.jsx` → **Languages (From/To) + Provider card + Style (Literal/Natural/Literary) + Keep-term-overrides toggle + cost footer**. No language grid, no Granularity, no preview.
   252	
   253	**Resolution:** this plan reproduces the **`vreader-bilingual.jsx` sheet EXACTLY**. **Style is DESCOPED for v1** (user decision): keep provider/model/**granularity**, DROP the bilingual "Style" control. Consequently store/VM carry no `style`, the chunk contract has no `style` param, and the cache key's `promptVersion` has no `s=` component.
   254	
   255	**Box-D parity note (do NOT claim full box-D parity):** the box-D checklist lists provider/model/**style**. Because Style is descoped, **WI-9 flips box D to done ONLY for provider/model/granularity + a descope note**; a follow-up tracker/checklist amendment records the Style descope. If Style is later wanted, that needs an updated committed design (a single sheet showing BOTH Style AND Granularity is not depicted anywhere — the one Style design gate below).
   256	
   257	### The AI-config path (rule 51) — Variant A is the committed design
   258	
   259	The canonical decision (`reader-ai-provider-entry.md`, Variant A) + its component canvas (`vreader-ai-provider-entry.jsx`) ARE the committed design; #131 reproduces only what they depict (a `‹ Bilingual`-titled push sheet hosting the #118 provider list + the canonical editor, pop-back-on-first-save). No AI-config sheet or nav is invented. The iOS #82 readiness additions (flag/consent) are explicitly **out** on Android (no such subsystems exist). This is a designed surface — it is NOT a design gate.
   260	
   261	### Other precedents applied
   262	
   263	- **#118 provider seam**: reuse `AiProviderStore.snapshot()` (`snapshot.active`) + `store.apiKey(profile)` + `AiProviderFactory.create` (default of an injected factory param) + `AiClient.chat`. #118's AI files are unchanged; #131 wires `AiProviderStore` into `AppContainer` and reuses `AiProviderListScreen`/`AiProviderEditSheet`/`AiSettingsViewModel` verbatim for the Variant A sheet.
   264	- **Room additive-migration pattern** (#122/#123/#127/#128/#135): version bump + `MIGRATION_n_(n+1)` appended to `ALL_MIGRATIONS` + exact-DDL + `VReaderDatabaseMigrationTest` PRAGMA guard. `@PrimaryKey` + `@Upsert` is the project DAO pattern (`BookDao`). Baseline v8.
   265	- **DataStore JSON-in-Preferences** for `PerBookBilingualStore` (the `ReaderSettingsStore`/`AiProviderStore` pattern).
   266	- **Pure-logic port**: iOS `ChapterSegmenter`/`ChapterTranslationChunker`/`TranslationChunkContract`/`ChapterTranslationService.translatePreSegmented`/`ChapterTranslationPrefetcher.translatedSegmentsDirect`+`cachedSegmentsDirect` are pure/heavily-unit-tested — direct Kotlin ports with the same test vectors (all verified to exist).
   267	- **Single-flight job registry**: iOS `prefetchTasks: [TranslationUnitID: Task]` (`BilingualReadingViewModel.swift:141`) — ported as `prefetchTasks: Map<TranslationUnitId, Job>` (M2).
   268	- **Entry point via #132/#134 (VERIFIED)**: the More-menu bilingual toggle (`MoreActionId.BILINGUAL` reserved; `MoreRow.Toggle`/`MoreRow.Disabled`) + top-chrome pill are landed; #131 mounts the pill + wires the toggle (§4).
   269	
   270	## 4. Work-item sequencing
   271	
   272	**13 WIs/PRs (round-3 Low-1 fix — corrected count):** the list is exactly **WI-0, WI-1, WI-2, WI-3, WI-4a, WI-4b, WI-5, WI-6, WI-7a, WI-7b, WI-AIP, WI-8, WI-9** = **13 WIs**. (v3 had 12: WI-0,1,2,3,4a,4b,5,6,7a,7b,8,9. Folding in the Variant A "AI Providers" sheet adds **WI-AIP**, making 13. The prior "11 WIs" claim in the plan header and `docs/features.md` was wrong on two counts and is corrected here.) Each WI = one PR. Build order: **foundation/cache → service/direct-block APIs → shared DI/factory (incl. `AiProviderStore` in `AppContainer`) → VM state/prefetch → host-specific renderers (TXT/MD + EPUB) + the Variant A AI Providers sheet → entry wiring.**
   273	
   274	**Dependencies (round-3 Medium-4 — dependency honesty; #136 folded in):**
   275	
   276	- **`Deps: [feat:#132, feat:#134]`.** **#132 (top chrome) and #134 (More menu) are VERIFIED.** **#129 (TXT/MD reader) is VERIFIED** — `TxtReaderActivity` is a straight edit, not a blocker. **There is NO external AI-reachability blocker** — the former #136 is CLOSED (GH #1976, not-planned) and its scope is #131-owned.
   277	- **WI-4b is foundational and gates the behavioral chain.** WI-4b now provides `AiProviderStore` into `AppContainer` PLUS the bilingual services + factories. Per the audit's Medium-4, WI-4b transitively gates WI-6 (needs the prefetcher/DI), WI-7b (needs DI), WI-AIP (needs `AiProviderStore` + `AiSettingsViewModel` from `AppContainer`), and WI-8 (needs DI). **Chosen resolution: injected seams so the behavioral work proceeds against fakes before WI-4b lands, AND WI-4b is sequenced early.** Concretely: the VM (WI-5/WI-6) takes an injected `ChapterTranslationPrefetcher` (fake in tests) and an injected `AiProviderSnapshot` provider (fake); the TXT/MD host Compose/unit work (WI-8) and the Variant A sheet (WI-AIP) take injected VM/store/`AiSettingsViewModel` seams — so unit/Compose tests do not wait on `AppContainer`. **WI-4b is built right after WI-4a (before WI-6/WI-7b/WI-AIP/WI-8) so the production wiring lands before the host integrations that mount it.** This is stated honestly: the *production run-through* of WI-6/WI-7b/WI-AIP/WI-8 depends on WI-4b; their *unit/Compose gates* depend only on the injected seams. No external feature gates any of this.
   278	
   279	**WI-0 (spike): Readium EPUB bilingual injection — go/no-go + race contract (M1).** Harness + criteria (a)–(e) and the race contract in §3. Output: a go/no-go on EPUB-in-v1 (no-go = box D ships TXT/MD-only, tracked) + the concrete `EpubChapterTextProvider` / `EpubBilingualJs` / `EpubBilingualController` surfaces + the EPUB direct-block ownership sequence (Medium-1). Deps: none (uses the existing #106 Readium host). Not TDD-gated (throwaway spike); feeds WI-7b.
   280	
   281	**WI-1 (foundational): value types + pure segmentation/chunk/contract.** `TranslationUnitId`, `TranslationGranularity`, `BilingualLanguages`, **`ChapterSegmenter` (with `paragraphRanges`/`sentenceRanges` returning half-open UTF-16 `(start, endExclusive)` spans — H1)**, `TranslationChunker`, `TranslationChunkContract` (no `style`), `ChapterTranslationError`. Pure; ported iOS vectors. Deps: none.
   282	
   283	**WI-2 (foundational): Room translation cache.** `ChapterTranslationEntity` (PK = `lookupKey`, `sourceParagraphCount` column) + `Dao` (`@Upsert`) + `ChapterTranslationStore`; `VReaderDatabase` **8→9 `MIGRATION_8_9`** appended after `MIGRATION_7_8`. Robolectric migration round-trip from v8 + full-chain + upsert/get/delete-by-lookupKey + FK-CASCADE + exact-DDL guard. Deps: none.
   284	
   285	**WI-3 (foundational): `ChapterTranslationService`** against a fake `AiClient`. Both `cachedTranslation` overloads (incl. the `expectedSegmentCount` divergence restore — H2) + `translate` + `translatePreSegmented`. **Dual-cancellation (native + typed `Cancelled`) BEFORE generic mapping (M2).** Deps: WI-1, WI-2. Tests: cache hit → zero client calls; miss → translate + write; decode fail → per-segment fallback; one-chunk fail → source-only that chunk (others translated, NOT cached); all-chunks fail → throw; native-cancel → `Cancelled` (no write); typed-`Cancelled`-from-chunk → `Cancelled` (no write); ensureActive-before-write; `AiError` mapping incl. `Config`/`InsecureUrl` → `ProviderFailed`; `translatePreSegmented` full-success caches under the enumerate count; partial degrade NOT cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` returns on stored-count match, null on mismatch, needs no provider.
   286	
   287	**WI-4a (foundational): `ChapterTextProvider` (TXT/MD) + `ChapterTranslationPrefetcher` + `BilingualAiReadiness`.** `TxtChapterTextProvider` builds the document-global segment `(start, endExclusive)` ranges once (H1), groups into windows, resolves `unitContaining(charOffsetUTF16)` via segment-start binary search, `sourceSegments(unit)`. Prefetcher: `prefetch` + `prefetchDirect` + `cachedDirect`; resolves active profile from `snapshot()`, decrypts snapshot-consistent, builds client via the injected factory param (default `AiProviderFactory::create`), constructs `AiRequest` with **`model = profile.model.ifBlank { profile.kind.defaultModel }` (M3)**. Readiness = active profile with non-empty decrypted key; **cipher failure → not-ready, never a crash.** Fake store + fake factory. Deps: WI-1, WI-3. Tests (all half-open-range-based): unit resolution + clamp + empty; **one-chunk document (no trailing newline) → its segment translation renders, not dropped (H1)**; **final-chunk anchor → renders (H1)**; **exact-boundary → correct anchor (H1)**; **EOF anchor (`segEndExclusive == text.length`) → last chunk, no clamp-collapse (H1)**; paragraph spanning MANY chunks → one segment/one unit, anchored to the last chunk (Low-2); multiple SENTENCES in one chunk → distinct sentence segments (Low-2); a >4000-char paragraph hard-split across chunks → one segment; CR/LF/CRLF; MD markers; locator→unit mapping; `unitAfter` end→null; **source-byte parity while disabled**; cache-hit-no-profile still returns (#306); no-profile miss → `ProviderFailed`; `prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls; **blank `profile.model` → `AiRequest.model == kind.defaultModel` (M3 regression)**; readiness true/false; empty-key → false; no-active-with-profiles-present → false (H3); cipher-throw → readiness false (no crash).
   288	
   289	**WI-4b (foundational — shared DI/factory, incl. `AiProviderStore` in `AppContainer`): AppContainer bilingual + AI-config graph.** `AppContainer` **now constructs `AiProviderStore`** (DataStore + #116 `KeystoreSecretCipher`, following the `readerSettingsStore` convention — this is #131's change, not an external feature's) and provides `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, an `AiSettingsViewModel` factory (for WI-AIP), and the `BilingualViewModel` factory. Deps: **WI-4a** (no external dep — #136 closed). Tests: container resolves the bilingual + AI-config graph; `AiProviderStore` resolves and round-trips a profile; the prefetcher's injected factory defaults to `AiProviderFactory::create`.
   290	
   291	**WI-5 (behavioral): `PerBookBilingualStore` + `BilingualViewModel` state core.** Store per book (enabled/targetLanguage/granularity — no style); VM setters (persist + first-enable `needsSetupSheet`); `aiConfigured` from `BilingualAiReadiness.resolve` over an injected snapshot; language/granularity change clears cache-shaped state + bumps generation. Injected prefetcher/snapshot seams (Medium-4). Turbine tests: first-enable raises sheet; re-enable persisted does not; disable clears; language change resets; granularity change resets + re-keys; `aiConfigured` true/false from readiness; round-trip through store; no style field. Deps: WI-1 (+ store).
   292	
   293	**WI-6 (behavioral): VM prefetch trigger + generation/cancellation + single-flight (M2).** `onPositionChanged(charOffsetUTF16)` derives current unit (TXT/MD only), dedupes, prefetches current+next; a monotonic position-request sequence checked after every suspension; **per-unit single-flight `prefetchTasks: Map<TranslationUnitId, Job>` (a new request cancels/joins the prior — M2)**; a captured language/granularity/provider snapshot per launch; generation bumps on disable/language/granularity/unit-change discard stale; **BOTH `CancellationException` AND typed `ChapterTranslationError.Cancelled` handled BEFORE generic error mapping (M2)**; a cancelled stale request does NOT surface as `errorUnit`; `Offline`→`unavailableUnits`; transient failure leaves unit unfetched + clears anchor to retry; `retryUnit` routes through the registry. The EPUB `onEpubBlocksEnumerated` entry is present but EPUB prefetch is owned by the controller (Medium-1); the VM's position-driven `prefetch` dispatches TXT/MD units only. Fake prefetcher (Medium-4 seam). Deps: WI-4a, WI-4b, WI-5. Tests: current+next on unit change; same-unit no-op; cancel-mid discards stale (no `errorUnit`); typed-`Cancelled` discards (not `errorUnit`); rapid re-trigger same unit → single-flight, no double-write; offline→unavailable; failure→retry-able; `retryUnit` re-fetches; granularity change cancels + re-fetches under the new key.
   294	
   295	**WI-7a (behavioral): Compose UI — setup sheet + interlinear body (TXT/MD) + pill.** Reproduce `vreader-bilingual.jsx` (setup sheet: language grid / granularity / preview / engine strip configured+unconfigured; body: the **additive translation items** per the H2 render contract — translated / loading N%+dimmed / error+Retry / offline source-only; pill). Consumes the host-neutral `BilingualRenderState` DTO. Light+dark. Compose UI tests each state, incl. **paragraph interlinear renders a translation item after a paragraph (depicted)** and **Sentence selection falls back to paragraph render (H2 gate)**. Deps: WI-5 (state shape). NO Style control; the unconfigured "Set up" CTA renders and (in WI-9) routes to the Variant A sheet.
   296	
   297	**WI-7b (behavioral, CONDITIONAL — only if WI-0 = go): EPUB render adapter (DOM injection, NOT Compose — M2) + direct-block ownership (M1).** `EpubBilingualJs` (enum/inject/clear JS builders, CSP-safe escaping) + `EpubBilingualController` (the serialization actor / session token AND the **single-owner enumerate→cachedDirect/prefetchDirect→guarded-commit sequence — Medium-1**) + `EpubChapterTextProvider`, wired into `ReaderActivity`, driving DOM from the shared `BilingualRenderState` DTO. Uses `prefetchDirect`/`cachedDirect` for the count-divergence path (H2). Depends on WI-6 (VM state) and WI-4b (DI); the WI-7a UI dependency is only the shared `BilingualRenderState`/value types. Connected test on a real EPUB (seeded cache): enable → injects; disable → cleared; reflow/href-change/fragment-recreation/activity-recreation → re-applies from cache (zero provider calls) via `cachedDirect`; count-divergence handled (direct path); **the regular TXT/MD prefetch path is never invoked for an EPUB unit (Medium-1)**. Unit tests: JS escaping/CSP-safe insertion, RTL/CJK style, empty translations, loading cleanup, idempotent replacement, source-only fallback, stale-session-token commit discarded (no `errorUnit`). Deps: WI-0, WI-3, WI-4a, WI-4b, WI-6, (shared types from WI-7a). (If WI-0 = no-go, dropped; box D ships TXT/MD-only, tracked.)
   298	
   299	**WI-AIP (behavioral — the folded-in Variant A AI Providers sheet): `ReaderAiProvidersSheet`.** The scoped in-reader "AI Providers" push sheet (nav bar `‹ Bilingual` + "AI Providers" title) reproducing `vreader-ai-provider-entry.jsx` `AIProvidersSheet`/`NavSheet`, hosting ONLY the #118 `AiProviderListScreen` (empty + populated) + the canonical `AiProviderEditSheet`, driven by the #118 `AiSettingsViewModel` (from WI-4b's `AppContainer` factory). Empty state carries the bilingual-context copy ("Bilingual mode needs a provider to translate" / "Add provider" CTA). On first Save → the provider becomes the bilingual engine (`store.setActive(savedId)`) + pop the whole stack back to the bilingual sheet (engine strip now "configured / Change…"). `‹ Bilingual` without adding → unconfigured, no state mutated. No consent/flag surface (Android has none). Deps: WI-4b (for `AiProviderStore` + `AiSettingsViewModel` in `AppContainer`), WI-7a (bilingual sheet host). Tests (Compose + connected): empty → Add → Save → pop-to-bilingual with strip configured; `‹ Bilingual` without adding → strip unconfigured, snapshot unchanged; "Change…" → populated list, current provider checked, tap row → `setActive`; editor reused verbatim (no divergent form).
   300	
   301	**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into the `items(count = document.chunkCount)` loop as **additive translation items after the anchor chunk, source chunks byte-unchanged (H2)** + position-change (`charOffsetUTF16`) + setup-sheet. `originalFormat`-gated (TXT/MD). Uses WI-4b's DI. **#129 VERIFIED — straight edit.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2)**; **highlights/annotation-washes/read-aloud-wash still key off source chunks (H2)**; a translation item is non-selectable, does not perturb source offsets (H2); disable → source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders exactly one translation after its last chunk (H1/Low-2)**; **one-chunk/final-chunk anchors render (H1)**; MD source mapping. Deps: WI-6, WI-7a, WI-4b.
   302	
   303	**WI-9 (behavioral): entry wiring + acceptance.** Mount `BilingualPill` in #132's VERIFIED top chrome; extend `readerMoreRows(...)` to supply the #134 VERIFIED More-menu `MoreActionId.BILINGUAL` toggle (`MoreRow.Toggle` `on`/`onToggle`, or `MoreRow.Disabled` "Configure AI provider first" when not configured) wired to the VM; **wire the setup sheet's "Set up"/"Change…" affordance → the #131-owned `ReaderAiProvidersSheet` (Variant A)**. Full acceptance across EPUB (if WI-7b landed) + TXT/MD, including the fresh-user path `unconfigured → Set up (→ Variant A AI Providers sheet) → add provider → return → enable → translate` (now #131-owned end-to-end). **Flip box D to done ONLY for provider/model/granularity + the Style-descope note; file the follow-up checklist amendment; do NOT claim full box-D parity.** The DONE flip **no longer waits on #136** (closed). Update `docs/architecture.md` (bilingual pipeline + the new `chapter_translations` schema + `AiProviderStore` + bilingual services in `AppContainer` + the Variant A AI Providers sheet). → DONE. Deps: WI-8, WI-AIP, WI-7b (if go), feat:#132, feat:#134.
   304	
   305	## 5. Test catalogue
   306	
   307	JVM/Robolectric (`android/app/src/test/...bilingual/`): `ChapterSegmenterTest` (paragraph blank-line; sentence CJK `。！？` vs Latin; empty→[]; single; **`paragraphRanges`/`sentenceRanges` return correct half-open UTF-16 `(start, endExclusive)` spans**); `TranslationChunkerTest` (packs to budget; oversize→own chunk+subSplit; empty→[]); `TranslationChunkContractTest` (prompt shape; strict JSON decode; code-fence strip; count mismatch→`CountMismatch`; non-array→`NotAStringArray`); `ChapterTranslationServiceTest` (cache hit 0 calls; miss→translate→write; decode-fail per-segment fallback; one-chunk-fail partial-not-cached; all-fail→throw; **native-cancel→Cancelled no write; typed-`Cancelled`→Cancelled no write (M2)**; ensureActive-before-write; offline/timeout/429/http/config/insecure→error mapping; very long chapter N-of-M; stale-cache count-mismatch re-translates; `translatePreSegmented` caches under enumerate count on full success; partial degrade not cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` hit/miss with no provider); `ChapterTranslationErrorMappingTest`; `TxtChapterTextProviderTest` (**one-chunk document → renders (H1); final-chunk anchor → renders (H1); exact-boundary → correct anchor (H1); EOF anchor → last chunk, no clamp-collapse (H1)**; paragraph spanning MANY chunks → one segment/unit anchored to last chunk (Low-2); multiple SENTENCES in one chunk → distinct segments (Low-2); >4000-char paragraph → one segment across hard-split chunks; CR/LF/CRLF; MD markers; locator→unit mapping; `unitAfter` end→null; source-byte parity while disabled); `ChapterTranslationPrefetcherTest` (snapshot-consistent profile+key; injected-factory used; `AiRequest` built from profile; **blank `profile.model` → `kind.defaultModel` (M3 regression)**; cache-hit-no-profile #306; no-profile miss→ProviderFailed; `prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls; CJK↔English + Latin round-trip via fake; cipher-throw→ProviderFailed not crash); `BilingualAiReadinessTest` (active+key→true; **no-active-with-profiles-present→false (H3); activeId-null→false (H3)**; empty key→false; cipher-throw→false, no crash); `PerBookBilingualStoreTest` (enabled/lang/granularity round-trip; no style field); `BilingualViewModelTest` (Turbine: first-enable sheet; re-enable no-sheet; disable clears; language reset; granularity reset + re-key; `aiConfigured` from readiness; prefetch current+next; same-unit no-op; **cancel-mid discards (no errorUnit); typed-Cancelled discards (M2); rapid re-trigger same unit single-flight, no double-write (M2)**; offline→unavailable; error→errorUnit+retry; `retryUnit`); `EpubBilingualJsTest` (JS escaping / CSP-safe insertion; RTL/CJK style; empty translations; clear idempotent; inject idempotent replacement; source-only fallback — WI-7b if go); `EpubBilingualControllerTest` (**enumerate→cachedDirect/prefetchDirect→guarded commit; stale-session-token commit discarded, no errorUnit; single-owner (regular TXT/MD prefetch never runs for EPUB unit) — Medium-1** — WI-7b if go).
   308	
   309	Room migration: `VReaderDatabaseMigrationTest` (extend) **v8→v9 + full-chain from v8** + FK-CASCADE + `lookupKey`-as-PK; `ChapterTranslationDaoTest` (upsert-by-PK replaces; get/delete-by-lookupKey).
   310	
   311	Compose UI (`androidTest/...bilingual/`): `BilingualSetupSheetUiTest` (language grid, granularity, preview, engine configured vs unconfigured driven by `aiConfigured`; no Style control present; light+dark); `BilingualInterlinearBodyUiTest` (**additive translation item after a paragraph anchor chunk (depicted); paragraph interlinear translated incl. CJK font + RTL Arabic; Sentence selection → paragraph-render fallback (H2 gate)**; loading N%+dimmed; error+Retry; offline source-only; empty translation→source-only no crash); `ReaderAiProvidersSheetUiTest` (**empty state with bilingual-context copy + Add CTA; populated list + current-provider checked; `‹ Bilingual` back label; editor reused (WI-AIP)**); `BilingualPillUiTest`.
   312	
   313	Connected (`androidTest/...reader/`): `TxtReaderBilingualConnectedTest` (API 35, fake `AiClient` via injected factory): enable→setup→confirm→interlinear from seeded Room cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2); highlights/annotation-washes/read-aloud-wash still key off source chunks (H2); translation item non-selectable + no source-offset perturbation (H2)**; disable→source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders one translation (H1/Low-2); one-chunk/final-chunk anchors render (H1)**; TXT/MD gated (PDF inert); very long chapter scroll responsive; cancellation leaves no partial cache row. `ReaderAiProvidersConnectedTest` (WI-AIP + WI-9): `unconfigured → Set up → Variant A sheet → add provider → Save → pop-to-bilingual configured → enable → translate`; `‹ Bilingual` without adding → unconfigured, snapshot unchanged; "Change…" → populated, current checked. `EpubReaderBilingualConnectedTest` (only if WI-0=go): enable→inject on a real EPUB; disable→clear; href-change/fragment-recreation/activity-recreation→re-apply from cache (zero provider calls); count-divergence handled via `prefetchDirect`/`cachedDirect`; regular prefetch never runs for EPUB unit (Medium-1).
   314	
   315	Edge cases: empty translation, failed, partial per-chunk, CJK↔English + Latin + RTL, provider error/timeout/429/config/insecure, native + typed cancellation mid-translation + before-write, single-flight overlap, very long chapters, offline (cache-first + silent source-only), cipher-decrypt failure → not-ready (no crash), enumerate↔segment count divergence (direct path), one-chunk/final-chunk/EOF anchors (H1), blank model (M3).
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:23:- **AI-config path (folded in — #136 CLOSED)** — the ONLY designed Android AI-config reader surface is the **Variant A scoped "AI Providers" sheet pushed inside the bilingual flow**, reached from the bilingual engine strip's "Set up"/"Change…" button (`reader-ai-provider-entry.md`). #131 now owns it end-to-end (§"AI-config reachability", WI-4b + WI-AIP + WI-9).
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:211:- `VReaderApp.kt` / `AppContainer` — **provide `AiProviderStore` INTO `AppContainer` itself** (it is NOT provided today — verified, only a comment names it at VReaderApp.kt:66) using the #116 `KeystoreSecretCipher` + a DataStore under the same convention as `readerSettingsStore`, PLUS provide `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, an `AiSettingsViewModel` factory (for the Variant A sheet), and a `BilingualViewModel` factory. **Extracted into the shared DI WI (WI-4b).** No `feat:#136` dependency remains — #131 owns the `AiProviderStore`-into-`AppContainer` wiring.
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:272:**13 WIs/PRs (round-3 Low-1 fix — corrected count):** the list is exactly **WI-0, WI-1, WI-2, WI-3, WI-4a, WI-4b, WI-5, WI-6, WI-7a, WI-7b, WI-AIP, WI-8, WI-9** = **13 WIs**. (v3 had 12: WI-0,1,2,3,4a,4b,5,6,7a,7b,8,9. Folding in the Variant A "AI Providers" sheet adds **WI-AIP**, making 13. The prior "11 WIs" claim in the plan header and `docs/features.md` was wrong on two counts and is corrected here.) Each WI = one PR. Build order: **foundation/cache → service/direct-block APIs → shared DI/factory (incl. `AiProviderStore` in `AppContainer`) → VM state/prefetch → host-specific renderers (TXT/MD + EPUB) + the Variant A AI Providers sheet → entry wiring.**
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:274:**Dependencies (round-3 Medium-4 — dependency honesty; #136 folded in):**
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:277:- **WI-4b is foundational and gates the behavioral chain.** WI-4b now provides `AiProviderStore` into `AppContainer` PLUS the bilingual services + factories. Per the audit's Medium-4, WI-4b transitively gates WI-6 (needs the prefetcher/DI), WI-7b (needs DI), WI-AIP (needs `AiProviderStore` + `AiSettingsViewModel` from `AppContainer`), and WI-8 (needs DI). **Chosen resolution: injected seams so the behavioral work proceeds against fakes before WI-4b lands, AND WI-4b is sequenced early.** Concretely: the VM (WI-5/WI-6) takes an injected `ChapterTranslationPrefetcher` (fake in tests) and an injected `AiProviderSnapshot` provider (fake); the TXT/MD host Compose/unit work (WI-8) and the Variant A sheet (WI-AIP) take injected VM/store/`AiSettingsViewModel` seams — so unit/Compose tests do not wait on `AppContainer`. **WI-4b is built right after WI-4a (before WI-6/WI-7b/WI-AIP/WI-8) so the production wiring lands before the host integrations that mount it.** This is stated honestly: the *production run-through* of WI-6/WI-7b/WI-AIP/WI-8 depends on WI-4b; their *unit/Compose gates* depend only on the injected seams. No external feature gates any of this.
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:289:**WI-4b (foundational — shared DI/factory, incl. `AiProviderStore` in `AppContainer`): AppContainer bilingual + AI-config graph.** `AppContainer` **now constructs `AiProviderStore`** (DataStore + #116 `KeystoreSecretCipher`, following the `readerSettingsStore` convention — this is #131's change, not an external feature's) and provides `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, an `AiSettingsViewModel` factory (for WI-AIP), and the `BilingualViewModel` factory. Deps: **WI-4a** (no external dep — #136 closed). Tests: container resolves the bilingual + AI-config graph; `AiProviderStore` resolves and round-trips a profile; the prefetcher's injected factory defaults to `AiProviderFactory::create`.
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:293:**WI-6 (behavioral): VM prefetch trigger + generation/cancellation + single-flight (M2).** `onPositionChanged(charOffsetUTF16)` derives current unit (TXT/MD only), dedupes, prefetches current+next; a monotonic position-request sequence checked after every suspension; **per-unit single-flight `prefetchTasks: Map<TranslationUnitId, Job>` (a new request cancels/joins the prior — M2)**; a captured language/granularity/provider snapshot per launch; generation bumps on disable/language/granularity/unit-change discard stale; **BOTH `CancellationException` AND typed `ChapterTranslationError.Cancelled` handled BEFORE generic error mapping (M2)**; a cancelled stale request does NOT surface as `errorUnit`; `Offline`→`unavailableUnits`; transient failure leaves unit unfetched + clears anchor to retry; `retryUnit` routes through the registry. The EPUB `onEpubBlocksEnumerated` entry is present but EPUB prefetch is owned by the controller (Medium-1); the VM's position-driven `prefetch` dispatches TXT/MD units only. Fake prefetcher (Medium-4 seam). Deps: WI-4a, WI-4b, WI-5. Tests: current+next on unit change; same-unit no-op; cancel-mid discards stale (no `errorUnit`); typed-`Cancelled` discards (not `errorUnit`); rapid re-trigger same unit → single-flight, no double-write; offline→unavailable; failure→retry-able; `retryUnit` re-fetches; granularity change cancels + re-fetches under the new key.
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:297:**WI-7b (behavioral, CONDITIONAL — only if WI-0 = go): EPUB render adapter (DOM injection, NOT Compose — M2) + direct-block ownership (M1).** `EpubBilingualJs` (enum/inject/clear JS builders, CSP-safe escaping) + `EpubBilingualController` (the serialization actor / session token AND the **single-owner enumerate→cachedDirect/prefetchDirect→guarded-commit sequence — Medium-1**) + `EpubChapterTextProvider`, wired into `ReaderActivity`, driving DOM from the shared `BilingualRenderState` DTO. Uses `prefetchDirect`/`cachedDirect` for the count-divergence path (H2). Depends on WI-6 (VM state) and WI-4b (DI); the WI-7a UI dependency is only the shared `BilingualRenderState`/value types. Connected test on a real EPUB (seeded cache): enable → injects; disable → cleared; reflow/href-change/fragment-recreation/activity-recreation → re-applies from cache (zero provider calls) via `cachedDirect`; count-divergence handled (direct path); **the regular TXT/MD prefetch path is never invoked for an EPUB unit (Medium-1)**. Unit tests: JS escaping/CSP-safe insertion, RTL/CJK style, empty translations, loading cleanup, idempotent replacement, source-only fallback, stale-session-token commit discarded (no `errorUnit`). Deps: WI-0, WI-3, WI-4a, WI-4b, WI-6, (shared types from WI-7a). (If WI-0 = no-go, dropped; box D ships TXT/MD-only, tracked.)
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:299:**WI-AIP (behavioral — the folded-in Variant A AI Providers sheet): `ReaderAiProvidersSheet`.** The scoped in-reader "AI Providers" push sheet (nav bar `‹ Bilingual` + "AI Providers" title) reproducing `vreader-ai-provider-entry.jsx` `AIProvidersSheet`/`NavSheet`, hosting ONLY the #118 `AiProviderListScreen` (empty + populated) + the canonical `AiProviderEditSheet`, driven by the #118 `AiSettingsViewModel` (from WI-4b's `AppContainer` factory). Empty state carries the bilingual-context copy ("Bilingual mode needs a provider to translate" / "Add provider" CTA). On first Save → the provider becomes the bilingual engine (`store.setActive(savedId)`) + pop the whole stack back to the bilingual sheet (engine strip now "configured / Change…"). `‹ Bilingual` without adding → unconfigured, no state mutated. No consent/flag surface (Android has none). Deps: WI-4b (for `AiProviderStore` + `AiSettingsViewModel` in `AppContainer`), WI-7a (bilingual sheet host). Tests (Compose + connected): empty → Add → Save → pop-to-bilingual with strip configured; `‹ Bilingual` without adding → strip unconfigured, snapshot unchanged; "Change…" → populated list, current provider checked, tap row → `setActive`; editor reused verbatim (no divergent form).
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:301:**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into the `items(count = document.chunkCount)` loop as **additive translation items after the anchor chunk, source chunks byte-unchanged (H2)** + position-change (`charOffsetUTF16`) + setup-sheet. `originalFormat`-gated (TXT/MD). Uses WI-4b's DI. **#129 VERIFIED — straight edit.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2)**; **highlights/annotation-washes/read-aloud-wash still key off source chunks (H2)**; a translation item is non-selectable, does not perturb source offsets (H2); disable → source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders exactly one translation after its last chunk (H1/Low-2)**; **one-chunk/final-chunk anchors render (H1)**; MD source mapping. Deps: WI-6, WI-7a, WI-4b.
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:303:**WI-9 (behavioral): entry wiring + acceptance.** Mount `BilingualPill` in #132's VERIFIED top chrome; extend `readerMoreRows(...)` to supply the #134 VERIFIED More-menu `MoreActionId.BILINGUAL` toggle (`MoreRow.Toggle` `on`/`onToggle`, or `MoreRow.Disabled` "Configure AI provider first" when not configured) wired to the VM; **wire the setup sheet's "Set up"/"Change…" affordance → the #131-owned `ReaderAiProvidersSheet` (Variant A)**. Full acceptance across EPUB (if WI-7b landed) + TXT/MD, including the fresh-user path `unconfigured → Set up (→ Variant A AI Providers sheet) → add provider → return → enable → translate` (now #131-owned end-to-end). **Flip box D to done ONLY for provider/model/granularity + the Style-descope note; file the follow-up checklist amendment; do NOT claim full box-D parity.** The DONE flip **no longer waits on #136** (closed). Update `docs/architecture.md` (bilingual pipeline + the new `chapter_translations` schema + `AiProviderStore` + bilingual services in `AppContainer` + the Variant A AI Providers sheet). → DONE. Deps: WI-8, WI-AIP, WI-7b (if go), feat:#132, feat:#134.
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:311:Compose UI (`androidTest/...bilingual/`): `BilingualSetupSheetUiTest` (language grid, granularity, preview, engine configured vs unconfigured driven by `aiConfigured`; no Style control present; light+dark); `BilingualInterlinearBodyUiTest` (**additive translation item after a paragraph anchor chunk (depicted); paragraph interlinear translated incl. CJK font + RTL Arabic; Sentence selection → paragraph-render fallback (H2 gate)**; loading N%+dimmed; error+Retry; offline source-only; empty translation→source-only no crash); `ReaderAiProvidersSheetUiTest` (**empty state with bilingual-context copy + Add CTA; populated list + current-provider checked; `‹ Bilingual` back label; editor reused (WI-AIP)**); `BilingualPillUiTest`.
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:313:Connected (`androidTest/...reader/`): `TxtReaderBilingualConnectedTest` (API 35, fake `AiClient` via injected factory): enable→setup→confirm→interlinear from seeded Room cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2); highlights/annotation-washes/read-aloud-wash still key off source chunks (H2); translation item non-selectable + no source-offset perturbation (H2)**; disable→source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders one translation (H1/Low-2); one-chunk/final-chunk anchors render (H1)**; TXT/MD gated (PDF inert); very long chapter scroll responsive; cancellation leaves no partial cache row. `ReaderAiProvidersConnectedTest` (WI-AIP + WI-9): `unconfigured → Set up → Variant A sheet → add provider → Save → pop-to-bilingual configured → enable → translate`; `‹ Bilingual` without adding → unconfigured, snapshot unchanged; "Change…" → populated, current checked. `EpubReaderBilingualConnectedTest` (only if WI-0=go): enable→inject on a real EPUB; disable→clear; href-change/fragment-recreation/activity-recreation→re-apply from cache (zero provider calls); count-divergence handled via `prefetchDirect`/`cachedDirect`; regular prefetch never runs for EPUB unit (Medium-1).
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:319:- **Live-translation verification is AI-credential-gated (the box-D caveat).** The whole pipeline is verified without live creds via a deterministic **fake `AiClient`** injected through the prefetcher's `clientFactory` param (default `AiProviderFactory::create`; tests override). WI-3/4a/8 prove segment→chunk→decode→cache→interleave end-to-end incl. every error/edge path. Connected tests seed the Room cache and assert render-from-cache with zero client calls. An optional live smoke confirms wire format but is NOT a gate. The fresh-user `unconfigured → Set up → add provider` reachability leg is now #131-owned (WI-AIP + WI-9) and verified by `ReaderAiProvidersConnectedTest`.
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:332:- **Dependency honesty (round-3 Medium-4).** WI-4b (DI, incl. `AiProviderStore` in `AppContainer`) is foundational and gates the production run-through of WI-6/WI-7b/WI-AIP/WI-8; those WIs' unit/Compose gates proceed against injected fakes, and WI-4b is sequenced before them. No external feature gates the chain (#136 closed).
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:348:*(REMOVED: the v3 "#136 dependency" design-gate line — #136 is closed and the Variant A AI Providers sheet IS the committed design, reproduced by WI-AIP, not a gate.)*
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:356:  - **AI-config FOLDED IN (#136 CLOSED, GH #1976 not-planned; user decision 2026-07-12):** the design proved the ONLY designed Android AI-config reader surface is the bilingual-coupled **Variant A** "AI Providers" sheet (`reader-ai-provider-entry.md`); it is not separable, so #131 now owns it end-to-end. Added **WI-AIP** (`ReaderAiProvidersSheet`, reusing #118 `AiProviderListScreen`/`AiProviderEditSheet`/`AiSettingsViewModel` verbatim, `‹ Bilingual` push, pop-back-on-first-Save); WI-4b now provides `AiProviderStore` into `AppContainer` (verified not provided today — VReaderApp.kt:66 comment only) plus the bilingual services + `AiSettingsViewModel` factory; removed `feat:#136` from Deps (now `[feat:#132, feat:#134]`, no external AI-reachability blocker); the DONE flip no longer waits on #136; `aiConfigured` derivation kept as the correct active-profile+decrypts-non-empty gate (H3), NOT `profiles.isEmpty()` (the iOS note's derivation), with no consent/flag gate (Android has none).
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:362:  - **M4 (round-3 Medium-4) dependency honesty:** WI-4b (DI incl. `AiProviderStore`) is foundational and gates the production run-through of WI-6/WI-7b/WI-AIP/WI-8; those WIs' unit/Compose gates use injected fakes; WI-4b sequenced before them; no external feature gates the chain.
dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:363:  - **Low fixes:** WI count corrected to **13** (added WI-AIP; the "11 WIs" claim was wrong — Low-1); chunk semantics corrected — a chunk is ONE LINE, holds multiple SENTENCES, a paragraph spans MANY chunks; removed the "a chunk can hold multiple paragraphs" claim (Low-2). Awaiting Gate-2 round-4 audit.
docs/features.md:100:| 45 | Verification harness sweep — retire the "Needs device verification" backlog    | DevTools/*   | High     | VERIFIED | XCUITest + DebugBridge recipes for 13 of 15 simulator-automatable backlog items. Adds VERIFIED status. Depends on #44. Plan: `dev-docs/plans/20260513-feature-45-verification-harness-sweep.md` (v3, 2026-05-15). **All WIs shipped** — WI-1 PR #581 v3.21.3; WI-2 PR #586; WI-3 PR #587; WI-4 PR #589; WI-4b PR #590; WI-4c-a PR #591; WI-4c-c PR #599; WI-4d commit `de5a73d`; WI-4e PR #643; WI-5 PR #679 v3.21.64; **WI-6 (named test-plan selector) PR #692 v3.21.69 commit `3753d2a`** — ships `TestPlans/Verification.xctestplan` (25 per-method identifiers across 13 classes) + `TestPlans/All.xctestplan` (no-flag default). Invocation: `xcodebuild test -scheme vreader -testPlan Verification`. **Recovery arc** — Bug #192 (PR #688) renamed `verify_*` → `test_verify_*` after WI-6 Gate 2 audit discovered the 25 methods were XCTest-invisible (vacuous `Executed 0 tests` passes had silently no-opped the harness across all 13 classes). Bug #193 (PR #691) fixed the Feature #36 OPDS XCUITest element-class mismatch surfaced by the post-rename re-run. WI-6's Gate 5 transport-success dispatch confirmed exactly 25 tests run end-to-end (10 passed, 13 XCTSkip-gated, 2 product failures filed as new bugs post-merge for Feature28/29). **2026-05-16 update (verify-cron progressive sampling)**: Feature #23 + Feature #31 confirmed clean in `dev-docs/verification/feature-45-20260516-sampling.md` (full plan run); Feature #31 re-confirmed in this iteration (2/2 PASS solo, 35s). **Feature #37 root-cause identified**: harness gap (XCUITest doesn't swipe-up to bring `perBookSection` into accessibility tree; production feature is fine per `feature-37-20260509.md`). Filed as **Bug #204 / GH #746** (DevTools/* Low). Net status: **7 of 13 classes still unsampled clean** (#11 EPUB load timing, #21 multi-page EPUB fixture, #28/#29 fixture-env-var gaps with 1-of-2 methods clean, #37 awaiting #204 harness fix, #40/#41 TTS control bar timing). VERIFIED status depends on Gate 5 final acceptance evidence file once those unsampled classes are sampled clean. **2026-05-16 round-2 sampling** (`dev-docs/verification/feature-45-20260516-round2.md`, result=partial) at v3.24.6 commit `a6103e5`: identical shape to round-1 (12 PASS, 13 SKIPPED, 0 FAILED in 410s). No regressions across the 40+ commits between v3.22.20 and v3.24.6. Same 7 classes remain gated by harness/fixture/env reasons. No new bugs filed. **2026-05-18 round-3 sampling** (`dev-docs/verification/feature-45-20260518-round3.md`, result=partial) at v3.27.23 commit `6936ccf`: 27 tests, 12 PASS / 15 SKIP / 0 FAIL — GREEN, no regressions across the feature #60 re-skin + Bug #209 repair + Bug #210/#214 changes landed since round-2. Progress: **Feature37 (2 methods) now PASS** (Bug #204 swipe-helper fix landed — previously gated); new `Feature11EPUBBottomChromeVerificationTests` (Bug #214, 2 tests) PASS. 9 method-groups still SKIP (Feature11Highlight, 21, 28-conversion, 29-backup-executes, 31, 35, 36-live, 40, 41 — fixture/harness/env gaps). No new bugs filed. **2026-05-18 round-4 sampling** (`dev-docs/verification/feature-45-20260518-round4.md`, result=partial) at v3.27.25 commit `8cab12a`: 27 tests, 12 PASS / 15 SKIP / 0 FAIL — GREEN, identical shape to round-3, zero regressions across the v3.27.23→v3.27.25 range (Bug #213/#216/#217 — GH #830/#838/#839 — test-infra fixes landed since round-3). Same 9 method-groups SKIP — unchanged fixture/harness/env gaps; no new bugs filed. **2026-05-18 round-5 sampling** (`dev-docs/verification/feature-45-20260518-round5.md`, result=partial) at v3.27.27 commit `9705693`: 27 tests, 12 PASS / 15 SKIP / 0 FAIL — GREEN, byte-identical shape to round-4, zero regressions across the v3.27.25→v3.27.27 range (Bug #219 / GH #846 — Feature11 EPUB-highlight XCUITest seed + readiness probe; Bug #182 / GH #847 — EPUB cross-chapter search highlight). Positive finding: Bug #219 converted `Feature11EPUBHighlightVerificationTests`'s reader-load gates from `XCTSkip` to hard `XCTAssert`; round-5 is the first full-plan run of that — both methods clear the hard gates and skip *deeper* at the WKWebView long-press step (`Feature11EPUBHighlightVerificationTests.swift:147/237`, Bug #220 / GH #845) rather than at the old seed gate. Skip count unchanged (still 9 method-groups). No new bugs filed. **2026-05-19 round-6 sampling** (`dev-docs/verification/feature-45-20260519-round6.md`, result=partial) at v3.34.15 commit `f47e1c5`: true shape **27 tests, 12 PASS / 15 SKIP / 0 FAIL — GREEN, byte-identical to round-5, zero regressions** across the ~7-version delta since round-5 (features #54/#55/#57/#63/#65/#68/#69 + Bug #225/#226 TTSService `rate` `didSet` recursion fix + test-infra fixes). The contended plan run on the shared simulator pool false-failed 6 classes (#28/#29/#34/#36/#40/#41 — testmanagerd wedged 427s on #28, #221-class flaky-parallel-pool cascade); a step-4 isolation re-run of all 6 on a dedicated idle simulator returned `** TEST SUCCEEDED **` (12 tests, 7 skipped, 0 failures), confirming the 6 plan-run failures were contention noise, not regressions. Same 9 method-groups SKIP — unchanged fixture/env/harness gaps; no new bugs filed. **2026-06-08 round-7 → VERIFIED** (`dev-docs/verification/feature-45-20260608.md`, `result: pass`, v3.59.23 `b6c74591`): the feature's purpose — retiring the device-verification backlog — is achieved: all 14 downstream target features (#11/#21/#23/#26/#27/#28/#29/#31/#34/#36/#37/#40/#41/#55) are independently VERIFIED with their own evidence files (the backlog is empty). Fresh harness run on current main (`Feature28` + `Feature31`) → `** TEST SUCCEEDED **`, 0 product failures, skips = env-gated/accepted-scope. Representative-subset run (no `timeout` watchdog binary available for a full unattended UITest run); substantive acceptance established by the downstream features' own VERIFIED evidence. Row → VERIFIED. GH: #576 |
docs/features.md:102:| 47 | WebDAV restore — selective book picker + lazy-on-tap downloads                 | Backup/*     | Medium   | VERIFIED  | Phase 2 of feature #46. `BookFileState` (`local / remoteOnly / downloading / failed / missingRemote`), library rows with cloud icons, "Pick…" entry on each backup row → `SelectiveRestorePicker` against the manifest, on-tap blob fetch via background URLSession with `taskDescription` identity, Wi-Fi-only cellular policy via `NWPathMonitor`, "Clean unused remote files" GC carved out as feature #51. Depends on feature #46. **Shipped 2026-05-04** in v3.11.18..v3.12.0 (21 PRs). **VERIFIED 2026-05-04** in v3.12.9 after fixing 5 blocking bugs (#112, #113, #114, #115, #116) found during initial Gate-5 run. Evidence: `dev-docs/verification/feature-47-20260504.md` (initial partial) + `dev-docs/verification/feature-47-20260504b.md` (post-fix pass) + per-bug evidence files. GH: #407 (closed — VERIFIED). |
docs/features.md:105:| 67 | Settings profile-header card + Stats entry point | App/* | Low | VERIFIED | **VERIFIED 2026-05-26 (Gate-5b, verify cron)** — CU-free XCUITest acceptance pass on iPhone 17 Pro Sim (iOS 26.4) at v3.39.17 build 638 (HEAD `14fe3861`). New suite `vreaderUITests/Verification/Feature67SettingsProfileCardVerificationTests.swift` (3 tests, 0 failures, 41.6s): (1) profile card present — "Your library" header + "… read this month" subline + `settingsProfileStatsButton` pill; (2) Stats pill → feature #58 `ReadingDashboardView` (cross-feature hand-off, #58 VERIFIED); (3) WI-6 AI-group Variant-A collapse — master `aiToggle` always present, `aiProvidersNavLink` + `consentToggle` appear only when AI on, collapse when off. Pixel-level design fidelity carried from Gate-5a screenshots (`feature-67-wi6-*-20260521.png`) + composition/snapshot unit tests. No bug discovered, no product code changed (verification scope). Evidence `dev-docs/verification/feature-67-20260526.md` (`result: pass`). **DONE 2026-05-21 (WI-6 — final WI) — feature complete, awaiting Gate-5b acceptance.** Now that `needs-design` #1068 is resolved (design `vreader-ai-toggles.jsx` + `ai-toggles-artboards.jsx` landed commit `3735529a`, Variant A recommended), WI-6 restyled the two deferred AI toggle rows to the design's colored-tile `SettingsToggleRow` + `PillSwitch`: **Enable AI Assistant** (oxblood `#8c2f2f` sparkle tile, master gate, always visible) and **Allow AI data sharing** (cool-blue `#4a6a8a` `checkmark.shield` tile, consent), merged with the AI Provider row into the design's single "AI" group (provider + consent hidden when AI off). New `PillSwitch` (a `ToggleStyle` over a real `Toggle` for native switch a11y) + `SettingsToggleRow` (peer of `SettingsIconRow`) + `SettingsRowPalette.aiAssistant`/`.aiDataSharing`. The `aiToggle`/`consentToggle`/`aiProvidersNavLink` identifiers + `AIProviderListView` destination preserved (identifier now lands on the actionable `Toggle`, not the row container). Gate-4 Codex audit: 2 rounds, **ship-as-is** (thread `019e4a37`); round-1 found 1 High (a11y identifier on container) + 1 Medium (button vs toggle semantics) + 1 Low (detail spacing), all resolved. Full suite green (7042 tests). Gate-5a slice-verified CU-free on iPhone 17 Pro Sim iOS 26.4 at v3.39.0 via the sim-drive-fallback tap path: AI-ON shows all 3 colored rows incl. the green/gray PillSwitches; toggling AI OFF collapses to the single master row (provider+consent hidden) — `dev-docs/verification/artifacts/feature-67-wi6-{02-ai-on-allrows,03-ai-off-collapsed}-20260521.png`. PR (this) v3.39.0 (minor — final WI completes the feature). This was the last remaining scope → row `IN PROGRESS` → `DONE`. Gate-5b end-to-end acceptance pass (`feature-67-<date>.md` evidence) pending before `VERIFIED`. Plan WI-6 addendum in `dev-docs/plans/20260519-feature-67-settings-profile-card.md`. **WI-5 (2026-05-20)** — `needs-design` #1068 filed for the AI Assistant + Data & Privacy toggle rows. The plan's WI-5 ("definitively restyles `AISettingsSection`") assumed all 3 AI rows would get colored-icon row chrome; Gate-3 audit of `vreader-panels.jsx:868-870` revealed the (then-)committed design depicted only the AI Provider row (`Icons.Sparkle` `#8c2f2f`). Per rule 51, WI-5's PR narrowed scope to restyle the AI Provider row only and added `SettingsRowPalette.aiProvider`; the two toggle rows stayed on plain-`Toggle` chrome pending design — **now unblocked + shipped in WI-6 (#1068 resolved)**. **WI-4 DONE 2026-05-20** — PR #1067 v3.38.15 commit `92cddd2`. Mounts `SettingsProfileCard` as the first `Form` row, restyles Cloud & Sync / Reading / About rows to `SettingsIconRow`, wires the Stats pill through `Notification.Name.openReadingStatsRequested` to a `SettingsStatsPresenter` that presents `ReadingDashboardView` (feature #58's surface shipped in PR #1061). Gate-4 audit: 2 rounds, ship-as-is (Codex `019e457e`); 1 High (stale-VM-on-reopen) + 1 Medium (state-machine test gap) resolved by extracting `SettingsStatsPresenter` (`@MainActor @Observable`) + 7 presenter state-machine tests. Gate-5a slice verified on iPhone 17 Pro Sim iOS 26.4 (5 PNG artifacts in `dev-docs/verification/artifacts/feature-67-wi-4-*.png`). **WI-1 DONE 2026-05-20** — reading-window persistence reads + `MonthBoundary` + `ReadingTimeFormatter.formatCompactHours` (foundational, no UI): PR #1014, 47 tests green, Codex-audited clean (thread `019e4146`). WI-2 (`SettingsRowPalette` + `SettingsIconRow`) PR #1016. WI-3 (`SettingsHeaderViewModel` + `SettingsProfileCard`) PR #1018. **WI-4 + WI-5 are HARD-BLOCKED on feature #58's dashboard-presenter WI (#58 WI-6) reaching `DONE` on `main`** — #58 WI-6 is itself blocked on product decisions D1–D4 (GH #665); per `.claude/rules/48-parallel-execution.md` hard rule 2, WI-4 (the WI that makes the Stats button user-visible) does not enter Gate 3 on an unmet hard dependency. **Depends: #58 (dashboard presenter, #58 WI-6).** **Gate 1+2 complete — plan dev-docs/plans/20260519-feature-67-settings-profile-card.md, Codex-audited clean.** **Design delivered 2026-05-18 — issue-canvas handoff resolves needs-design #862** — Gate-1 triage (2026-05-18): the design's profile-header card shows a user **name** + avatar initial, but the app has no user-account / no user-name source (only OPDS / WebDAV credentials); and the **Stats** button's destination is feature #58's reading dashboard — unbuilt and undesigned. The profile-card identity model + the reading-stats surface need a design decision → `needs-design` #862. The grouped-row restyle (30pt colored-icon rows) IS designed and unaffected. **Filed 2026-05-17** — surfaced by a component-by-component re-skin audit of the design bundle vs shipped state. **Problem**: `SettingsView.swift` re-skinned to v2 chrome with the four design groups, but omits the design's top **profile-header card** (avatar disc, name, "N books · Nh read this month") and the **Stats** button that opens the reading-stats dashboard; grouped rows are native `Form` `NavigationLink`s, not the design's 30pt colored-icon rows. **Design source**: `vreader-panels.jsx` — `SettingsSheet` / `Row`. **Cross-ref**: the Stats button is the entry point to feature #58 (reading-time dashboard, TODO). **Lineage**: v2 follow-on of feature #60 (VERIFIED). GH: #825 |
docs/features.md:116:| 60 | VReader visual identity v2 — Source Serif 4 / Inter typography, 5-theme palette (Paper / Sepia / Dark / OLED / Photo), oxblood accent, redesigned reader chrome + sheets (Library / Reader / AI / TOC / Highlights / Reader Settings), new SelectionPopover for new-selection-from-long-press flow (4 colors + Note / Translate / Ask AI / Read), generative typographic covers — per `claude.ai/design` handoff bundle | App/*, Library/*, Reader/*, Theme/* | Medium | VERIFIED | **VERIFIED 2026-05-16 (v3.27.0)** — all 12 WIs merged (WI-1..WI-11 incl. WI-6a/6b/6c + WI-7a..7c5, WI-12). needs-design #760 resolved. Gate 5b full-acceptance pass: result=pass — all 7 acceptance criteria (a-g) exercised end-to-end on iPhone 17 Pro Simulator (build 414). Evidence: `dev-docs/verification/feature-60-20260516.md`. WI-12 (#795) renders the Photo theme background image inside the EPUB WKWebView via a base64 data URL. WI-7a (SelectionPopoverView + action-row contract) shipped in PR #762 as a no-UI-regression slice — view built per design, 8 contract tests pin action order/accent/identifiers. WI-7b (foundational `SelectionPopoverActionRouter` — pure-logic dispatch enum mapping `SelectionPopoverAction` → existing `.readerHighlightRequested` / `.readerAnnotationRequested` / `.readerTranslateRequested` notifications; `userInfo["color"]` carries `NamedHighlightColor.rawValue` additively; `.askAI` / `.read` return `.deferredNotYetWired`) shipping in this iteration — 10 router tests pin enum-case-exhaustive contract, Codex Gate 4 thread `019e2e83` 1 round ship-as-is. WI-7c1 (foundational `SelectionPopoverPresenter` — `.readerSelectionPopoverRequested` notification + typed `SelectionPopoverRequest.post/parse` helpers + SwiftUI `SelectionPopoverPresenterModifier` that presents `SelectionPopoverView` as a sheet; routes taps via `SelectionPopoverActionRouter` + `SelectionPopoverDismissPolicy` keeps the sheet open on `.deferredNotYetWired` results so `.askAI`/`.read` taps don't silently swallow) shipping in this iteration — 10 contract tests pin notification wire format + dismiss policy; `TextSelectionInfo` gained additive `Equatable + Sendable` conformance; Codex Gate 4 thread `019e2ea9` 2 rounds ship-as-is. WI-7c2..7c5 (behavioral, per-bridge swap of `TXTBridgeShared.buildReaderEditMenu` → `SelectionPopoverRequest.post` + attach presenter to the container) are the remaining slices for SelectionPopover. **Progress**: WI-1 (typography registry Swift API) shipped in PR #750; WI-2 (theme tokens, `ReaderThemeV2`) shipped in PR #749; WI-3 (foundational popover types) shipped in PR #745; WI-4 (EPUB theme injection) shipped in PR #753 — EPUB renders now route through `ReaderThemeV2.epubOverrideCSS` via the legacy → V2 projection (`ReaderTheme.asV2`); WI-5 (TXT + MD theme injection) shipped in PR #754 — TXT body bg/ink + MD body ink + MD blockquote sub + MD code-block paper now route through V2. **Slice verify 2026-05-16** (`dev-docs/verification/feature-60-20260516-wi5slice.md`, `result: partial`) closes acceptance criterion (c) for 3 of 5 reachable themes (paper/sepia/dark) on TXT end-to-end via DebugBridge theme switches — OLED + Photo deferred because they're not reachable from the legacy 3-case `ReaderSettingsStore.theme` enum until a later WI migrates the settings type. Remaining WIs 6-10 cover reader chrome, SelectionPopover, library re-skin (cards/rows then container), final sheet re-skin + status-bar tinting + generative covers. **Plan**: `dev-docs/plans/20260515-feature-60-visual-identity-v2.md` (v5, Codex Gate-2 audit clean inline per rule 47; v4 introduces the WI-6a/6b split + needs-design #760; v5 introduces the WI-7a/7b split — WI-7a ships the SelectionPopoverView + action-row contract as a no-regression slice, WI-7b replaces the legacy UIMenu). 10 WIs sequenced from foundational (typography, theme tokens, popover types) → behavioral (EPUB theme injection, TXT/MD theme + typography, reader chrome, SelectionPopover, library cards/rows, library container, sheet re-skins + covers + status bar). Per row Cross-refs: #53/#55 presenters re-skinned post-#60 in separate PRs (not consumed). **Origin**: bundle handed off 2026-05-15 from `claude.ai/design` (share token `tSClWWD84corsOcW52YmNw`). Full prototype committed under `dev-docs/designs/vreader-fidelity-v1/` — README, chat-1 intent log, 9 JSX/HTML source files, 31 PNG screenshots. **Problem**: VReader's current chrome is a mix of SwiftUI system defaults (Library), a TextKit-driven UITextView (TXT/MD), a WKWebView + CSS-injected theme (EPUB), Foliate-js with its own CSS (AZW3/MOBI), and PDFKit (PDF). Each surface drifted its own typography, accent, and theme story; the user wants a single coherent reader identity. The design ("Refined-literary meets native iOS") specifies a unified visual layer over all of these without changing behavior. **Scope (purely visual + UX; no behavioral change to readers, persistence, search, WebDAV, or AI)**: (1) **Typography** — bundle Source Serif 4 (body, default reader font) + Inter (UI chrome). Add a serif↔sans toggle in Reader Settings. Replace ad-hoc font selection across `TXTViewConfig`, EPUB CSS injection, Foliate `setStyles`, and PDFKit. (2) **5-theme palette** — extend `ThemeColor`/`ReaderTheme` to Paper / Sepia / Dark / OLED / Photo. Photo theme uses a user-chosen background image with translucent paper layer (per `vreader-themes.jsx:image`). Tokens: `bg`, `paper`, `ink`, `sub`, `rule`, `accent`, `chrome` + `isDark` flag for status-bar tinting. Replace current theme palette; migrate existing per-book setting. (3) **Oxblood accent** — `#8c2f2f` (light) / `#d6885a` (warm-dark) / `#e8b465` (photo) — single restrained hue across buttons, indicators, selection. (4) **Library redesign** — continue-reading rail + 3-column cover grid, filter chips, search bar, grid↔list toggle. Aligns with #6 view preferences (no behavior change). (5) **Reader chrome** — new top bar (back / title / bookmark / more) + bottom bar (TOC / Display / Highlights / AI) + page indicator + scrubber. Edges-tap-flip / middle-tap-toggle-chrome convention (resolves bug #165 as a side effect; aligns with feature #25 tap zones). (6) **SelectionPopover** — REPLACES the current `HighlightableTextView` 4-item UIMenu (Highlight / Add Note / Define / ▶) for the **new-selection-from-long-press** flow. 4 named highlight colors (yellow / pink / green / blue) + Note / Translate / Ask AI / Read actions. **Cross-ref**: This is distinct from feature #53 (tap-on-existing-highlight Edit/Delete) and feature #55 (tap-on-annotated-text note preview) — those are separate hit-test flows the design does NOT cover. (7) **Sheets** — re-skin TOC, Highlights, AI (Summarize / Chat / Translate tabs), Reader Settings (Brightness + theme picker + Size / Line-spacing / Margin sliders + font toggle), App Settings. (8) **Generative typographic covers** — fallback cover style (classic / modern / editorial / animal / minimal) when no real cover image is available. Coexists with feature #43 cover extraction (decision-policy in plan: real-cover-if-available, generative-fallback). (9) **Status bar tinting** — flips light/dark based on `theme.isDark`. **Out of scope for v1**: PDF chrome (stays on PDFKit defaults until extended), AZW3/MOBI chrome (Foliate-js shell; extension TBD), search results panel, WebDAV / restore picker UI (#52 in flight), AI provider editor (#50 / #185 surface), reading-time dashboard (#58 has no design — needs design extension before implementing), hierarchical TOC tree (#38), bilingual inline mode (#56 — design's Translate is point-in-time only). **Edge cases**: (a) Photo theme image storage / picker / clearing; (b) backward-compat: per-book `epubTheme` value `.warmDark` etc. need migration to the new 5-theme set; (c) cover-policy collision with #43 — choose order at runtime; (d) accent against highlight colors — ensure contrast on each theme; (e) dynamic-island top inset preserved across the new chrome (bug #179 territory); (f) PDF/AZW3 fall-through: if user picks a theme the underlying renderer can't honour, render closest approximation. **Acceptance criteria**: (a) Library matches design's grid + rail on iPhone 17 Pro Sim; (b) Reader (EPUB + TXT + MD) matches design's chrome + page layout pixel-close (within typography metric drift); (c) All 5 themes render correctly including Photo; (d) Long-press text in any reader format produces the new SelectionPopover with 4 colors + 4 actions; (e) AI sheet Summarize/Chat/Translate tabs match design; (f) Source Serif 4 ↔ Inter toggle works in reader; (g) Existing features (highlight persistence, search, AI, backup) unaffected — no regressions in feature #3 / #4 / #11 / #17 / #29 / #44 / #50 verification sets. **Dependencies**: blocks none; informs #53 (presenter could be re-skinned post-#60), #55 (same), #58 (needs design extension first). **Risks**: (a) typography metric drift between Source Serif 4 and current Georgia/system serif breaks scroll-position restore math (bug #179 family) — mitigate with offset re-projection on font change; (b) Photo theme image storage policy + WebDAV backup question (does the image travel?); (c) AZW3/MOBI fall-through — Foliate-js's own typography won't match Source Serif 4 unless we ship a font into the Foliate bundle; (d) re-skinning #53 + #55 presenters post-#60 = double-implementation cost vs gating those features behind #60. **Implementation gating**: per rule 47 follows /feature-workflow Gates 1-6 (Plan → Independent plan audit → TDD → Implementation audit → Device verification → Merge). Likely 8-15 WIs depending on Gate-1 split. Per rule 48 most WIs must serialize (one writer per file per area). Cron-friendly mechanical WIs: font asset bundling, theme-token extension, accent-color sweep. Human-loop WIs: Library redesign, Reader chrome, SelectionPopover swap. **Out-of-design surface decisions** (locked at triage time, plan can adjust): PDF/AZW3/MOBI reader chrome stays on current rendering for v1; #58 reading-time dashboard waits for design extension; #56 bilingual inline waits for design extension; #38 TOC tree waits for design extension; #43 generative covers folds into this feature. Reported by user 2026-05-15. GH: #718 |
docs/features.md:117:| 59 | Register vreader as a system document handler — appear in iOS "Open in" / Share Sheet for `.epub`, `.azw3` (+ `.mobi`/`.prc`/`.azw`), `.md` (+ `.markdown`), `.txt`, `.pdf` and import the tapped file into the library | App/*, Library/* | Medium | VERIFIED | **VERIFIED 2026-05-16 round-3** (`dev-docs/verification/feature-59-20260516-round3.md`, `result: pass`) on iPhone 17 Pro Sim v3.22.23 (commit `cdefc5a5`). All 6/6 criteria PASS — Bug #197 / GH #708 fix (`75fc5409`, v3.22.22) unblocked criterion (b): `simctl openurl booted "file://...epub"` → new book appears in library within ~1s, no cold restart needed (`dev-docs/verification/artifacts/feature-59-verified-library-postfix-20260516.png`). **Round-2 device-verify 2026-05-16** (`dev-docs/verification/feature-59-20260516.md`, `result: partial`). 5/6 criteria PASS, only (b) still BLOCKED by Bug #197 (library not auto-refreshing post-import — still NEW). Round-2 confirmed: (a) Share Sheet shows vreader for PDF — Files-app → tap PDF → Quick Look → Share → Preview/vreader/More listed ✅; (c) `.mobi`/`.prc`/`.azw` dispatch correctly via simctl openurl (FileURLImportRouter logs + DB rows confirm import), `.pdf` dispatches via Share Sheet → tap vreader → DB row appears (lands on prior view due to Bug #197, but the import-to-DB path works) ✅; (e) Files-app context menu wording is "Open With" NOT "Copy to vreader" → `LSSupportsOpeningDocumentsInPlace: true` honored ✅; (f) "Open With" expanded list shows Preview labeled "Default" and vreader as alternative → `LSHandlerRank: Alternate` honored ✅. Combined with round-1 (`feature-59-20260515.md`): all 7 of 8 supported extensions verified to dispatch (only `.markdown` is broken at the Apple system-UTI level, not a vreader bug). Cannot flip to VERIFIED until Bug #197 lands a fix and criterion (b) reverifies. Plan: `dev-docs/plans/20260515-feature-59-share-sheet-open-in-vreader.md` (v1, Gate 2 round-1 audit clean via Codex `019e2a9e`). **2 WIs both shipped** — WI-1 (Info.plist metadata: CFBundleDocumentTypes + UTImportedTypeDeclarations + LSSupportsOpeningDocumentsInPlace) in PR #698 v3.21.73 commit `ba92440`. WI-2 (FileURLImportRouter + production .onOpenURL handler in both Debug & Release Scene branches + `BookFormat.isSupportedExtension`) in this PR. Test suite: 6 InfoPlist regression guards + 6 BookFormat extension cases + 9 router dispatch cases (including 10 supported-extension parameterized + 6 unsupported-extension parameterized). All pass. **Problem**: When the user taps a book file in another app (Files, Mail, Safari downloads, AirDrop receive, third-party file managers) iOS shows an "Open in…" / Share Sheet listing the apps that have declared support for that document type. vreader is not in the list because `Info.plist` declares no `CFBundleDocumentTypes` and no `UTImportedTypeDeclarations`. The app also has no production `.onOpenURL`/scene-delegate handler for `file://` URLs — the existing handler in `VReaderApp.swift:309` is wrapped in `#if DEBUG` and only matches `DebugCommand.scheme` (the `vreader-debug://` URL surface). All five formats (EPUB / PDF / TXT / MD / AZW3-MOBI-PRC-AZW) are otherwise fully supported — `BookImporter` already routes them through format-specific metadata extractors (`AZW3MetadataExtractor` for `.azw3/.azw/.mobi/.prc`, EPUB/PDF/TXT/MD extractors elsewhere) and the reader views all consume `URL` inputs via `open(url:)` ViewModels. So this is purely the missing system-level registration + import dispatch — not a new format-handling capability. **Scope**: (1) **Document-type declarations in `project.yml` Info.plist properties** — add `CFBundleDocumentTypes` array with one entry per supported family, each with `CFBundleTypeName` + `LSHandlerRank: Alternate` (so vreader appears alongside other readers without claiming primacy) + `LSItemContentTypes` listing the relevant UTIs. Standard UTIs: `org.idpf.epub-container` (EPUB), `com.adobe.pdf` (PDF), `public.plain-text` (TXT), `net.daringfireball.markdown` (MD — Apple-recognized public conformance). Custom UTIs declared in `UTImportedTypeDeclarations`: `com.amazon.azw3` / `com.amazon.mobi-pocket` / `com.amazon.kindle` covering the AZW3/MOBI/PRC/AZW extensions (Apple does not provide a system UTI for these). Each imported type spec: `UTTypeIdentifier`, `UTTypeConformsTo: [public.data]`, `UTTypeDescription`, `UTTypeTagSpecification` ({public.filename-extension: [...], public.mime-type: [...]}). (2) **`LSSupportsOpeningDocumentsInPlace: true`** — required so the Files app and document-pickers can hand the URL to vreader without copying the file first; pairs with `UIFileSharingEnabled` if the user wants their library exposed (separate scope decision). (3) **Production `.onOpenURL` handler** in `VReaderApp.swift` (outside the `#if DEBUG` block) that dispatches `file://` URLs to a new `BookImportRouter` (or extension on the existing `BookImporter`) which: securely scopes-the-resource (`url.startAccessingSecurityScopedResource()`), detects format via `BookFormat.from(fileExtension:)`, calls the existing `BookImporter.importBook(at:)` path, releases the scope, and navigates to the new library row (or directly opens the book — UX decision in plan). (4) **Edge cases**: (a) unknown extension reaching the handler (because UTI conformance can be looser than our extension list) — fall back to user-visible alert; (b) file URL points to iCloud / OneDrive lazy file not yet downloaded — surface a "downloading…" state before import; (c) huge AZW3 files imported under memory pressure — same risk surface as existing AZW3 import (covered by `BookImporter`); (d) duplicate import — `fingerprintKey` dedupe already handles this; the handler should still navigate to the existing row, not silently no-op; (e) MD file mistyped as plain text by source app — UTI dispatch picks the highest-conforming registered type; (f) iOS 17+ App Intents / Quick Actions integration is OUT of scope for this row. **Acceptance criteria**: (a) on iOS Share Sheet for an `.epub` file in Files / Mail / Safari, "vreader" appears in the destinations list; (b) tapping the destination launches vreader, imports the file, and lands on either the library or the freshly-opened reader (decide in plan); (c) same flow for `.azw3`, `.mobi`, `.prc`, `.azw`, `.md`, `.markdown`, `.txt`, `.pdf`; (d) duplicate handling: same file shared twice does not create a duplicate library row; (e) Files-app context menu shows "Open in vreader" without a copy step; (f) `LSHandlerRank: Alternate` confirmed by NOT becoming the default handler on a clean device. **Dependencies**: none (all format-handling already implemented). **Risks**: (a) UTI conformance for `.azw3`/`.mobi` is non-standard — Apple doesn't ship a public UTI for these, so we must declare them; if a competing reader app declared a slightly different conforming UTI tree, both apps might show or one might be hidden — confirm against Apple Books, Kindle, Marvin, KyBook on a real device during verification; (b) `LSSupportsOpeningDocumentsInPlace` interactions with the existing book-files-directory model in `BookImporter` — make sure scope-released URLs aren't re-read after `stopAccessingSecurityScopedResource`; (c) `UTImportedTypeDeclarations` declarations could conflict with already-installed system Markdown editors — test on a device with Bear / iA Writer / Drafts installed to confirm we appear in the sheet without breaking their defaults. Reported by user 2026-05-14. GH: #667 |
docs/features.md:118:| 58 | Reading-time + activity dashboard — time-window aggregation (today / week / month / 3mo / 6mo / year / all-time), per-book breakdown with notes and highlights counts, sortable, included in WebDAV backup | Library/*, Stats/* | Medium | VERIFIED | **VERIFIED 2026-05-22 (verify-cron Gate-5b round 2)** — all 6 acceptance criteria PASS on merged `main` `1973b002` (v3.39.8). Round-2 unblocked by Bug #263 / GH #1138 (`vreader-debug://seed-sessions`): seeded a deterministic 6-session spread on-device, confirmed the live per-window ladder today=600<7d=1200<30d=1800<90d=2400<180d=3000<all=3600 + `ReadingStats`=3600s/6, and drove the SAME `ReadingStatsAggregator` over the SAME seeded data via the seam test (criterion b); `sortIsAppliedToPerBookTable` reorders rows + `StatsPerBookTable` exposes all 5 sortable columns + per-book notes/highlights projection (criterion c); VM UserDefaults sort round-trip across construction (criterion d); criterion a reachability carried from round-1 artifact; criteria e/f re-confirmed green by `BackupReadingHistoryTests`. Dashboard's *visual* surface is not CU-free reachable (no `present?sheet=stats` / `vreader-debug://stats`; CU down) so b/c/d verified at the data/behavioral substance layer per the verify-skill authorized path — 333 tests / 0 failures across 9 suites. Evidence: `dev-docs/verification/feature-58-20260522-round2.md` (`result: pass`). GH #665 closed. Round 1 (`feature-58-20260522.md`, `result: partial`) verified a + e/f; b/c/d were blocked on session-seeding (Bug #263, now FIXED). **DONE 2026-05-22 (feature-cron Gate-6)** — all WIs merged on `main` (WI-1–5 PRs #982/#994/#995/#999/#1001; WI-6a/6b/6c) and all 6 acceptance criteria have shipping code: `ReadingDashboardView`+`ReadingDashboardViewModel` (a), `ReadingStatsAggregator` 7-window (b), `StatsPerBookTable` 5-col sort (c) + persisted sort (d), `BackupReadingHistory` reading-history.json (e/f). Dashboard reachable via Feature #67's Stats button (now DONE). Implementation complete; awaiting Gate-5b VERIFIED (verify cron — exercise the acceptance criteria end-to-end incl. a WebDAV backup→wipe→restore round-trip). **D1–D4 RESOLVED 2026-05-20 — A/B/B/A.** D1=A: entry point amended to **"from Settings → profile card → Stats"** (accepts feature #67 dependency — #67 WI-4 owns the SettingsView Stats button, itself hard-blocked on this feature's WI-6 reaching `DONE`, the standard mutual-dependency knot — WI-6a ships a DEBUG-only `vreader-debug://stats` entry for Gate-5 verification while the user-facing hook waits on #67). D2=B: accept the design literally (`Year` calendar-YTD + `Custom` range picker) — **Custom range picker deferred to GH #1058** (filed `needs-design`). D3=B: ship 5 sort fields including `last-read` — **`last-read` column deferred to GH #1059** (filed `needs-design`). D4=A: hero + 7-pill bar (design). **Deferred per D2-B / D3-B: Custom range picker (GH #1058) + last-read sort column (GH #1059); WI-6a's first cut ships 6 windows (Today / 7d / 30d / 90d / Year / All — Custom dropped) + 4 sort fields (title / time / highlights / notes — last-read dropped).** WI-6 split into WI-6a (A-portion: dashboard view + 6-pill bar + 4-col table + DEBUG-only `vreader-debug://stats` entry, ships now), WI-6b (D2-B Custom range picker + Year calendar-YTD bucket swap, blocked on #1058 — **UNBLOCKED 2026-05-20 by PR #1060 Stats Followups design landing**; **WI-6b SHIPPED 2026-05-20** — Custom pill on `StatsTimeWindowBar` + new `StatsCustomRangePicker` sheet (month grid + quick-preset rail + start/end date chips + summary footer) + new `ReadingStatsCustomRange` value type + aggregator widened with optional `customRange` arg (additive; nil = WI-6a behaviour) + VM tracks/persists the applied range across launches; 100 WI-6a/6b tests green), WI-6c (D3-B `last-read` column, blocked on #1059 — **UNBLOCKED 2026-05-20 by PR #1060**; **WI-6c SHIPPED 2026-05-20** as PR #1063 — `.lastRead` case added to `ReadingDashboardSortField` + comparator (nil sinks to bottom regardless of direction); `StatsPerBookTable` gained a 5th `Read` header-tap-driven column (Alt-1 always-5-columns design variant); nil cells render as "—", non-nil reuse `ReadingTimeFormatter.formatRelativeLastRead`). **WI-1–5 MERGED to main 2026-05-19 (WI-1 ReadingStatsModels PR #982; WI-2 ReadingStatsAggregator PR #994; WI-3 ReadingTimeFormatter.formatDuration PR #995; WI-4 ReadingDashboardViewModel PR #999; WI-5 WebDAV reading-history backup section PR #1001 — each Codex-audited ship-as-is, 79 WI-1–5 tests green on main).** **Gate 1+2 complete — plan dev-docs/plans/20260519-feature-58-reading-dashboard.md, Codex-audited clean.** **Design delivered 2026-05-18 — issue-canvas handoff resolves needs-design #862** — triage 2026-05-18: the `ReadingDashboardView` UI (7 time-window cards + sortable per-book table) has no committed design; `needs-design` #862 covers it (bundled with feature #67's profile card — same reading-stats design family). The non-UI parts (the `ReadingStatsAggregator` service + the WebDAV backup-payload extension) are not design-gated and can be planned independently once the dashboard design lands. **Problem**: Per-session reading-time data is already collected (`ReadingSession` SwiftData model: `startedAt`, `endedAt`, `durationSeconds`, `bookFingerprintKey`) and per-book lifetime totals exist (`ReadingStats` model: `totalReadingSeconds`, `sessionCount`, `lastReadAt`), but there is no surface that exposes this data to the user. No view, no time-window aggregation, no per-book breakdown panel, no sorting beyond `LibrarySortOrder.totalReadingTime`. Notes (`AnnotationNote`) and highlights (`Highlight`) counts per book are queryable but never aggregated into a stats surface. WebDAV backup (`BackupDataCollector`) currently omits both `ReadingSession` and `ReadingStats` (CloudKit-only via `SyncReadingSessionRecord` / `VRReadingSession`), so stats are lost on restore-to-fresh-device. **Scope**: (1) **Time-window aggregator** — new `ReadingStatsAggregator` service (likely actor-isolated): query `ReadingSession` records over a `DateInterval`, sum `durationSeconds`, return totals for the standard windows (today / past-7d / past-30d / past-90d / past-180d / past-365d / all-time). Uses `startedAt` as the bucket anchor; sessions spanning a window boundary count toward the window containing `startedAt` (document this decision). (2) **Dashboard view** — new `ReadingDashboardView` (SwiftUI), accessible from **Settings → profile card → Stats** (D1=A resolution 2026-05-20; depends on feature #67's profile card). Top section shows the seven aggregate totals as cards (label + formatted duration via `ReadingTimeFormatter`). Middle section is a per-book table: columns for book title, reading time in the active window, notes count (from `PersistenceActor.fetchAnnotations(forBookWithKey:)`), highlights count (from `PersistenceActor.fetchHighlights(forBookWithKey:)`). Window picker at the top of the per-book table re-runs the aggregator and re-renders. (3) **Sorting** — per-book table sortable by: title (asc/desc), reading time (desc/asc), notes count (desc/asc), highlights count (desc/asc), last-read (desc/asc). Default: reading time desc within the active window. Persist last-used sort in `UserDefaults` mirroring `LibrarySortOrder` pattern. (4) **WebDAV backup inclusion** — extend `BackupDataCollector` with a `collectReadingHistory()` method that emits a new `reading-history.json` (or similar) section containing `ReadingSession` records (sessionId, bookFingerprintKey, bookFingerprint, startedAt, endedAt, durationSeconds, pagesRead, wordsRead) and `ReadingStats` aggregates. `BackupDataRestorer` mirrors with `restoreReadingHistory(...)`. Bumps `kBackupCurrentSchemaVersion`. **Edge cases**: (a) zero sessions for a book — still show row with "0m"; (b) book deleted but historical sessions exist — show row with `(deleted)` placeholder title or omit (decide in plan); (c) session crosses midnight / week boundary — counts to the bucket containing `startedAt`; (d) clock skew (device-time changes) — accept whatever `startedAt` records; (e) very long history (1000+ sessions) — aggregator must be efficient (`@Query`-style predicate over `startedAt`); (f) WebDAV restore from older backup with no `reading-history.json` — section is optional, aggregator falls back to local-only stats; (g) timezone — bucket boundaries computed in user's current timezone (today = local-midnight to local-midnight). **Acceptance criteria**: (a) dashboard surface reachable from Settings → profile card → Stats (D1=A); (b) all 7 windows render correct totals on a fixture with seeded sessions; (c) per-book table shows time/notes/highlights counts, sortable on all 4 columns; (d) sort selection persists across app launches; (e) `BackupDataCollector` emits `reading-history.json`; restore on a fresh device reproduces historical totals; (f) round-trip: backup → wipe → restore preserves `ReadingSession` + `ReadingStats` exactly. **Dependencies**: Feature #29 (WebDAV backup, VERIFIED — for the backup payload extension), `LibrarySortOrder.totalReadingTime` (already exists). **Risks**: (a) aggregator performance over large session histories — may need a denormalized per-day-bucket cache table if N+1 patterns appear; (b) WebDAV backup payload bloat — `ReadingSession` rows accumulate over time; consider compression or window-based truncation; (c) timezone semantics — buckets recomputed if user travels; this is correct but document in UI. **Notes**: builds on existing infrastructure — no new SwiftData @Models required for stats display; read-only over existing schemas plus the new backup payload section. Reported by user 2026-05-14. ~~WI-6 has 4 open product decisions (D1-D4) — blocked at Gate 3 pending user input.~~ (Superseded: D1-D4 were RESOLVED 2026-05-20 as A/B/B/A — see Notes head; WI-6a/6b/6c shipped accordingly and the feature reached DONE 2026-05-22.) GH: #665 |
docs/features.md:119:| 57 | AZW3/MOBI TTS — wire `FoliateTTSAdapter` (or Foliate-webview text extraction) into production so the speaker button works for Foliate-rendered formats | Reader/TTS | Medium | VERIFIED | **VERIFIED 2026-05-26** — criterion-4 pause/resume gap closed CU-free. `Feature26TextToSpeechVerificationTests.test_verify_feature_57_azw3_start_pause_resume_stop_cycle` (seed `.azw3Fixture` — added by Bug #233/#964 — + `--tts-test-mode`) drove the full start → pause → resume → stop lifecycle on the live Foliate AZW3 reader via XCUITest accessibility taps (the play/pause control's "Pause"⇄"Resume" label flips prove `.speaking ⇄ .paused`); 1 test, 0 failures, 20.8 s. All in-scope criteria (1,2,3,4,7) now pass. Evidence: `dev-docs/verification/feature-57-20260526.md`. The 2026-05-19 partial was a framing error (XCUITest taps via accessibility, not CU). **Status**: all 4 WIs merged to `main` — WI-1 (`extractPlainText` JS helper + Swift channel, PR #913, v3.33.8), WI-2 (`startTTS()` AZW3 branch + in-flight extraction gate, PR #916, v3.34.1), WI-3 (re-add `.tts` capability, PR #919, v3.34.3), WI-4 (acceptance verification, this PR). **Verification**: `dev-docs/verification/feature-57-20260519.md`, `result: partial` — criteria 1, 2, 3, 7 verified end-to-end (device + unit); criteria 5 & 6 amended out of scope at the PLANNED flip; criterion 4's **pause/resume** could NOT be exercised end-to-end (the `vreader-debug://tts` grammar has only `start`/`stop`, and CU — the only path to the `TTSControlBar` pause button — is down). Row stays `DONE` (not `VERIFIED`); reaching `VERIFIED` needs a follow-up pause/resume verification (recommend extending `DebugCommand.tts` with `pause`/`resume` actions). **Problem**: AZW3 and MOBI files render through Foliate-js inside a WKWebView. Unlike TXT/MD/PDF/EPUB, the Swift side has no parsed view of the content — there is no `loadBookTextContent` case for these formats. Bug #176 capability-gated `.tts` off `.azw3` to stop the silent failure user-facing (PR forthcoming 2026-05-14, v3.21.42). This feature reverses that gate by implementing a real TTS path. **Plan**: `dev-docs/plans/20260518-feature-57-azw3-mobi-tts.md` (Gate 1; audited clean at Gate 2 round 3, Codex `019e3e3a`). **Scope decision — path (a) chosen** (plan §2): Foliate-webview whole-book plain-text extraction via a new `readerAPI.extractPlainText()` JS helper (walks `view.book.sections[].createDocument()`, the same seam `view.search()` uses) feeding the shared `AVSpeechSynthesizer` pipeline. Path (b) (Foliate in-webview SSML TTS) rejected — `FoliateTTSAdapter` expects a `tts-text` message the bundle never posts, Foliate-js TTS is SSML-based with no `AVSpeechUtterance` bridge, and it is per-section not whole-book. The `v1` path-(a) premise `document.body.innerText` was disproven (host `<body>` is shell-only; book content is two closed-shadow-roots + an iframe deep) — the plan re-bases on the real `createDocument()` seam. **Acceptance criteria**: (1) `.tts` re-added to `FormatCapabilities.capabilities(for: .azw3)`; speaker button visible in AZW3/MOBI reader chrome again. (2) Tapping speaker → TTS starts speaking the AZW3 text; `vreader-debug://snapshot` reports `ttsState: "speaking"` and `ttsOffsetUTF16` advances over time. (3) `vreader-debug://tts?action=start` URL path works for AZW3 (matches TXT/MD/PDF/EPUB behaviour). (4) Pause/Resume/Stop cycle exercised end-to-end on iPhone 17 Pro Sim. (5) **AMENDED at PLANNED flip (plan §7.1, Gate-2 audit-confirmed)**: visual sentence-highlight inside the Foliate WKWebView is **explicitly out of scope** for #57 — `TTSHighlightCoordinator` is TXT/MD-only (`TTSHighlightCoordinator.swift:7-10`) and is never instantiated for Foliate, so the #40 pipeline does not run there at all; a Foliate TTS-highlight overlay is a tracked follow-up feature, not a line item of #57. (6) **AMENDED at PLANNED flip (plan §7.1, Gate-2 audit-confirmed)**: auto-scroll inside the Foliate WKWebView is **explicitly out of scope** for #57, for the same reason — feature #41's own VERIFIED row already declares "EPUB/AZW3/PDF intentionally out of scope (different scroll surfaces)." (7) Removed regression-guard `azw3_doesNotSupportTTS()` test; replaced with positive `azw3_supportsTTS()` assertion. #57 delivers **TTS audio + pause/resume/stop** for AZW3/MOBI; visual highlight/scroll on Foliate is deferred to a separate feature. **Dependencies**: Feature #42 (Foliate unified reader engine) listed as a soft dependency only "if pursuing path a via Foliate's #42-introduced helpers" — **severed**: path (a) uses #57's own `extractPlainText` helper added to `foliate-host.js`, not a #42 helper; #57's Gate 3 does not wait on #42 (merge-order coordination only — plan §3.4). **Risks**: path (a) — `extractPlainText()` must return correct whole-book text and the returned `Promise<string>` must marshal across `evaluateJavaScript` (front-loaded into WI-1's device-verified feasibility slice); whole-book extraction may be slow on large books → handled by deferring to first speaker tap + an in-flight extraction gate (`azw3ExtractionTask`) for rapid repeated taps. Reported by user 2026-05-13 via bug #176 fix's deferral. GH: #904 |
docs/features.md:120:| 56 | Bilingual reading mode — AI-translated chapter displayed inline below original, persistent disk cache, whole-book translation, per-chapter re-translation with provider override | AI/*, Reader/* | Medium | VERIFIED | **2026-05-20 — VERIFIED (Gate 5b round-3)**: all 6 acceptance criteria PASS via host-script + DebugBridge + live OpenRouter provider; criterion (b) re-verified post Bug #245 fix (PR #1076, v3.38.19) — TXT bilingual interleaved render directly observed via `mcp__computer-use__screenshot` (war-and-peace.txt chapter 3, English source + Chinese inline below each paragraph). Evidence: `dev-docs/verification/feature-56-20260520-round3.md` (round-3 result=pass) + `dev-docs/verification/feature-56-20260520-round2.md` (round-2 result=partial, criteria a/c/d/e/f PASS, criterion-b PARTIAL pre-fix). **2026-05-20 — DONE**: all 15 WIs shipped (WI-1..15 incl. WI-2.5 + WI-7a/7b split). WI-15 (final) — `ChapterReTranslateViewModel` + `ReTranslatePickerSheet` + host wiring (`ReaderContainerView+ReTranslate`) deliver acceptance criteria (e) per-chapter re-translate clears old cache and fetches fresh, and (f) provider override does not mutate `ProviderProfileStore`. Awaiting Gate 5b post-merge final-acceptance pass (every AC exercised end-to-end against a real provider) → `VERIFIED`. **Scope note — secondary TOC swipe affordance deferred to a follow-up `needs-design`**: the plan named `ChapterReTranslateSwipeAction` in `TOCListView`, but the existing TOC is `LazyVStack`-in-`ScrollView` and SwiftUI `.swipeActions` requires a `List` host — the designed swipe affordance cannot attach without inventing UI (rule 51). The primary path (More-menu row → picker → progress) fully delivers (e) and (f); the secondary TOC swipe is queued as a follow-up. **Gate 3 complete — WI-1..WI-15 merged (incl. WI-2.5, WI-7a/7b split).** **Gate 1+2 complete — plan dev-docs/plans/20260519-feature-56-bilingual-reading.md, Codex-audited clean.** **Design delivered 2026-05-18 — issue-canvas handoff resolves needs-design #863, #864** — triage 2026-05-18: the committed design (`vreader-bilingual.jsx` + `feature-60-followups.md` §2) covers the interlinear renderer, setup sheet, More-menu row, and `EN ↔ 中` pill — but NOT scope item (3) "Translate entire book" (entry point / confirmation / progress / cancel → `needs-design` #863) nor scope item (4) per-chapter re-translate UI + provider-override picker (→ `needs-design` #864). The core bilingual-reading slices are designed; the global-translate + re-translate slices are blocked. **Problem**: Feature #18 translates selected text within the AI panel (point-in-time, in-memory cache, session-only). Users reading foreign-language books want a full bilingual reading experience: the entire current chapter translated and displayed inline below the original text, cached to disk so translations survive app restarts, with a global translate-entire-book option and per-chapter re-translation control. **Scope**: (1) **Chapter bilingual mode** — a toggle in the reader AA panel (per-book, persisted in `PerBookSettings`) that, when enabled, fetches the full chapter text through `AIService.sendRequest` and renders the translation below the original in each reader format. For TXT/MD: append translation in a styled `UITextView` section below the chapter text. For EPUB: inject translated paragraphs after each `<p>` via a JS bridge call. For Foliate/AZW3: inject via Foliate message. For PDF: overlay translation panel below the page. Target language defaults to Chinese (user-configurable per-book or globally). (2) **Persistent translation cache** — `ChapterTranslationStore` actor (new SwiftData `@Model`): keyed by `(fingerprintKey, chapterHref, targetLanguage, providerProfileID, promptVersion)` → translated text + timestamp. `AIResponseCache` is session-only in-memory; this store persists to disk and survives relaunches. Stale-cache invalidation: user-driven only (re-translate). (3) **Global book translation** — "Translate entire book" action in the Library card or book detail screen. Presents a confirmation alert with estimated chapter count and a warning ("This will send all chapters to your AI provider, which may use a significant number of tokens"). Runs chapter-by-chapter as a `Task.detached` background operation with cancellability; progress bar in a translating status badge. Already-cached chapters are skipped. (4) **Per-chapter re-translation** — "Re-translate Chapter" option in the reader AA panel long-press menu or chapter list context menu. Clears the cached entry for that chapter and re-fetches. Provider override: a picker (using existing `ProviderProfileStore`) lets the user choose a different AI provider for the re-translation without changing the global active provider. **Edge cases**: (a) chapter text exceeds provider max_tokens — split into chunks with overlap, recombine; (b) translation in progress when user navigates away — cancel and discard partial result; (c) offline mode — load from disk cache if available, else show "Translation unavailable offline"; (d) provider changed after cache entry written — treat as stale (different providerProfileID); (e) CJK→CJK translation (e.g. Simplified→Traditional) — same pipeline, no special case; (f) concurrent global translation + single-chapter re-translate racing on the same chapter — last writer wins, or serialise via actor; (g) book deleted while global translation running — cancel the operation and clean up cache entries. **Acceptance criteria**: (a) bilingual mode toggle persists per book; (b) current chapter translation renders inline within 10 seconds for a typical chapter; (c) cached translation loads immediately on next app open without an API call; (d) global translate shows confirmation with chapter count and can be cancelled; (e) per-chapter re-translate clears old cache and fetches fresh; (f) provider override for re-translate does not change the global active provider. **Dependencies**: Feature #18 (VERIFIED — `AIService`, `AITranslationViewModel`), Feature #50 (VERIFIED — `ProviderProfileStore`). Reported by user 2026-05-14. **Design landed 2026-05-16**: `dev-docs/designs/vreader-fidelity-v1/project/design-notes/feature-60-followups.md` §2.1 is feature #56's design source — paragraph-interlinear rendering (each source paragraph followed by its translation at ~0.88× size, `sub` color, slight indent), a first-toggle setup sheet (target language / Paragraph|Sentence granularity / AI-provider chip), and a persistent on/off mode with an `EN ↔ 中` reader-chrome pill. Arrived via the feature #60 follow-up handoff — the #790 `Design needed:` issue proposed this as a new feature before realising #56 already tracked it. Feature #56 can be promoted TODO → PLANNED against this design. **Scope note 2026-05-17**: #56's scope explicitly includes the **More-menu bilingual toggle row** (`feature-60-followups.md §2.3` — off / on / AI-unavailable states) as bilingual mode's entry point. Feature #60 WI-6c deferred that row (`ReaderMoreMenuRow.swift` marks Bilingual deferred) and a "WI-6d" was named but never created; since #60 is VERIFIED the row has no home there — #56 owns it, and #56's eventual plan must implement the row alongside the backing mode. WI-13 (PDF below-page translation panel) + the bilingual-offline-affordance WI are needs-design-blocked. GH: #629 |
docs/features.md:122:| 54 | Remove Native/Unified reading mode toggle — route by ReaderEngine internally | Reader/* | Medium | VERIFIED | **Problem**: The Native/Unified picker leaks an implementation detail. Users want "apply replacement rules" or "convert Chinese," not "Unified mode." A toggle that makes EPUB rendering worse is the wrong abstraction. Design decision documented in GH #493. **Scope**: (1) Hide picker when no transforms configured; (2) Introduce internal ReaderEngine routing (textNative/markdownNative/epubWKWebView/foliateWeb/pdfKit) replacing readingMode branch; (3) Wire replacement rules into native EPUB (JS text-node preprocessing, CFI-safe) and MD (TextMapper.apply before parse); (4) Migrate and remove readerReadingMode from UserDefaults + per-book PerBookSettings; (5) Retire UnifiedPlaceholderView and dead Unified paths. **Acceptance criteria**: no picker in normal use; replacement rules work in native EPUB and MD without mode switch; readingMode key removed with migration; all existing reader features unchanged. **Dependencies**: Feature #42 (Foliate-js) required for full EPUB engine swap — steps 1/3(MD)/4 can land independently. **Risks**: Foliate JS transforms must be CFI-safe; per-book override migration; transform parity tests required per engine before removing toggle. **Gate 1 + Gate 2 complete 2026-05-19**: implementation plan at `dev-docs/plans/20260518-feature-54-remove-reading-mode-toggle.md` (v3, 7 WIs across 3 autonomous phases + 1 deferred Phase D). Independent Codex plan audit ran 3 rounds; round-3 verdict clean (round-1 found 8 findings — TXT replacement rules deferred to Phase D, synchronous migration; round-2 found 3 — `openPositionUnsupportedInUnifiedMode` one-producer reality, semantic-not-byte migration preservation, WI-4 two-file scope; all resolved). EPUB replacement-rule wiring + `epubWKWebView`/`foliateWeb` differentiation + native-TXT replacement rules are explicitly DEFERRED (Phase D). **All 7 WIs shipped → DONE 2026-05-19**: WI-1 `ReaderEngine` enum + per-format `resolve` (PR #878, v3.31.4); WI-2 `ReadingModeMigration` namespace (PR #879, v3.31.5); WI-3 reader dispatch routed by `ReaderEngine`, Unified dispatch branch deleted (PR #883, v3.31.7); WI-4 Reading Mode + Tap Zones removed from the settings panel (PR #886, v3.31.9); WI-6 DebugBridge cleanup — retired `openPositionUnsupportedInUnifiedMode` (PR #888, v3.31.11); WI-5 `ReadingMode` enum + `readerReadingMode` key/field removed, one-shot launch migration (PR #893); WI-7 content replacement rules wired into the native MD reader via `MDFileLoader` transform chain — the final WI (PR #901). WI-5/WI-6 implementation order was swapped vs the plan (WI-5's field removal would not compile while WI-6's DebugBridge guard still read `store.readingMode`). Phase D (native EPUB replacement rules, `epubWKWebView`↔`foliateWeb` differentiation, native TXT replacement rules + offset map) remains deferred — see plan §4 Phase D. `VERIFIED` flip pending the final-WI full acceptance pass + evidence file. **2026-05-19 (Gate-5 CU-free XCUITest verification)** — `dev-docs/verification/feature-54-20260519-cu-free.md`, `result: partial`, on iPhone 17 Pro Simulator / iOS 26.4, `main` @ `306f7ce`, v3.34.3. A new CU-free XCUITest suite `Feature54ReadingModeRemovalVerificationTests` (4 tests, all green) drives the app through the accessibility API — no computer-use, no DebugBridge URL-confirm — and closes the headless-navigation gap that blocked the earlier `feature-54-20260519.md` partial. Verified end-to-end via the live reader UI: criterion 1 (no Reading Mode / Tap Zones / Native / Unified picker anywhere in the Display panel — for TXT, EPUB, MD, full 12-section scroll), criterion 2's structural half (MD opens into the native `markdownNative` engine with no mode switch — transform correctness still via the 20 integration tests), criterion 5 (TXT/EPUB/MD each open into their native `ReaderEngine` surface and render). Criterion 4 stays device-verified + unit (UserDefaults / launch-migration — no UI surface). **Row stays `DONE`, NOT `VERIFIED`**: criterion 3 (replacement rules in native EPUB without a mode switch) is in the acceptance contract but was DEFERRED to Phase D by the plan and Phase D has not shipped — one acceptance criterion is genuinely unimplemented, so per `SCHEMA.md` the `partial` result cannot flip the row. `VERIFIED` flip awaits Phase D shipping criterion 3 + a follow-up acceptance pass. **2026-06-08 Phase D-1 shipped → VERIFIED** (v3.59.26, evidence `dev-docs/verification/feature-54-20260608-phase-d1.md`, `result: pass`): criterion 3 (replacement rules in native EPUB) is now implemented + device-verified. NEW `EPUBReplacementJS.injectionJS` builds a CFI-safe per-text-node replacement JS (string replace-all / regex global; only `nodeValue` mutated, structure untouched, JSON-escaped rules) wired into BOTH EPUB engines per `ReaderEngine.routeEPUB`: the legacy #71 WKWebView stitch (inject on `EPUBWebViewBridgeCoordinator.didFinish` + a scroll-root `MutationObserver` for appended chapters) and Readium (`ReadiumReaderCoordinator+Replacement` per-spine on `locationDidChange`). Rules fetched via `MDReplacementRuleFetcher`. Device-verified on the legacy stitch (default scroll mode): a seeded global "Chapter"→"Sektion" rule auto-applies on open (`hasChapter=False, hasSektion=True`), both chapters covered (2/2 sections marked, "Sektion Two" present via the observer). 23 `EPUBReplacementJS` unit tests + the banner-copy test updated (EPUB now a supported format). Codex audit `follow-up-recommended`: 2 Medium accepted with rationale — both are the documented v1 limitation (rules apply at open; a mid-read edit takes effect on next open, since correct live re-apply needs original-text preservation). All 5 acceptance criteria met. Native-TXT replacement rules + `epubWKWebView`↔`foliateWeb` further differentiation remain separate deferrals. GH: #609 |
docs/features.md:124:| 52 | Multiple WebDAV server profiles with active-server switching | Settings/Backup | Medium | VERIFIED | **Problem**: WebDAV backup stores exactly one server's credentials in Keychain under fixed account keys (`com.vreader.webdav.serverURL/username/password`). Users with multiple WebDAV services (Nextcloud at home, Synology at work, Nutstore) must re-enter credentials every time they switch. **Scope**: (1) `WebDAVServerProfile` value type: `id: UUID`, `name: String`, `serverURL: String`, `username: String`, password Keychain-backed per `id`; (2) `WebDAVServerProfileStore` actor: persists a list of profiles (UserDefaults JSON) + `activeProfileID`; (3) Keychain: per-profile key `com.vreader.webdav.profile.<id>.password`; (4) Migration: on first launch, if legacy flat keys exist, migrate them into a profile named "Default" and set as active; (5) Settings UI: replace `WebDAVSettingsView`'s single-server form with a profile list (add/edit/delete/set-active) — mirrors `AIProviderListView` / `AIProviderEditSheet` pattern; (6) `WebDAVProviderFactory.make(...)` reads the active profile from the store instead of reading flat Keychain keys. **Edge cases**: (a) zero profiles — disable Back Up Now / restore with "Add a server in WebDAV Settings" prompt; (b) active profile deleted — fall back to first remaining or disable; (c) credential migration from legacy flat keys — silent, no re-entry required; (d) duplicate URLs are allowed (same server, different credentials); (e) profile name empty — default to serverURL hostname; (f) server URL malformed — validation before save. **Acceptance criteria**: (a) user can add two WebDAV profiles and switch the active one — only the active server is used for backup; (b) existing single-server users migrate without re-entering credentials; (c) deleting the active profile falls back to remaining or disables backup; (d) backup + restore round-trip works with the selected profile. Reported by user 2026-05-12. **Gate 1 + Gate 2 complete 2026-05-14**: implementation plan at `dev-docs/plans/20260514-feature-52-multiple-webdav-profiles.md` (7 WIs sized after Feature #50's precedent; foundational/behavioral tier-marked). Manual-fallback audit (Codex MCP unavailable) inline in plan section 9 — 1 Medium finding (JSON corruption edge case → defensive `try?` fallback in store init) + 2 Low findings (Notification.Name + migrator-async invocation pattern), all fixed in plan. **WI-1 shipped 2026-05-14 in v3.21.46** (PR #648): `WebDAVServerProfile` value type + `WebDAVServerProfileStore` actor + 32 tests (12 + 20). Foundational tier; no user-observable behavior. Gate 4 manual-fallback audit (Codex unavailable): zero open findings, ship-as-is. **Status flipped IN PROGRESS**. **WI-2 shipped 2026-05-14**: `WebDAVProfileMigrator` enum (109 LOC) + 6 tests covering legacy-flat-keychain → "Default" profile migration with idempotency on two axes (marker `com.vreader.webdav.profilesMigrated.v1` set OR store non-empty) + partial-legacy edge (URL-only) + fresh-install + repeat-call safety. Foundational tier; migrator callable but currently unwired (WI-3 wires it into `VReaderApp.init` + `WebDAVProviderFactory`). Stable migrated UUID `00000002-AAAA-4000-8000-000000000001` ensures re-runs upsert in-place. Legacy keychain entries kept (cleanup deferred to a post-#52 WI). Gate 4 manual-fallback audit (Codex unavailable): zero open findings, ship-as-is. **WI-3 shipped 2026-05-14**: `WebDAVProviderFactory.make(persistence:profileStore:...)` async + `makeRequestBuilder(profileStore:)` async variants (read active profile from store, dispatch to `WebDAVProvider` / `WebDAVDownloadRequestBuilder` with the same error contract as legacy sync variants: `missingCredentials` for no-active / empty-fields / no-password, `invalidServerURL` for malformed URL). 8 dispatch tests (`WebDAVProviderFactoryProfileDispatchTests`) cover the contract. `VReaderApp.init()` schedules `WebDAVProfileMigrator.migrateIfNeeded(...)` as a fire-and-forget background `Task.detached` at the end of the success branch. Legacy sync variants left untouched (parallel paths until WI-5); the two existing call sites (`WebDAVSettingsView.swift:371`, `LibraryView.swift:147`) continue to use the legacy flat-keychain readers. **Deliberate divergence from plan section 2.4's "thin wrapper" wording**: making the existing sync `throws` variant a wrapper over the new async path would require either a semaphore (antipattern) or a signature change (breaks the "compiling unchanged" goal); parallel paths achieve the plan's stated after-WI-3 outcome ("backup still works for existing users via the migrated Default profile") without churning the two legacy call sites. Foundational tier. Gate 4 manual-fallback audit (Codex unavailable): zero open findings, ship-as-is. **WI-4a shipped 2026-05-14 in v3.21.54** (PR forthcoming): `WebDAVProfileListViewModel` @Observable @MainActor VM (loadProfiles via atomic loadSnapshot, setActive with stale-id guard, deleteProfile with VM-side state cleanup) + `WebDAVServerProfileListView` (radio-row selection, leading/trailing swipe actions, pencil-edit affordance, empty state with externaldrive icon + Add CTA, `webdavProfilesDidChange` notification observer for external resync) + `WebDAVServerProfileEditSheet` STUB body (Cancel + Add-mode placeholder save writing `WebDAVServerProfile(name: "New WebDAV Server", serverURL: "", username: "")` per the plan's "placeholder save" wording) + `WebDAVSettingsView` modified to add a top NavigationLink section (legacy single-server form retained until WI-4b ships the full editor, to avoid breaking credential entry between merges). Sheet presentation uses `.sheet(item: $editorContext)` with a `WebDAVEditorContext: Identifiable, Equatable, Sendable` wrapper mirroring bug #174's AIEditorContext race-fix pattern. **Unified `.alert(...)` plumbing** via `enum WebDAVListAlertItem` (Codex round-2 finding) collapses the listError + active-delete-confirm into one alert binding so SwiftUI's "one alert per branch" limitation can't drop a path. Active-row swipe-delete prompts a confirmation alert ("Delete active server?") naming the displayName + "leaves no active server" copy; inactive rows delete immediately. **Re-entrancy guard** on stub editor's Add button (`@State isAdding` + `.disabled(isAdding)`) prevents duplicate placeholder rows from rapid double-tap. **VoiceOver disambiguation**: row label joins displayName + username + URL host (so duplicate-named profiles don't sound identical). Codex MCP audit `019e257c` (4 verification rounds): round 1 = 2 Medium (active-delete confirmation + stub-cancel-only) + 2 Low (VoiceOver + UI tests). Round 2 = 2 Medium (dual `.alert` conflict + re-entrant Add button) — both addressed. Round 3 = 2 Medium (listError state inconsistency + dropped deferred listError) — both addressed via direct mutation in listError OK + `promoteDeferredListErrorIfAny()` helper. Round 4 = zero findings, ship-as-is. Test gate: 21/21 new tests pass (11 VM + 7 EditorContext id stability/Equatable + 2 stub editor placeholder save + 1 notification-driven resync). Per-WI Gate 5 slice verification PASS on iPhone 17 Pro Sim (iOS 26.5): Settings → WebDAV Backup → Servers nav-link → empty state with "Add Server" CTA → tap Add → stub editor presents → tap Add toolbar → placeholder row "New WebDAV Server" appears with empty radio → tap radio → row activates (`largecircle.fill.circle`) → swipe-left active row → red Delete chip appears → tap Delete → confirmation alert "Delete active server? 'New WebDAV Server' is currently the active backup server. Deleting it leaves no active server until you switch to another or add one." with Cancel + Delete buttons → tap Cancel → alert dismissed, active row preserved. 2 evidence screenshots (`feature-52-wi4a-01-list-with-active-row-20260514.png`, `feature-52-wi4a-02-active-delete-confirmation-20260514.png`). Behavioral tier — slice verified pre-merge per plan section 4 "Tier: Behavioral. List UI lands but full editor in WI-4b". Audit log: `.claude/codex-audits/feat-feature-52-wi-4a-profile-list-ui-audit.md`. **WI-4b shipped 2026-05-14 in v3.21.57**: replaced WI-4a's stub editor with the full add/edit form — `WebDAVServerProfileEditSheet.swift` (rewrite, ~240 LOC) + `WebDAVServerProfileEditSheet+Sections.swift` (NEW, ~150 LOC: nameSection / endpointSection / passwordSection / testConnectionSection) + `WebDAVProfileListViewModel+Editor.swift` (NEW, ~180 LOC: addProfile / updateProfile / savePassword / deletePassword / testConnection + WebDAVTestConnectionError + validatedServerURL shared static helper) + `WebDAVServerProfileStore.updateIfExists(_:)` single-hop atomic update. Bug #184 pattern: add-mode hides Save Password / Delete Password / Test Connection buttons and shows promoted footnote notes; edit-mode shows the real buttons. WebDAVError → LocalizedError conformance gives specific Test Connection failure messages (authenticationFailed → "check the username and password", httpError(405) → "Server doesn't support WebDAV PROPFIND ... verify this URL points at a WebDAV endpoint"). Behavioral tier; full feature reachable from Settings. **Codex MCP audit `019e26d6` (3 rounds)**: round 1 = 1 High (URL validator weak — accepted `https://` hostless) + 4 Medium (updateProfile stale-guard, WebDAVError generic, testConnection whitespace credentials, name autofill missing) + 1 Low (direct KeychainService in view bypasses test injection); all 6 fixed. Round 2 = 2 new Medium (updateProfile race across 2 actor hops, password whitespace persisted verbatim); both fixed via `updateIfExists` + trim-before-persist. Round 3 = **zero findings, ship-as-is**. Test gate: **31/31 new tests** pass (`WebDAVProfileListViewModelEditorTests`) covering all 5 editor methods + URL validator (6) + WebDAVError messages (3) + round-1 fixes (3) + keychain VM-probe (2) + round-2 fixes (4). Adjacent suites (`WebDAVProfileListViewModelTests` + `WebDAVServerProfileStoreTests` + `WebDAVServerProfileTests` + `WebDAVProviderTests`) all green. Audit log: `.claude/codex-audits/feat-feature-52-wi-4b-profile-editor-audit.md`. **WI-5 shipped 2026-05-14**: foundational cleanup. Removed the legacy single-server credentials form from `WebDAVSettingsView` entirely (Server URL / Username / Password fields + Test Connection + Save / Remove Credentials buttons + supporting state vars + helper methods + 3 keychain-account constants + the `keychain:` init parameter). Migrated the 2 remaining production call sites (`WebDAVSettingsView.refreshBackupVMIfNeeded` + `LibraryView`'s row-tap-to-enqueue observer) from legacy sync `WebDAVProviderFactory.make(keychain:)` / `makeRequestBuilder(keychain:)` to the async profile-store-backed variants from WI-3. Deleted those now-unused sync factory variants (~80 LOC removed; factory header comment rewritten to reflect post-WI-5 state). Wired `WebDAVServerProfileStore.writePassword(_:for:)` + `deletePassword(for:)` to post `.webdavProfilesDidChange` so observers re-evaluate active credentials on password-only mutations (round-2 fix — without this, password changes from the editor sheet would leave the backup section stale). Added `WebDAVSettingsView` `.onReceive(.webdavProfilesDidChange)` to refresh the backup VM on add/switch/password-update from the multi-profile list. Added 3 new UserDefaults keys (`com.vreader.webdav.profiles`, `.activeProfileID`, `.profilesMigrated.v1`) to `TestSeeder.knownPreferenceKeys` for `--reset-preferences` test isolation. Doc-synced `docs/architecture.md` (3 rows: `WebDAVProviderFactory` is profile-store-only now; `WebDAVServerProfileStore` backing is `UserDefaults` / `KeychainService`; `WebDAVProfileMigrator` added). Codex MCP audit `019e26ec` 4 rounds: round 1 = 1 High (source-of-truth divergence — surgical loadCredentials change introduced inconsistency with save/clear paths) + 1 Medium (flat-keychain fallback still in view layer) + 1 Low (arch.md backing column); resolved by escalating the WI-5 scope to remove the legacy form entirely. Round 2 = 1 Medium (writePassword/deletePassword didn't post notification) + 2 Low (stale arch.md rows + orphan `@Environment(\.dismiss)`). Round 3 = 2 Low (stale comments in VReaderApp.swift and WebDAVProviderFactory.swift referencing removed legacy variants). Round 4 = 1 Low (this tracker row narrative). All findings fixed. Test gate: 33/33 editor tests pass (added 2 new `webdavProfilesDidChange` notification-on-password-mutation tests) + 122/122 across 7 WebDAV-adjacent suites all green. Audit log: `.claude/codex-audits/feat-feature-52-wi-5-cleanup-audit.md`. **WI-6 round-1 partial 2026-05-14** (`dev-docs/verification/feature-52-20260514.md`, result=**partial**) on merged-main 942703b (v3.21.61, build 338) against iPhone 17 Pro Sim (iOS 26.5) + 2 test rclone WebDAV servers on 127.0.0.1:8082-8083 (live ~/vreader-webdav-data not touched). **UI-shape verification PASS**: WI-5 cleanup confirmed (WebDAV Backup screen has zero legacy single-server form remnants — just Servers nav-link + Network policy section); WI-4a list view renders with toolbar `+` / radio-row active marker / pencil-edit affordance; WI-4b editor add-mode shows the bug #184 pattern (Save Password / Test Connection buttons hidden, footnote notes shown instead); edit-mode shows the real buttons. Prior-session profile persisted across `vreader-debug://reset?backups=true` (UserDefaults-backed; library-scoped reset doesn't clear WebDAV keys — matches design). 4 screenshot artifacts. **DEFERRED to round-2**: acceptance (a) switch-active + per-profile backup observation, (c) live delete-active-profile fallback on backup section, (d) full backup+restore roundtrip — all blocked on CU `type` not reaching iOS Simulator text fields this session (CU/Simulator integration limitation, not a vreader defect). Three round-2 unblock paths documented in the evidence file: clipboard fast-path (`clipboardWrite` grant + cmd+v), pre-launch UserDefaults+Keychain seed, or a new `vreader-debug://webdav?profile=<json>&password=<pw>` URL. Status stays **IN PROGRESS**. **WI-6 round-2 final acceptance 2026-05-15** (`dev-docs/verification/feature-52-20260515.md`, result=**pass**) on merged-main 891c616 (v3.21.61, build 338) against iPhone 17 Pro Sim (iOS 26.5) + 2 test rclone WebDAV servers on 127.0.0.1:8082-8083. Unblock path: CU clipboard fast-path (`request_access` with `clipboardWrite: true` + `cmd+v` paste keystroke into focused TextFields) — reaches all fields where `type` couldn't. Acceptance: (a) **PASS** — two distinct backup zips landed in their respective server data dirs (`/tmp/vreader-test-webdav-a/.../2026-05-14T20-10-23Z_d6c6c5ce.vreader.zip` when A active; `/tmp/vreader-test-webdav-b/.../2026-05-14T20-12-21Z_d0348cab.vreader.zip` when B active); each server's dir empty when the other was active. (b) covered by 6 `WebDAVProfileMigratorTests` unit tests; live migration not exercisable post-WI-5 (no way to write pre-WI-5 flat-keychain state from a post-WI-5 install). (c) **PASS** — swipe-delete active row → confirmation alert with `"Server B (test)" is currently the active backup server. Deleting it leaves no active server until you switch to another or add one.` copy → Delete → plist `activeProfileID` key REMOVED, profiles array reduced by 1 (Server A preserved as inactive); WebDAV Backup screen Backup section disappears, "Add a WebDAV server above to enable backup." footnote shown. (d) **PASS (backup half)** — Test Connection returned "Connected — the WebDAV server responded successfully." against real rclone Server A; backup roundtrip uploaded zip + per-book blob to correct active-server-only directory via real PROPFIND + auth + MKCOL + PUT; restore button is wired but not explicitly clicked this round (covered by `WebDAVProviderTests` integration). 7 round-2 screenshot artifacts. **Bug discovered + filed** (per scope guardrail, NOT fixed): WebDAVServerProfileListView shows the empty-state empty-state after any mutation (Save, Add, setActive, delete) until view is dismissed and re-presented — underlying UserDefaults persistence is correct (verified via plist), SwiftUI list view doesn't re-render on `.webdavProfilesDidChange`. Status → **VERIFIED**. GH #565 closing. |
docs/features.md:158:| 104| **Android Spike A — canonical cross-platform identity conformance** (the gate; ADR-0001 Risk 1). Decomposed from #102. Prove/decide deterministic book identity across Swift and Kotlin BEFORE promising library/backup interop: a `contracts/` canonical spec (fingerprint/locator/cache-key/backup-format distilled from the Swift reference), a libmobi cross-platform conversion-determinism harness, a Readium locator round-trip harness, the canonical-identity DECISION (exact-match / normalization / platform-local+mapping), legally-clean golden vectors + a dual-platform (Swift+Kotlin) conformance command. Library/CLI harnesses, NOT an Android app. **Depends on #103 (Phase 0 owns `contracts/` routing).** | contracts/ (new), contracts/conformance/{swift,kotlin}/, contracts/harness/ | High | VERIFIED | Decomposed 2026-06-16 from #102 (ADR-0001 Spike A). Plan: `dev-docs/plans/20260616-feature-104-android-spikeA-identity-conformance.md` (Gate-1 drafted; awaiting Gate-2 audit). **HELD with #102.** WI-1/2 Swift-only (doable without Android toolchain); WI-3+ need NDK+Kotlin/JVM (shared with Spike B). A conversion/locator DIVERGENCE is a successful spike result (it sets the canonical model), not a failure. **PLANNED 2026-06-16** (Gate-2 clean, Codex `019ed111`→`019ed122`); **IN PROGRESS 2026-06-17** — WI-1 `contracts/` canonical spec (README + identity/{fingerprint,locator,cache-key,backup-format}.md distilled from the Swift reference) done. WI-2 (Swift conformance, PR #1708→) + WI-5 SEEDED: dual-platform identity conformance lane DONE for fingerprint + cache-key — shared `contracts/vectors/`, Swift suite (vreaderTests/Contracts) + Kotlin suite (contracts/conformance/kotlin, pure Kotlin/JVM) both GREEN via `contracts/conformance/run.sh`. **Toolchain INSTALLED 2026-06-17** (JDK17, Kotlin 2.4, Android SDK platform-35 + NDK 29 + CMake, Gradle 9.5 — verified end-to-end). **DONE+VERIFIED 2026-06-17** — WI-4 added the **engine-neutral `Locator.canonicalJSON` cross-platform conformance** (Swift `Locator.canonicalJSON()` + a Kotlin `CanonicalLocator` reference impl produce a byte-identical canonical string for one shared `contracts/vectors/locator.json` — both suites GREEN), and the **canonical-identity DECISION** (`contracts/identity/DECISION.md`): exact-match for native fingerprint + cache-key + `Locator.canonicalJSON`; **source-bytes (not converted-EPUB)** for converted-Kindle cross-platform identity (the iOS `MobiEPUBConverter` is deterministic+content-addressed but pipeline-specific → source-bytes is the robust canonical key, NDK byte-identity harness off-critical-path); **CFI lossy-fallback** (resume on progression + text quotes; corroborated by #105 WI-3's ~2-paragraph fragment-restore approximation). All 4 acceptance criteria met. Evidence `dev-docs/verification/feature-104-20260617.md`. GH: #1702. |
docs/features.md:159:| 105| **Android Spike B — CJK WebView reader benchmark** (instrumentation-first; ADR-0001 Risk 2). Decomposed from #102. Measure Readium-Kotlin 3.3.0 on a real 1000+-spine CJK novel (道诡异仙) — scroll smoothness/jank, memory+eviction over a long sweep, renderer stability, CFI+selection anchor restore — BEFORE committing to the WebView-engine plan. Throwaway harness module, NOT the product app; benchmark/instrumentation-driven, NOT UI-automation (the iOS verify stack doesn't transfer). Secondary deliverable: a minimally-automatable Android verification recipe. **Depends on #103 (Phase 0 must gate `spikes/` first); independent of #104, can run in parallel once #103 lands.** | spikes/android-reader-bench/ (harness root picked), dev-docs/verification/feature-105-* | High | VERIFIED | Decomposed 2026-06-16 from #102 (ADR-0001 Spike B). Plan: `dev-docs/plans/20260616-feature-105-android-spikeB-cjk-reader-benchmark.md` (Gate-1 drafted; awaiting Gate-2 audit). **HELD with #102.** All WIs gate on Android SDK/NDK+emulator+Readium-Kotlin toolchain (UNVERIFIED on the host — bring-up is WI-1). A jank/memory-unacceptable result reopens the engine strategy (a legitimate spike outcome). **PLANNED 2026-06-16** (Gate-2 clean, Codex `019ed111`); **IN PROGRESS 2026-06-17** — WI-1: toolchain + emulator stood up (the ADR-UNVERIFIED 'can the cron drive an Android device' = now YES); a minimal Android instrumentation test (`spikes/android-reader-bench`) builds + installs + RUNS on the android-35 arm64 emulator. **DONE+VERIFIED 2026-06-17** — all 4 WIs merged (WI-1 harness v3.66.24 PR#1710; WI-2 scroll/memory/stability bench v3.66.25 PR#1711, Codex 3-round; WI-3 anchor/selection restore v3.66.26 PR#1712, Codex 3-round; WI-4 verdict). **Verdict: Readium-Kotlin 3.3.0 scroll mode is VIABLE as the Android v1 reader engine — WebView-engine plan CONFIRMED, NOT reopened** (60fps / 0.23% jank; renderer memory bounded with working eviction, ~1.1GB high-water → 580-870MB oscillation, zero OOM; zero renderer crashes; chapter + Locator-JSON + selection restore faithful). Two recorded Phase-3 hardening obligations (not blockers): renderer ~1.1GB high-water (low-RAM watch-item) + fragment-restore ~2-paragraph CJK precision. Evidence `dev-docs/verification/feature-105-20260617.md`; ADR-0001 Spike-B amendment added; recipe `spikes/android-reader-bench/run-bench.sh`. GH: #1703. |
docs/features.md:184:| 131| **Android bilingual interlinear reading** (parity box D) — per-book toggle renders each source paragraph followed by an AI-backed translation (muted, accent border), cached to disk; Android parity of iOS #56/#100, building on the #118 AI foundation. | android/app/.../bilingual/* + reader hosts + ReaderBottomChrome/More-menu entry | Medium | PLANNED | Deps:[feat:#132, feat:#134] (#132 top chrome + #134 More menu VERIFIED; #129 TXT reader VERIFIED = straight edit). **AI-config reachability FOLDED IN (2026-07-12, user decision): the #136 spin-out is CLOSED (GH #1976, not-planned) — the Gate-2 audit + committed design (reader-ai-provider-entry.md / reader-ai-readiness.md) proved the ONLY designed Android AI-config reader surface is the bilingual-coupled "Variant A" AI Providers sheet reached from the bilingual Set-up button; NO standalone AI-config entry is designed. #131 now owns it: AppContainer AiProviderStore DI + the Variant A AI Providers sheet (reuse #118 AiProviderListScreen/AiProviderEditSheet verbatim, pushed in the bilingual flow, pop-back-on-save) as its own WIs.** Plan `dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md` (Gate-1 v4, 13 WIs: WI-0 Readium JS-injection spike w/ go-no-go + navigator-race contract; WI-1..4a foundation/service; WI-4b shared DI incl. AiProviderStore-into-AppContainer; WI-5/6 VM state+prefetch+single-flight; WI-7a Compose UI; WI-7b conditional EPUB DOM-injection adapter; WI-AIP Variant-A in-bilingual AI Providers sheet [reuse #118 AiProviderListScreen/EditSheet verbatim, pop-back-on-Save]; WI-8 TXT/MD host; WI-9 entry wiring+acceptance). **Style DESCOPED v1** (user decision 2026-07-12): keep provider/model/granularity, drop the bilingual Style control (box D flips done for provider/model/granularity + a Style-descope follow-up amendment; a Style+Granularity single sheet is not depicted anywhere = the one open design gate). Design authority (landed, rule 51): vreader-bilingual.jsx (granularity-only setup sheet) + vreader-reader.jsx pill + vreader-more.jsx toggle. **Gate-2 round-2 = REDESIGN resolved (v3): TXT/MD document-global segment ranges (H1); EPUB translatePreSegmented + count-keyed cache + direct-block prefetch (H2); #136 spun out + Style descoped (H3); WI-0 go/no-go + race contract (M1); EPUB DOM-injection NOT Compose body (M2); DI/factory WI reordered (M3); Room 8->9 MIGRATION_8_9 (M4). Gate-2 round-3 = block-recommended (0 Critical; H1 TXT/MD final-chunk drop [offsetForChunk clamps the last chunk -> empty span; fix endExclusive = if(i+1<chunkCount) offsetForChunk(i+1) else text.length + half-open ranges + EOF tests]; H2 per-segment Text nodes break the live one-TextLayoutResult-per-chunk selection/highlight model -> needs an offset-preserving render/layout design + enabled-mode selection/highlight/read-aloud/annotation/MD tests; M1 EPUB direct-block flow not wired e2e; M2 cancellation must handle both native + typed Cancelled + a per-unit single-flight registry; M3 AiRequest.model needs the live ifBlank{kind.defaultModel} fallback). v4 rewrite (13 WIs) resolving those + folding in the designed Variant-A AI-config path (#136 CLOSED). NEW rule-51 design gate: sentence-granularity interlinear RENDER is undepicted (only paragraph interlinear is designed in vreader-bilingual.jsx BilingualPageContent) -> v1 ships the paragraph render + the granularity control, Sentence selection falls back to paragraph render (cache still granularity-keyed); a future sentence-render needs its own design bundle. Gate-2 round-4 pending.** GH: #1923 |

exec
/bin/zsh -lc "nl -ba android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt | sed -n '1,180p' && nl -ba android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt | sed -n '205,275p;345,490p;600,635p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
     1	// Purpose: feature #124 WI-3 — drives the TXT custom selection. Each visible chunk registers its
     2	// TextLayoutResult + LayoutCoordinates; the controller converts a pointer (LazyColumn-local) → window
     3	// space → the hit chunk's local space → rendered offset → SOURCE offset (TxtSourceOffsets), and resolves
     4	// a word boundary at long-press. Selection is a SOURCE Utf16Range; the in-progress range renders as an
     5	// accent wash. Kept off the Activity so the geometry is isolated; the Activity wires the gesture +
     6	// popover + persistence.
     7	package com.vreader.app.reader
     8	
     9	import androidx.compose.runtime.Stable
    10	import androidx.compose.ui.geometry.Offset
    11	import androidx.compose.ui.layout.LayoutCoordinates
    12	import androidx.compose.ui.layout.boundsInWindow
    13	import androidx.compose.ui.text.TextLayoutResult
    14	import kotlinx.coroutines.flow.MutableStateFlow
    15	import kotlinx.coroutines.flow.StateFlow
    16	import kotlinx.coroutines.flow.asStateFlow
    17	
    18	@Stable
    19	class TxtSelectionController(
    20	    private val doc: TxtDocument,
    21	    // feature #125 — format-aware rendered↔source bridge. The chunk TextLayoutResults are built from the
    22	    // RENDERED text, so getOffsetForPosition/getWordBoundary/getCursorRect speak rendered coords; the
    23	    // mapper converts them to/from the SOURCE coords selections + highlights are stored in. TXT = identity.
    24	    private val mapper: ChunkTextMapper,
    25	) {
    26	    private data class ChunkInfo(val layout: TextLayoutResult, val coords: LayoutCoordinates)
    27	    /** A resolved hit: the chunk index/info + the chunk-local rendered offset + the absolute source offset. */
    28	    private data class Hit(val chunkIndex: Int, val info: ChunkInfo, val rendered: Int, val source: Int)
    29	    private val chunks = HashMap<Int, ChunkInfo>()
    30	    private var lazyCoords: LayoutCoordinates? = null
    31	    // the initial word selected at long-press — the FIXED anchor; drags extend relative to it (never drop it).
    32	    private var anchorRange: Utf16Range? = null
    33	
    34	    private val _selection = MutableStateFlow<Utf16Range?>(null)
    35	    val selection: StateFlow<Utf16Range?> = _selection.asStateFlow()
    36	
    37	    fun setLazyCoords(coords: LayoutCoordinates) { lazyCoords = coords }
    38	    fun registerChunk(index: Int, layout: TextLayoutResult, coords: LayoutCoordinates) {
    39	        chunks[index] = ChunkInfo(layout, coords)
    40	    }
    41	    fun unregisterChunk(index: Int) { chunks.remove(index) }
    42	
    43	    /** Pointer (LazyColumn-local) → the hit chunk + chunk-local rendered offset + source offset. The hit
    44	     *  chunk is used for BOTH the source mapping AND word-boundary lookup (avoids a chunk-boundary shift).
    45	     *  [allowNearest]: for a DRAG, fall back to the nearest chunk when the point is past the text; for a
    46	     *  TAP-to-edit, require the point to actually be inside a text chunk (else a margin tap could edit). */
    47	    private fun hitAt(localPoint: Offset, allowNearest: Boolean = true): Hit? {
    48	        val lz = lazyCoords ?: return null
    49	        if (chunks.isEmpty()) return null
    50	        val windowPoint = lz.localToWindow(localPoint)
    51	        val hit = chunks.entries.firstOrNull { it.value.coords.boundsInWindow().contains(windowPoint) }
    52	            ?: (if (allowNearest) chunks.entries.minByOrNull { verticalDistance(it.value.coords.boundsInWindow(), windowPoint) } else null)
    53	            ?: return null
    54	        val chunkLocal = hit.value.coords.windowToLocal(windowPoint)
    55	        val rendered = hit.value.layout.getOffsetForPosition(chunkLocal).coerceIn(0, hit.value.layout.layoutInput.text.length)
    56	        // rendered cursor → chunk-local source (empty rendered range maps to the source edge) → global source.
    57	        val localSource = mapper.renderedRangeToSource(hit.key, Utf16Range(rendered, rendered)).startInclusive
    58	        return Hit(hit.key, hit.value, rendered, doc.offsetForChunk(hit.key) + localSource)
    59	    }
    60	
    61	    /** Long-press: select the word under [localPoint] (word boundary in the HIT chunk, mapped to source). */
    62	    fun beginAt(localPoint: Offset) {
    63	        val hit = hitAt(localPoint) ?: return
    64	        val word = hit.info.layout.getWordBoundary(hit.rendered)   // RENDERED coords in the hit chunk
    65	        val base = doc.offsetForChunk(hit.chunkIndex)
    66	        // rendered word → chunk-local source span → global source (markers stripped for MD).
    67	        val src = mapper.renderedRangeToSource(hit.chunkIndex, Utf16Range(word.start, word.end))
    68	        val start = base + src.startInclusive
    69	        val end = base + src.endExclusive
    70	        val range = if (end > start) Utf16Range(start, end) else Utf16Range(hit.source, (hit.source + 1).coerceAtMost(doc.text.length))
    71	        anchorRange = range
    72	        _selection.value = range
    73	    }
    74	
    75	    /** Drag: extend relative to the FIXED [anchorRange] (the initial word) — extending before it grows the
    76	     *  start, after it grows the end, inside it keeps the word. The anchor word is never dropped. */
    77	    fun extendTo(localPoint: Offset) {
    78	        val anchor = anchorRange ?: return
    79	        val off = (hitAt(localPoint) ?: return).source.coerceIn(0, doc.text.length)
    80	        _selection.value = when {
    81	            off <= anchor.startInclusive -> Utf16Range(off, anchor.endExclusive)
    82	            off >= anchor.endExclusive -> Utf16Range(anchor.startInclusive, off)
    83	            else -> anchor
    84	        }
    85	    }
    86	
    87	    fun clear() { _selection.value = null; anchorRange = null }
    88	
    89	    /** The current selection range, or null. */
    90	    fun currentRange(): Utf16Range? = _selection.value
    91	
    92	    /** Resolve a tap (LazyColumn-local) to a SOURCE offset, for hit-testing an existing highlight. Strict
    93	     *  (no nearest-chunk fallback) so a tap in the margin/blank space doesn't edit a nearby highlight. */
    94	    fun resolveSourceOffset(localPoint: Offset): Int? = hitAt(localPoint, allowNearest = false)?.source
    95	
    96	    /** Convert a LazyColumn-local point to window coords (to anchor the edit popover at a tap). */
    97	    fun toWindow(localPoint: Offset): Offset? = lazyCoords?.localToWindow(localPoint)
    98	
    99	    /** Whether the current selection is a persist-worthy range (in-bounds, non-empty, surrogate-safe). */
   100	    fun isCurrentSelectionValid(): Boolean = _selection.value?.let { TxtSelection.isValid(it, doc.text) } ?: false
   101	
   102	    /** The VISIBLE (rendered) substring of the current selection — for the popover / copy / share / UI.
   103	     *  For TXT this equals the source; for MD it's the marker-stripped rendered text the user sees. */
   104	    fun selectedVisibleText(): String? {
   105	        val r = _selection.value ?: return null
   106	        if (r.isEmpty || r.endExclusive > doc.text.length) return null
   107	        val sb = StringBuilder()
   108	        for (cr in TxtSourceOffsets.chunkRanges(doc, r)) {
   109	            sb.append(mapper.visibleText(cr.chunkIndex, mapper.sourceRangeToRendered(cr.chunkIndex, cr.local)))
   110	        }
   111	        return sb.toString().ifEmpty { null }
   112	    }
   113	
   114	    /** The SOURCE (markdown/raw) substring of the current selection — for the locator textQuote + anchor. */
   115	    fun selectedSourceText(): String? {
   116	        val r = _selection.value ?: return null
   117	        if (r.isEmpty || r.endExclusive > doc.text.length) return null
   118	        return doc.text.substring(r.startInclusive, r.endExclusive)
   119	    }
   120	
   121	    /** The in-progress selection projected onto [chunkIndex] as a chunk-local RENDERED range, for the
   122	     *  accent wash (`getPathForRange` speaks rendered coords). Source→rendered via the mapper (MD). */
   123	    fun selectionForChunk(chunkIndex: Int): Utf16Range? {
   124	        val r = _selection.value ?: return null
   125	        val localSource = TxtSourceOffsets.chunkRanges(doc, r).firstOrNull { it.chunkIndex == chunkIndex }?.local ?: return null
   126	        return mapper.sourceRangeToRendered(chunkIndex, localSource)
   127	    }
   128	
   129	    /** The window-space point just below the selection's end, to anchor the popover. */
   130	    fun selectionEndAnchorWindow(): Offset? {
   131	        val r = _selection.value ?: return null
   132	        val endChunk = doc.chunkForOffset((r.endExclusive - 1).coerceAtLeast(0)).coerceIn(0, doc.chunkCount - 1)
   133	        val info = chunks[endChunk] ?: return null
   134	        val base = doc.offsetForChunk(endChunk)
   135	        // source end → chunk-local source → rendered cursor (end-affinity) for getCursorRect.
   136	        val localSourceEnd = (r.endExclusive - base).coerceAtLeast(0)
   137	        val renderedEnd = mapper.renderedCursorForSourceEnd(endChunk, localSourceEnd).coerceIn(0, info.layout.layoutInput.text.length)
   138	        val rect = info.layout.getCursorRect(renderedEnd)
   139	        return info.coords.localToWindow(Offset(rect.left, rect.bottom))
   140	    }
   141	
   142	    private fun verticalDistance(bounds: androidx.compose.ui.geometry.Rect, p: Offset): Float = when {
   143	        p.y < bounds.top -> bounds.top - p.y
   144	        p.y > bounds.bottom -> p.y - bounds.bottom
   145	        else -> 0f
   146	    }
   147	}
   205	                    }
   206	                }
   207	                // feature #129 — the live Display settings (theme/font/size/spacing/margin). NULL until
   208	                // the DataStore's first emission; the reader body is withheld until then (Gate-4 Medium:
   209	                // rendering defaults first would flash the wrong theme/typography for a user with stored
   210	                // non-default settings). The empty loading scaffold is the only pre-emission surface.
   211	                val settingsOrNull by container.readerSettingsStore.settings
   212	                    .collectAsStateWithLifecycle(initialValue = null)
   213	                val gated = if (settingsOrNull == null && state !is TxtUiState.Failed) TxtUiState.Loading else state
   214	                when (val s = gated) {
   215	                    is TxtUiState.Failed -> LaunchedEffect(Unit) { finish() }
   216	                    is TxtUiState.Loading -> TxtLoadingScaffold((settingsOrNull ?: ReaderSettings()).theme)
   217	                    is TxtUiState.Loaded -> {
   218	                        // non-null by the gate above (Loaded is unreachable pre-emission).
   219	                        val displaySettings = checkNotNull(settingsOrNull)
   220	                        val listState = rememberLazyListState(initialFirstVisibleItemIndex = s.initialIndex)
   221	                        // onStop flush — captures the live list state + book/document.
   222	                        SideEffect {
   223	                            flushPosition = { savePosition(s.book, s.document, listState.firstVisibleItemIndex) }
   224	                        }
   225	                        // Debounced steady-state save as the user scrolls.
   226	                        LaunchedEffect(listState, s.document) {
   227	                            snapshotFlow { listState.firstVisibleItemIndex }
   228	                                .drop(1)
   229	                                .debounce(1_000)
   230	                                .collect { savePosition(s.book, s.document, it) }
   231	                        }
   232	                        // feature #121 — read-aloud. The VM drives the designed control bar; the spoken
   233	                        // sentence is washed + auto-scrolled (TXT). Chunking is LAZY + off-main (only
   234	                        // on Read aloud) so a large book never scans the whole text on composition.
   235	                        val ttsVm: TtsViewModel = viewModel(factory = viewModelFactory {
   236	                            initializer { TtsViewModel(AndroidTtsEngine(applicationContext)) }
   237	                        })
   238	                        val tts by ttsVm.state.collectAsStateWithLifecycle()
   239	                        val ttsScope = rememberCoroutineScope()
   240	                        LaunchedEffect(ttsVm) { ttsVm.intents.collect { launchTtsIntent(it) } }
   241	                        // pause read-aloud when the reader is backgrounded (no MediaSession by design —
   242	                        // plan §OOS); the engine is shut down on Activity finish via the VM's onCleared.
   243	                        val lifecycleOwner = LocalLifecycleOwner.current
   244	                        DisposableEffect(lifecycleOwner) {
   245	                            // guard against ON_STOP firing on a rotation (config change) — the VM is
   246	                            // retained across rotation, so don't pause when we're just reconfiguring.
   247	                            val obs = LifecycleEventObserver { _, e -> if (e == Lifecycle.Event.ON_STOP && !isChangingConfigurations) ttsVm.pause() }
   248	                            lifecycleOwner.lifecycle.addObserver(obs)
   249	                            onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
   250	                        }
   251	                        val active = tts.phase != TtsPhase.idle
   252	                        val spokenChunk = if (tts.phase == TtsPhase.speaking) s.document.chunkForOffset(tts.charStart) else -1
   253	                        // auto-scroll ONLY when the spoken chunk is off-screen — so a small manual scroll
   254	                        // while listening isn't fought on every sentence.
   255	                        LaunchedEffect(spokenChunk) {
   256	                            if (spokenChunk >= 0 && listState.layoutInfo.visibleItemsInfo.none { it.index == spokenChunk }) {
   257	                                runCatching { listState.animateScrollToItem(spokenChunk) }
   258	                            }
   259	                        }
   260	                        var showSpeed by remember { mutableStateOf(false) }
   261	                        var showVoice by remember { mutableStateOf(false) }
   262	                        var starting by remember { mutableStateOf(false) }   // guards double-tap → double-chunk
   263	                        // snapshot the voice options once when the sheet opens (not every recomposition).
   264	                        val voiceList = remember(showVoice) { if (showVoice) ttsVm.voiceListState() else com.vreader.app.tts.TtsVoiceListState() }
   265	
   266	                        // feature #122 — reading-stats: track this session (the process-singleton tracker
   267	                        // survives rotation) + show the auto-fading session pill.
   268	                        val tracker = container.readingTimeTracker
   269	                        val bookKey = s.book.fingerprintKey
   270	                        val sessionSeconds by tracker.sessionSeconds.collectAsStateWithLifecycle()
   271	
   272	                        // feature #124/#125 — stored highlights → per-chunk washes. Enabled for TXT AND MD
   273	                        // (#125 added the MarkdownChunkTextMapper source-offset map, so MD is no longer
   274	                        // render-only). The mapper is the single rendered↔source bridge + render owner,
   275	                        // shared by the wash, the selection controller, and the body.
   345	                        // snippet around the stored char offset — the host owns the decoded text). The current
   346	                        // position is the top-visible chunk's char offset → a plain canonical Locator.
   347	                        val previewProvider = remember(s.document) { txtBookmarkPreviewProvider(s.document) }
   348	                        val dateRenderer = remember { bookmarkDateRenderer() }
   349	                        val currentCanonical = remember(s.book) {
   350	                            { off: Int -> txtBookmarkLocator(s.book, off) }
   351	                        }
   352	                        val bookmarkRecords by remember(bookKey) { container.annotationsRepository.bookmarks(bookKey) }
   353	                            .collectAsStateWithLifecycle(emptyList())
   354	                        val bookmarkRows = remember(bookmarkRecords, s.book) {
   355	                            bookmarkRowItems(bookmarkRecords, s.book.originalFormat, tocIndex = null, previewProvider = previewProvider, dateRenderer = dateRenderer)
   356	                        }
   357	                        // The live top-visible offset → canonical (recomputed on scroll; the toggle/presence read it).
   358	                        val liveOffset = s.document.offsetForChunk(listState.firstVisibleItemIndex)
   359	                        val liveCanonical = remember(s.book, liveOffset) { txtBookmarkLocator(s.book, liveOffset) }
   360	                        val isBookmarked by produceState(false, liveCanonical, bookmarkRecords) {
   361	                            value = runCatching { container.annotationsRepository.isBookmarked(bookKey, liveCanonical) }.getOrDefault(false)
   362	                        }
   363	
   364	                        // feature #133 WI-10 — the in-book search VM (ONE per reader session): built from the
   365	                        // ALREADY-decoded reader text so a search never re-reads the file, scoped to a
   366	                        // composition-lifetime scope so its collectors stop when the reader leaves. onDispose
   367	                        // runs the VM's documented lifecycle (closeAllEpubCursors via onCleared) — TXT has no
   368	                        // EPUB cursors, but the contract holds uniformly. Hidden only when the index-state gate
   369	                        // reports Unsupported (a TXT/MD book skipped as unsupported); otherwise the Search icon
   370	                        // is present.
   371	                        val searchScope = rememberCoroutineScope()
   372	                        val inBookSearchVm = remember(bookKey, s.book.originalFormat) {
   373	                            container.inBookSearchViewModel(
   374	                                bookKey = bookKey,
   375	                                format = s.book.originalFormat,
   376	                                decodedText = s.document.text,
   377	                                contentSHA256 = s.book.contentSHA256,
   378	                                fileByteCount = s.book.fileByteCount,
   379	                                coroutineScope = searchScope,
   380	                            )
   381	                        }
   382	                        DisposableEffect(inBookSearchVm) { onDispose { inBookSearchVm.onCleared() } }
   383	                        val inBookSearchState by inBookSearchVm.state.collectAsStateWithLifecycle()
   384	                        var showSearch by remember(bookKey) { mutableStateOf(false) }
   385	
   386	                        TxtReaderChrome(
   387	                            theme = displaySettings.theme,
   388	                            title = s.title,
   389	                            chromeState = chromeState,
   390	                            annotations = annotationsSnapshot,
   391	                            onBack = ::finish,
   392	                            bookDetails = bookDetails,
   393	                            onShareBook = { com.vreader.app.reader.share.shareBook(this@TxtReaderActivity, s.book) },
   394	                            onCopyFingerprint = { copyFingerprint(it) },
   395	                            // feature #135 WI-7 — the top-bar bookmark toggle + Bookmarks-tab rows + TXT jump.
   396	                            isCurrentBookmarked = isBookmarked,
   397	                            onToggleBookmark = {
   398	                                container.appScope.launch {
   399	                                    runCatching { container.annotationsRepository.toggleBookmark(bookKey, title = null, locator = liveCanonical) }
   400	                                }
   401	                            },
   402	                            currentLocator = liveCanonical,
   403	                            bookmarks = bookmarkRows,
   404	                            // TXT jump: scroll to the bookmark's char offset via the existing chunk scroll seam
   405	                            // (the same path resume + the annotation jump use). Out-of-range → Failed (sheet stays open).
   406	                            onJumpBookmark = { record ->
   407	                                val target = txtBookmarkScrollTarget(record.locator.charOffsetUTF16, s.document.text.length)
   408	                                if (target == null) {
   409	                                    JumpResult.Failed
   410	                                } else {
   411	                                    ttsScope.launch { listState.scrollToItem(s.document.chunkForOffset(target)) }
   412	                                    JumpResult.Succeeded
   413	                                }
   414	                            },
   415	                            // TXT/MD jump: scroll to the annotation's UTF-16 offset via the existing chunk
   416	                            // scroll seam (the same path used by resume + scrubber).
   417	                            onJumpToAnnotation = { item ->
   418	                                ttsScope.launch {
   419	                                    val target = annotationScrollOffset(item)
   420	                                        .coerceIn(0, (s.document.text.length - 1).coerceAtLeast(0))
   421	                                    listState.scrollToItem(s.document.chunkForOffset(target))
   422	                                }
   423	                            },
   424	                            onShareAnnotations = { shareAnnotations(annotationsSnapshot) },
   425	                            // feature #133 WI-10 — the Search entry + sheet. The icon is hidden only when the
   426	                            // index-state gate says Unsupported (a skipped-unsupported TXT/MD book — no dead
   427	                            // control); otherwise tapping it opens the sheet for THIS book.
   428	                            onOpenSearch = if (inBookSearchState.hidesSearchEntry) null else { { showSearch = true } },
   429	                            searchSheet = if (!showSearch) null else {
   430	                                {
   431	                                    InBookSearchSheet(
   432	                                        theme = displaySettings.theme,
   433	                                        bookTitle = s.title,
   434	                                        state = inBookSearchState,
   435	                                        query = inBookSearchState.query,
   436	                                        onQueryChange = inBookSearchVm::onQueryChange,
   437	                                        onPickRecent = inBookSearchVm::onPickRecent,
   438	                                        // Resolve the tapped hit's canonical charOffsetUTF16 → scroll via the
   439	                                        // EXISTING chunk-scroll seam (the same path resume / annotation / bookmark
   440	                                        // jumps use). The WI-9 sheet's onJump is NON-suspend (JumpResult returns
   441	                                        // synchronously), so — like the sibling annotation/bookmark jumps — the
   442	                                        // range is validated UP FRONT (out-of-range/null → Failed, sheet stays
   443	                                        // open, rule 51) and a valid target returns Succeeded optimistically while
   444	                                        // the actual scroll runs on ttsScope; the launch is runCatching-guarded so
   445	                                        // a scroll cancelled during teardown can't crash. The recent is committed
   446	                                        // only on a valid result-open (the VM's commitSearch contract).
   447	                                        onJump = { hit ->
   448	                                            val off = hit.canonicalLocator?.charOffsetUTF16
   449	                                            val target = txtBookmarkScrollTarget(off, s.document.text.length)
   450	                                            if (target == null) {
   451	                                                JumpResult.Failed
   452	                                            } else {
   453	                                                inBookSearchVm.commitSearch()
   454	                                                ttsScope.launch { runCatching { listState.scrollToItem(s.document.chunkForOffset(target)) } }
   455	                                                JumpResult.Succeeded
   456	                                            }
   457	                                        },
   458	                                        onLoadMore = inBookSearchVm::loadMore,
   459	                                        onDismiss = { inBookSearchVm.onDismiss(); showSearch = false },
   460	                                    )
   461	                                }
   462	                            },
   463	                            bottomBar = { (openContents, openNotes) ->
   464	                                if (active) TtsControlBar(
   465	                                    tts,
   466	                                    onPlayPause = { if (tts.phase == TtsPhase.speaking) ttsVm.pause() else ttsVm.play() },
   467	                                    onPrevious = ttsVm::previous, onNext = ttsVm::next, onStop = ttsVm::stop,
   468	                                    onSpeed = { showSpeed = true }, onVoice = { showVoice = true },
   469	                                    onInstallVoice = ttsVm::installVoiceData, onSystemTts = ttsVm::openSystemTts,
   470	                                ) else ReaderBottomChrome(
   471	                                    theme = displaySettings.theme,
   472	                                    progress = TxtProgress.fraction(
   473	                                        s.document.offsetForChunk(listState.firstVisibleItemIndex),
   474	                                        s.document.text.length,
   475	                                    ),
   476	                                    displayPage = 0, totalPages = 0,   // TXT/MD scroll-only — no page labels
   477	                                    onScrub = { f ->
   478	                                        ttsScope.launch {
   479	                                            val target = (f * s.document.text.length).toInt()
   480	                                                .coerceIn(0, (s.document.text.length - 1).coerceAtLeast(0))
   481	                                            listState.scrollToItem(s.document.chunkForOffset(target))
   482	                                        }
   483	                                    },
   484	                                    onOpenDisplay = { showDisplaySheet = true },
   485	                                    // #132 WI-6: the scaffold hands the Contents/Notes open callbacks in.
   486	                                    // TXT/MD has no TOC → openContents is null (Contents control hidden);
   487	                                    // openNotes opens the review sheet.
   488	                                    onOpenContents = openContents,
   489	                                    onOpenNotes = openNotes,
   490	                                    extraSlot = {
   600	        val path = book?.localFilePath ?: return TxtUiState.Failed
   601	        if (book == null) return TxtUiState.Failed
   602	        val decoded = TxtDecoder.decode(File(path))
   603	        val document = TxtDocument.of(decoded.text)
   604	        container.repository.markOpened(key, System.currentTimeMillis())
   605	        val initial = computeInitialIndex(key, document)
   606	        return TxtUiState.Loaded(book.title, document, book, initial)
   607	    }
   608	
   609	    /** Restore: the saved legacy locator's charOffsetUTF16 → the chunk containing it. */
   610	    private suspend fun computeInitialIndex(key: String, document: TxtDocument): Int {
   611	        // In-memory cache first — a fast rotation / reopen sees the latest offset even
   612	        // before the prior instance's async Room flush commits. Falls to durable Room.
   613	        container.cachedOffset(key)?.let { return document.chunkForOffset(it) }
   614	        val saved = container.repository.loadPosition(key) ?: return 0
   615	        // ResumeResolver/ResumeTarget are in this package. A TXT position is a legacy
   616	        // (non-Readium) envelope → Canonical; its charOffsetUTF16 is the anchor.
   617	        val offset = (ResumeResolver.resolve(saved) as? ResumeTarget.Canonical)
   618	            ?.locator?.charOffsetUTF16 ?: return 0
   619	        return document.chunkForOffset(offset)
   620	    }
   621	
   622	    /** Enqueue the top-visible chunk's char offset; the lone writer persists it (latest-wins). */
   623	    private fun savePosition(book: Book, document: TxtDocument, topIndex: Int) {
   624	        val offset = document.offsetForChunk(topIndex)
   625	        // Cache synchronously so an immediate reopen/rotation reads the latest position
   626	        // even before the async Room write below commits.
   627	        container.cacheOffset(book.fingerprintKey, offset)
   628	        saveRequests.trySend(PendingSave(book, offset))
   629	    }
   630	
   631	    /** Launch a system intent for a read-aloud one-shot, guarded by resolveActivity with fallbacks
   632	     *  (there is no public Settings.ACTION_TTS_SETTINGS — fall back to accessibility / settings). */
   633	    private fun launchTtsIntent(i: TtsIntent) {
   634	        val candidates = when (i) {
   635	            TtsIntent.InstallVoiceData -> listOf(android.content.Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA))

exec
/bin/zsh -lc "nl -ba vreader/Services/AI/ChapterTranslationService.swift | sed -n '330,385p' && nl -ba vreader/ViewModels/BilingualReadingViewModel.swift | sed -n '120,185p' && nl -ba vreader/ViewModels/BilingualReadingViewModel+Prefetch.swift | sed -n '1,260p' && rg -n \"Deps:\\[feat:#132, feat:#134\\]|WI-AIP|WI-4b|setActive\\(savedId\\)|savedId|pop\" dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md" in /Users/ll/workspace/vreader
 succeeded in 0ms:
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
   120	            name: .readerBilingualPrefetchDidChange, object: nil,
   121	            userInfo: [
   122	                "fingerprintKey": bookFingerprintKey,
   123	                "inFlightUnits": newSet
   124	            ])
   125	    }
   126	
   127	    /// Monotonic guard; bumps on disable / book-change / unit-change. A
   128	    /// prefetch `Task` captures the epoch at launch and discards its result
   129	    /// if the epoch has since moved.
   130	    var epoch: Int = 0
   131	
   132	    /// Monotonic per-`handlePositionChange`-call counter. The trigger captures
   133	    /// it at entry and re-checks it after the `unit(after:)` suspension — only
   134	    /// the LATEST request proceeds, so two position changes interleaving
   135	    /// across the suspension cannot let the older one win.
   136	    var triggerRequestSeq: Int = 0
   137	
   138	    /// In-flight prefetch tasks keyed by unit, so a reset can cancel them, a
   139	    /// completed task removes its own entry (no unbounded growth), and a test
   140	    /// can await quiescence.
   141	    var prefetchTasks: [TranslationUnitID: Task<Void, Never>] = [:]
   142	
   143	    /// Cancelled-but-still-unwinding prefetch tasks, kept only so the
   144	    /// test-only `awaitPrefetchForTesting` can fully drain them after a
   145	    /// disable / unit-change cancels them out of `prefetchTasks`.
   146	    var cancelledPrefetchTasks: [Task<Void, Never>] = []
   147	
   148	    init(bookFingerprintKey: String, perBookBaseURL: URL) {
   149	        self.bookFingerprintKey = bookFingerprintKey
   150	        self.perBookBaseURL = perBookBaseURL
   151	
   152	        let override = PerBookSettingsStore.settings(
   153	            for: bookFingerprintKey, baseURL: perBookBaseURL)
   154	        self.isEnabled = override?.bilingualEnabled ?? false
   155	        self.targetLanguage = override?.bilingualTargetLanguage ?? Self.defaultTargetLanguage
   156	        self.granularity = TranslationGranularity(
   157	            rawValue: override?.bilingualGranularity ?? "") ?? .paragraph
   158	    }
   159	
   160	    // MARK: - Toggle
   161	
   162	    /// Enables / disables bilingual mode for this book and persists the change.
   163	    /// The first time it is enabled the setup sheet is raised; disabling clears
   164	    /// the per-unit translation cache and resets the prefetch trigger state.
   165	    func setEnabled(_ enabled: Bool) {
   166	        guard enabled != isEnabled else { return }
   167	        if enabled && !hasBeenConfigured {
   168	            needsSetupSheet = true
   169	        }
   170	        isEnabled = enabled
   171	        if !enabled {
   172	            resetTriggerState()
   173	        }
   174	        persist()
   175	        postDidChange()
   176	    }
   177	
   178	    /// Sets the target language and persists it.
   179	    func setTargetLanguage(_ language: String) {
   180	        guard language != targetLanguage else { return }
   181	        targetLanguage = language
   182	        // A language change invalidates the cached translations + the
   183	        // prefetch trigger state — re-fetch fresh for the new language.
   184	        resetTriggerState()
   185	        persist()
     1	// Purpose: Feature #56 WI-7b — the behavioral layer of
     2	// `BilingualReadingViewModel`, split out of the main file to keep each under
     3	// the ~300-line budget (rule 50 §9).
     4	//
     5	// This extension owns the unit-aware prefetch trigger: `handlePositionChange`
     6	// derives the current `TranslationUnitID` from a position `Locator` via the
     7	// injected `ChapterTextProviding`, dedupes against `lastTriggerUnit`, and on a
     8	// real unit change bumps the epoch, cancels the prior epoch's in-flight
     9	// prefetches, and prefetches the current + next unit through the
    10	// `ChapterPrefetching` seam. A prefetch `Task` captures its epoch; a result
    11	// from a superseded epoch is discarded. An offline cache-miss is recorded in
    12	// `unavailableUnits` (the silent-source-fallback — plan Decision 2).
    13	//
    14	// Key decisions (Codex audit round 1):
    15	// - `handlePositionChange` resolves the current + next unit **before**
    16	//   mutating `epoch` / `lastTriggerUnit`, so a disable / unit-change during
    17	//   the `unit(after:)` suspension cannot let a stale invocation start
    18	//   superseded-epoch prefetches.
    19	// - In-flight prefetch `Task`s are tracked in a `[TranslationUnitID: Task]`
    20	//   dictionary so `finishPrefetch` removes the completed entry (no unbounded
    21	//   growth) and `awaitPrefetchForTesting` awaits a stable snapshot.
    22	// - A transient provider failure clears `lastTriggerUnit` when it names the
    23	//   failed unit, so a later position change inside the same unit retries.
    24	//
    25	// @coordinates-with: BilingualReadingViewModel.swift, ChapterTextProviding.swift,
    26	//   ChapterPrefetching.swift, ReaderNotifications.swift,
    27	//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-7b)
    28	
    29	import Foundation
    30	
    31	extension BilingualReadingViewModel {
    32	
    33	    // MARK: - Collaborators
    34	
    35	    /// Attaches the format adapter that resolves `Locator → TranslationUnitID`.
    36	    /// The format host calls this once after constructing the view model.
    37	    func attachProvider(_ provider: any ChapterTextProviding) {
    38	        textProvider = provider
    39	    }
    40	
    41	    /// Attaches the translation-prefetch seam. The format host calls this once
    42	    /// after constructing the view model.
    43	    func attachPrefetcher(_ prefetcher: any ChapterPrefetching) {
    44	        self.prefetcher = prefetcher
    45	    }
    46	
    47	    // MARK: - Prefetch trigger
    48	
    49	    /// Whether a unit's translation is unavailable (offline cache-miss).
    50	    func isUnavailable(_ unit: TranslationUnitID) -> Bool {
    51	        unavailableUnits.contains(unit)
    52	    }
    53	
    54	    /// Driven by `.readerPositionDidChange`. Derives the current unit from the
    55	    /// position `Locator`; if the unit changed since the last trigger, bumps
    56	    /// the epoch, cancels any in-flight prefetch, and prefetches the current +
    57	    /// next unit. Repeated calls inside the same unit are no-ops.
    58	    func handlePositionChange(_ locator: Locator) async {
    59	        guard isEnabled, let provider = textProvider, prefetcher != nil else { return }
    60	        // Claim a monotonic request token — only the latest request proceeds.
    61	        triggerRequestSeq += 1
    62	        let requestToken = triggerRequestSeq
    63	
    64	        guard let currentUnit = await provider.unit(containing: locator) else { return }
    65	        // After the `unit(containing:)` suspension: bail if a newer request
    66	        // has been claimed, or the VM was disabled.
    67	        guard isEnabled, requestToken == triggerRequestSeq else { return }
    68	        // Dedupe: the position is still inside the unit the trigger last
    69	        // acted on — nothing to do.
    70	        guard currentUnit != lastTriggerUnit else { return }
    71	
    72	        // Resolve the next unit BEFORE mutating any trigger state — this call
    73	        // suspends, and a disable / another `handlePositionChange` during the
    74	        // suspension must not let this (now stale) invocation start prefetches.
    75	        let nextUnit = await provider.unit(after: currentUnit)
    76	
    77	        // Re-validate after the suspension: the VM must still be enabled AND
    78	        // this must still be the latest request. The request-token check
    79	        // (not just `currentUnit != lastTriggerUnit`) is what defeats the
    80	        // interleaving race — a newer request for a *different* unit bumped
    81	        // `triggerRequestSeq`, so the older invocation stops here even though
    82	        // its `currentUnit` differs from the newer `lastTriggerUnit`.
    83	        guard isEnabled, requestToken == triggerRequestSeq else { return }
    84	
    85	        // A real unit change — bump the epoch and cancel the prior epoch's
    86	        // in-flight prefetches before starting the new ones.
    87	        epoch += 1
    88	        cancelInFlightPrefetches()
    89	        lastTriggerUnit = currentUnit
    90	
    91	        let currentEpoch = epoch
    92	        var targets: [TranslationUnitID] = [currentUnit]
    93	        if let nextUnit { targets.append(nextUnit) }
    94	        for unit in targets {
    95	            startPrefetch(unit: unit, epoch: currentEpoch)
    96	        }
    97	    }
    98	
    99	    /// Test-only: awaits every prefetch `Task` — both still-registered and
   100	    /// already-cancelled — so a test can assert deterministically after
   101	    /// `handlePositionChange`.
   102	    func awaitPrefetchForTesting() async {
   103	        while !prefetchTasks.isEmpty || !cancelledPrefetchTasks.isEmpty {
   104	            let active = Array(prefetchTasks.values)
   105	            let cancelled = cancelledPrefetchTasks
   106	            cancelledPrefetchTasks.removeAll()
   107	            for task in cancelled { await task.value }
   108	            for task in active { await task.value }
   109	            // Drop finished+accounted active entries; loop if a new task
   110	            // appeared (or a new cancellation occurred) while awaiting.
   111	            for unit in prefetchTasks.keys where !inFlightUnits.contains(unit) {
   112	                prefetchTasks.removeValue(forKey: unit)
   113	            }
   114	        }
   115	    }
   116	
   117	    // MARK: - Unit-scoped prefetch (Feature #71 WI-7)
   118	
   119	    /// Prefetch ONE explicit unit's translation without touching the
   120	    /// visible-locator trigger state (`lastTriggerUnit` / `triggerRequestSeq`).
   121	    ///
   122	    /// Feature #71 WI-7 (Gate-4 round-2 HIGH 1): continuous-scroll EPUB stitches
   123	    /// multiple chapter sections into one document; an adjacent section that
   124	    /// materializes is frequently OFF-SCREEN relative to the visible locator
   125	    /// (the ±1 initial fill, lazy append/prepend). The whole-book
   126	    /// `handlePositionChange` trigger resolves its prefetch targets from the
   127	    /// CURRENT visible locator and dedupes against `lastTriggerUnit`, so reusing
   128	    /// it for an off-screen section would either no-op (wrong unit) or clobber
   129	    /// the dedupe anchor. This seam prefetches exactly the named unit through
   130	    /// the same `startPrefetch` internals (cache-guarded, in-flight-guarded,
   131	    /// epoch-stamped) so a section-materialize can warm its OWN unit's
   132	    /// translation independent of where the reader is looking.
   133	    ///
   134	    /// No-op when bilingual is disabled, no prefetcher is attached, or the unit
   135	    /// is already cached / already in flight (`startPrefetch` guards the latter
   136	    /// two). Does NOT mark the unit unavailable on its own — the existing
   137	    /// `finishPrefetch` outcome handling applies.
   138	    func prefetchUnitIfNeeded(_ unit: TranslationUnitID) {
   139	        guard isEnabled, prefetcher != nil else { return }
   140	        startPrefetch(unit: unit, epoch: epoch)
   141	    }
   142	
   143	    // MARK: - Unit-scoped retry (Feature #56 WI-13)
   144	
   145	    /// Retry one unit's translation fetch. Designed for the PDF
   146	    /// offline-state CTA — and reusable by any future per-format
   147	    /// retry affordance — when the user wants a single offline unit
   148	    /// re-fetched without nuking the rest of the book's cache.
   149	    ///
   150	    /// Removes the unit from `unavailableUnits`, clears
   151	    /// `lastTriggerUnit` only if it equals the retried unit (so the
   152	    /// next position change is not deduped), bumps the epoch, then
   153	    /// schedules a fresh prefetch via the same `startPrefetch` seam
   154	    /// `handlePositionChange` uses. Other units' translations and
   155	    /// other unavailable entries are untouched.
   156	    ///
   157	    /// Belt-and-braces: if an in-flight task already exists for the
   158	    /// retried unit (a rare race between the prefetch starting and
   159	    /// the user tapping Retry), cancel it before launching the
   160	    /// fresh one — Gate-2 v5 round-2 M2.
   161	    ///
   162	    /// No-op when bilingual is disabled or no prefetcher is attached.
   163	    func retryUnit(_ unit: TranslationUnitID) {
   164	        guard isEnabled, prefetcher != nil else { return }
   165	        if let priorTask = prefetchTasks.removeValue(forKey: unit) {
   166	            priorTask.cancel()
   167	            cancelledPrefetchTasks.append(priorTask)
   168	        }
   169	        setInFlight(inFlightUnits.subtracting([unit]))   // Feature #77 funnel
   170	        unavailableUnits.remove(unit)
   171	        if lastTriggerUnit == unit { lastTriggerUnit = nil }
   172	        epoch += 1
   173	        startPrefetch(unit: unit, epoch: epoch)
   174	    }
   175	
   176	    /// Bug #268: when the EPUB plain-text prefetch's segment count diverges from
   177	    /// the DOM leaf-enumerate's block count (nested `<pre>` / mixed-content
   178	    /// `<blockquote>` → the shared 1:1 pairing falls back to source-only),
   179	    /// translate the enumerate's OWN block texts directly so blocks↔segments are
   180	    /// 1:1 BY CONSTRUCTION. Stores the result for the unit so the next inject
   181	    /// pairs every block. A no-op when a matching-count translation already
   182	    /// exists; never worse than source-only on failure (the divergence-fallback
   183	    /// can only improve the divergent case, never regress the common one).
   184	    func translateBlocksDirectly(_ blockTexts: [String], for unit: TranslationUnitID) async {
   185	        guard isEnabled, let prefetcher, !blockTexts.isEmpty else { return }
   186	        // Already have a translation that pairs 1:1 with these blocks → nothing to do.
   187	        if let existing = translationsByUnit[unit], existing.count == blockTexts.count { return }
   188	        // Bug #343: cache-only restore FIRST — a previous run's divergence
   189	        // fallback persisted the canonical row with the enumerate's count as
   190	        // its contract, so a toggle/reopen restores with zero provider calls.
   191	        if let cached = await prefetcher.cachedSegmentsDirect(
   192	            for: unit, expectedCount: blockTexts.count, targetLanguage: targetLanguage) {
   193	            guard isEnabled else { return }
   194	            translationsByUnit[unit] = cached
   195	            postDidChange()
   196	            return
   197	        }
   198	        do {
   199	            let translated = try await prefetcher.translatedSegmentsDirect(
   200	                for: unit, sourceSegments: blockTexts, targetLanguage: targetLanguage)
   201	            guard isEnabled, translated.count == blockTexts.count else { return }
   202	            translationsByUnit[unit] = translated
   203	            postDidChange()
   204	        } catch {
   205	            // Leave the unit source-only — never worse than the current behavior.
   206	        }
   207	    }
   208	
   209	    // MARK: - Reset + notification (called from the main file's toggle setters)
   210	
   211	    /// Clears the per-unit translation cache + the unavailable set + the
   212	    /// prefetch trigger state, and bumps the epoch so any in-flight result is
   213	    /// discarded. Called on disable / language / granularity change.
   214	    func resetTriggerState() {
   215	        epoch += 1
   216	        cancelInFlightPrefetches()
   217	        translationsByUnit.removeAll()
   218	        unavailableUnits.removeAll()
   219	        lastTriggerUnit = nil
   220	    }
   221	
   222	    /// Posts `.readerBilingualDidChange` for this book so each format renderer
   223	    /// re-injects / clears its interlinear translation. The userInfo
   224	    /// carries the book's fingerprintKey (observers filter by it),
   225	    /// the current `isEnabled`, and the current `targetLanguage` so
   226	    /// chrome-layer observers (the parent reader's pill mirror, More-
   227	    /// menu row state) can paint without crossing the host boundary.
   228	    /// The renderer-side observers use `isEnabled` to decide between
   229	    /// inject and clear.
   230	    func postDidChange() {
   231	        NotificationCenter.default.post(
   232	            name: .readerBilingualDidChange, object: nil,
   233	            userInfo: [
   234	                "fingerprintKey": bookFingerprintKey,
   235	                "isEnabled": isEnabled,
   236	                "targetLanguage": targetLanguage,
   237	                // Feature #99 WI-3: the granularity rides the payload so the
   238	                // parent chrome mirror can build the More-menu settings
   239	                // sub-line ("Chinese · Paragraph · Claude").
   240	                "granularity": granularity.rawValue
   241	            ])
   242	    }
   243	
   244	    // MARK: - Private — prefetch internals
   245	
   246	    /// The outcome of one prefetch task, applied back on the main actor.
   247	    private enum PrefetchOutcome {
   248	        case success([String])
   249	        case offline
   250	        case cancelled
   251	        case failed
   252	    }
   253	
   254	    /// Launches a prefetch for one unit unless it is already cached or already
   255	    /// in flight. The task captures `epoch`; a stale result is discarded.
   256	    private func startPrefetch(unit: TranslationUnitID, epoch launchEpoch: Int) {
   257	        guard translationsByUnit[unit] == nil else { return }
   258	        guard !inFlightUnits.contains(unit) else { return }
   259	        guard let prefetcher else { return }
   260	        setInFlight(inFlightUnits.union([unit]))   // Feature #77 funnel (was insert + isFetching=true)
23:- **AI-config path (folded in — #136 CLOSED)** — the ONLY designed Android AI-config reader surface is the **Variant A scoped "AI Providers" sheet pushed inside the bilingual flow**, reached from the bilingual engine strip's "Set up"/"Change…" button (`reader-ai-provider-entry.md`). #131 now owns it end-to-end (§"AI-config reachability", WI-4b + WI-AIP + WI-9).
109:                                  pop the whole stack)
114:- **"Change…"** (already-configured strip) opens the **SAME** `ReaderAiProvidersSheet`, populated, current provider checked.
165:- `bilingual/ReaderAiProvidersSheet.kt` — **NEW (folded in; the Android analog of iOS `ReaderAIProvidersView`).** The Variant A scoped in-reader AI Providers sheet, reproducing `vreader-ai-provider-entry.jsx` `AIProvidersSheet` + `NavSheet` (nav bar `‹ Bilingual` leading + centered "AI Providers" title). It hosts **ONLY the provider list** — nothing else from settings. It **reuses the #118 `AiProviderListScreen` (list, empty + populated states) and `AiProviderEditSheet` (the canonical add/edit modal) VERBATIM**, driven by the #118 `AiSettingsViewModel` (`listState`, `editState`, `openAdd/openEdit/save/setActive`, verified `AiSettingsViewModel.kt`). Behavior per the nav model:
167:  - **Add provider** presents `AiProviderEditSheet` unchanged; **on the first Save** the new provider becomes active/the bilingual engine and the stack **pops all the way back** to the bilingual sheet with the engine strip now reading "Claude · configured / Change…". (First-provider-active is already the store's behavior — `AiProviderStore.upsert` sets `activeId = cur.activeId ?: id`, AiProviderStore.kt:81; the sheet additionally calls `store.setActive(savedId)` on the first-Save-from-bilingual path so the freshly-saved provider is the engine even if others existed.)
169:  - "Change…" opens the SAME sheet, populated, current provider checked (tapping a row → `setActive`).
211:- `VReaderApp.kt` / `AppContainer` — **provide `AiProviderStore` INTO `AppContainer` itself** (it is NOT provided today — verified, only a comment names it at VReaderApp.kt:66) using the #116 `KeystoreSecretCipher` + a DataStore under the same convention as `readerSettingsStore`, PLUS provide `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, an `AiSettingsViewModel` factory (for the Variant A sheet), and a `BilingualViewModel` factory. **Extracted into the shared DI WI (WI-4b).** No `feat:#136` dependency remains — #131 owns the `AiProviderStore`-into-`AppContainer` wiring.
259:The canonical decision (`reader-ai-provider-entry.md`, Variant A) + its component canvas (`vreader-ai-provider-entry.jsx`) ARE the committed design; #131 reproduces only what they depict (a `‹ Bilingual`-titled push sheet hosting the #118 provider list + the canonical editor, pop-back-on-first-save). No AI-config sheet or nav is invented. The iOS #82 readiness additions (flag/consent) are explicitly **out** on Android (no such subsystems exist). This is a designed surface — it is NOT a design gate.
272:**13 WIs/PRs (round-3 Low-1 fix — corrected count):** the list is exactly **WI-0, WI-1, WI-2, WI-3, WI-4a, WI-4b, WI-5, WI-6, WI-7a, WI-7b, WI-AIP, WI-8, WI-9** = **13 WIs**. (v3 had 12: WI-0,1,2,3,4a,4b,5,6,7a,7b,8,9. Folding in the Variant A "AI Providers" sheet adds **WI-AIP**, making 13. The prior "11 WIs" claim in the plan header and `docs/features.md` was wrong on two counts and is corrected here.) Each WI = one PR. Build order: **foundation/cache → service/direct-block APIs → shared DI/factory (incl. `AiProviderStore` in `AppContainer`) → VM state/prefetch → host-specific renderers (TXT/MD + EPUB) + the Variant A AI Providers sheet → entry wiring.**
277:- **WI-4b is foundational and gates the behavioral chain.** WI-4b now provides `AiProviderStore` into `AppContainer` PLUS the bilingual services + factories. Per the audit's Medium-4, WI-4b transitively gates WI-6 (needs the prefetcher/DI), WI-7b (needs DI), WI-AIP (needs `AiProviderStore` + `AiSettingsViewModel` from `AppContainer`), and WI-8 (needs DI). **Chosen resolution: injected seams so the behavioral work proceeds against fakes before WI-4b lands, AND WI-4b is sequenced early.** Concretely: the VM (WI-5/WI-6) takes an injected `ChapterTranslationPrefetcher` (fake in tests) and an injected `AiProviderSnapshot` provider (fake); the TXT/MD host Compose/unit work (WI-8) and the Variant A sheet (WI-AIP) take injected VM/store/`AiSettingsViewModel` seams — so unit/Compose tests do not wait on `AppContainer`. **WI-4b is built right after WI-4a (before WI-6/WI-7b/WI-AIP/WI-8) so the production wiring lands before the host integrations that mount it.** This is stated honestly: the *production run-through* of WI-6/WI-7b/WI-AIP/WI-8 depends on WI-4b; their *unit/Compose gates* depend only on the injected seams. No external feature gates any of this.
289:**WI-4b (foundational — shared DI/factory, incl. `AiProviderStore` in `AppContainer`): AppContainer bilingual + AI-config graph.** `AppContainer` **now constructs `AiProviderStore`** (DataStore + #116 `KeystoreSecretCipher`, following the `readerSettingsStore` convention — this is #131's change, not an external feature's) and provides `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, an `AiSettingsViewModel` factory (for WI-AIP), and the `BilingualViewModel` factory. Deps: **WI-4a** (no external dep — #136 closed). Tests: container resolves the bilingual + AI-config graph; `AiProviderStore` resolves and round-trips a profile; the prefetcher's injected factory defaults to `AiProviderFactory::create`.
293:**WI-6 (behavioral): VM prefetch trigger + generation/cancellation + single-flight (M2).** `onPositionChanged(charOffsetUTF16)` derives current unit (TXT/MD only), dedupes, prefetches current+next; a monotonic position-request sequence checked after every suspension; **per-unit single-flight `prefetchTasks: Map<TranslationUnitId, Job>` (a new request cancels/joins the prior — M2)**; a captured language/granularity/provider snapshot per launch; generation bumps on disable/language/granularity/unit-change discard stale; **BOTH `CancellationException` AND typed `ChapterTranslationError.Cancelled` handled BEFORE generic error mapping (M2)**; a cancelled stale request does NOT surface as `errorUnit`; `Offline`→`unavailableUnits`; transient failure leaves unit unfetched + clears anchor to retry; `retryUnit` routes through the registry. The EPUB `onEpubBlocksEnumerated` entry is present but EPUB prefetch is owned by the controller (Medium-1); the VM's position-driven `prefetch` dispatches TXT/MD units only. Fake prefetcher (Medium-4 seam). Deps: WI-4a, WI-4b, WI-5. Tests: current+next on unit change; same-unit no-op; cancel-mid discards stale (no `errorUnit`); typed-`Cancelled` discards (not `errorUnit`); rapid re-trigger same unit → single-flight, no double-write; offline→unavailable; failure→retry-able; `retryUnit` re-fetches; granularity change cancels + re-fetches under the new key.
297:**WI-7b (behavioral, CONDITIONAL — only if WI-0 = go): EPUB render adapter (DOM injection, NOT Compose — M2) + direct-block ownership (M1).** `EpubBilingualJs` (enum/inject/clear JS builders, CSP-safe escaping) + `EpubBilingualController` (the serialization actor / session token AND the **single-owner enumerate→cachedDirect/prefetchDirect→guarded-commit sequence — Medium-1**) + `EpubChapterTextProvider`, wired into `ReaderActivity`, driving DOM from the shared `BilingualRenderState` DTO. Uses `prefetchDirect`/`cachedDirect` for the count-divergence path (H2). Depends on WI-6 (VM state) and WI-4b (DI); the WI-7a UI dependency is only the shared `BilingualRenderState`/value types. Connected test on a real EPUB (seeded cache): enable → injects; disable → cleared; reflow/href-change/fragment-recreation/activity-recreation → re-applies from cache (zero provider calls) via `cachedDirect`; count-divergence handled (direct path); **the regular TXT/MD prefetch path is never invoked for an EPUB unit (Medium-1)**. Unit tests: JS escaping/CSP-safe insertion, RTL/CJK style, empty translations, loading cleanup, idempotent replacement, source-only fallback, stale-session-token commit discarded (no `errorUnit`). Deps: WI-0, WI-3, WI-4a, WI-4b, WI-6, (shared types from WI-7a). (If WI-0 = no-go, dropped; box D ships TXT/MD-only, tracked.)
299:**WI-AIP (behavioral — the folded-in Variant A AI Providers sheet): `ReaderAiProvidersSheet`.** The scoped in-reader "AI Providers" push sheet (nav bar `‹ Bilingual` + "AI Providers" title) reproducing `vreader-ai-provider-entry.jsx` `AIProvidersSheet`/`NavSheet`, hosting ONLY the #118 `AiProviderListScreen` (empty + populated) + the canonical `AiProviderEditSheet`, driven by the #118 `AiSettingsViewModel` (from WI-4b's `AppContainer` factory). Empty state carries the bilingual-context copy ("Bilingual mode needs a provider to translate" / "Add provider" CTA). On first Save → the provider becomes the bilingual engine (`store.setActive(savedId)`) + pop the whole stack back to the bilingual sheet (engine strip now "configured / Change…"). `‹ Bilingual` without adding → unconfigured, no state mutated. No consent/flag surface (Android has none). Deps: WI-4b (for `AiProviderStore` + `AiSettingsViewModel` in `AppContainer`), WI-7a (bilingual sheet host). Tests (Compose + connected): empty → Add → Save → pop-to-bilingual with strip configured; `‹ Bilingual` without adding → strip unconfigured, snapshot unchanged; "Change…" → populated list, current provider checked, tap row → `setActive`; editor reused verbatim (no divergent form).
301:**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into the `items(count = document.chunkCount)` loop as **additive translation items after the anchor chunk, source chunks byte-unchanged (H2)** + position-change (`charOffsetUTF16`) + setup-sheet. `originalFormat`-gated (TXT/MD). Uses WI-4b's DI. **#129 VERIFIED — straight edit.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2)**; **highlights/annotation-washes/read-aloud-wash still key off source chunks (H2)**; a translation item is non-selectable, does not perturb source offsets (H2); disable → source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders exactly one translation after its last chunk (H1/Low-2)**; **one-chunk/final-chunk anchors render (H1)**; MD source mapping. Deps: WI-6, WI-7a, WI-4b.
303:**WI-9 (behavioral): entry wiring + acceptance.** Mount `BilingualPill` in #132's VERIFIED top chrome; extend `readerMoreRows(...)` to supply the #134 VERIFIED More-menu `MoreActionId.BILINGUAL` toggle (`MoreRow.Toggle` `on`/`onToggle`, or `MoreRow.Disabled` "Configure AI provider first" when not configured) wired to the VM; **wire the setup sheet's "Set up"/"Change…" affordance → the #131-owned `ReaderAiProvidersSheet` (Variant A)**. Full acceptance across EPUB (if WI-7b landed) + TXT/MD, including the fresh-user path `unconfigured → Set up (→ Variant A AI Providers sheet) → add provider → return → enable → translate` (now #131-owned end-to-end). **Flip box D to done ONLY for provider/model/granularity + the Style-descope note; file the follow-up checklist amendment; do NOT claim full box-D parity.** The DONE flip **no longer waits on #136** (closed). Update `docs/architecture.md` (bilingual pipeline + the new `chapter_translations` schema + `AiProviderStore` + bilingual services in `AppContainer` + the Variant A AI Providers sheet). → DONE. Deps: WI-8, WI-AIP, WI-7b (if go), feat:#132, feat:#134.
311:Compose UI (`androidTest/...bilingual/`): `BilingualSetupSheetUiTest` (language grid, granularity, preview, engine configured vs unconfigured driven by `aiConfigured`; no Style control present; light+dark); `BilingualInterlinearBodyUiTest` (**additive translation item after a paragraph anchor chunk (depicted); paragraph interlinear translated incl. CJK font + RTL Arabic; Sentence selection → paragraph-render fallback (H2 gate)**; loading N%+dimmed; error+Retry; offline source-only; empty translation→source-only no crash); `ReaderAiProvidersSheetUiTest` (**empty state with bilingual-context copy + Add CTA; populated list + current-provider checked; `‹ Bilingual` back label; editor reused (WI-AIP)**); `BilingualPillUiTest`.
313:Connected (`androidTest/...reader/`): `TxtReaderBilingualConnectedTest` (API 35, fake `AiClient` via injected factory): enable→setup→confirm→interlinear from seeded Room cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2); highlights/annotation-washes/read-aloud-wash still key off source chunks (H2); translation item non-selectable + no source-offset perturbation (H2)**; disable→source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders one translation (H1/Low-2); one-chunk/final-chunk anchors render (H1)**; TXT/MD gated (PDF inert); very long chapter scroll responsive; cancellation leaves no partial cache row. `ReaderAiProvidersConnectedTest` (WI-AIP + WI-9): `unconfigured → Set up → Variant A sheet → add provider → Save → pop-to-bilingual configured → enable → translate`; `‹ Bilingual` without adding → unconfigured, snapshot unchanged; "Change…" → populated, current checked. `EpubReaderBilingualConnectedTest` (only if WI-0=go): enable→inject on a real EPUB; disable→clear; href-change/fragment-recreation/activity-recreation→re-apply from cache (zero provider calls); count-divergence handled via `prefetchDirect`/`cachedDirect`; regular prefetch never runs for EPUB unit (Medium-1).
319:- **Live-translation verification is AI-credential-gated (the box-D caveat).** The whole pipeline is verified without live creds via a deterministic **fake `AiClient`** injected through the prefetcher's `clientFactory` param (default `AiProviderFactory::create`; tests override). WI-3/4a/8 prove segment→chunk→decode→cache→interleave end-to-end incl. every error/edge path. Connected tests seed the Room cache and assert render-from-cache with zero client calls. An optional live smoke confirms wire format but is NOT a gate. The fresh-user `unconfigured → Set up → add provider` reachability leg is now #131-owned (WI-AIP + WI-9) and verified by `ReaderAiProvidersConnectedTest`.
332:- **Dependency honesty (round-3 Medium-4).** WI-4b (DI, incl. `AiProviderStore` in `AppContainer`) is foundational and gates the production run-through of WI-6/WI-7b/WI-AIP/WI-8; those WIs' unit/Compose gates proceed against injected fakes, and WI-4b is sequenced before them. No external feature gates the chain (#136 closed).
348:*(REMOVED: the v3 "#136 dependency" design-gate line — #136 is closed and the Variant A AI Providers sheet IS the committed design, reproduced by WI-AIP, not a gate.)*
356:  - **AI-config FOLDED IN (#136 CLOSED, GH #1976 not-planned; user decision 2026-07-12):** the design proved the ONLY designed Android AI-config reader surface is the bilingual-coupled **Variant A** "AI Providers" sheet (`reader-ai-provider-entry.md`); it is not separable, so #131 now owns it end-to-end. Added **WI-AIP** (`ReaderAiProvidersSheet`, reusing #118 `AiProviderListScreen`/`AiProviderEditSheet`/`AiSettingsViewModel` verbatim, `‹ Bilingual` push, pop-back-on-first-Save); WI-4b now provides `AiProviderStore` into `AppContainer` (verified not provided today — VReaderApp.kt:66 comment only) plus the bilingual services + `AiSettingsViewModel` factory; removed `feat:#136` from Deps (now `[feat:#132, feat:#134]`, no external AI-reachability blocker); the DONE flip no longer waits on #136; `aiConfigured` derivation kept as the correct active-profile+decrypts-non-empty gate (H3), NOT `profiles.isEmpty()` (the iOS note's derivation), with no consent/flag gate (Android has none).
362:  - **M4 (round-3 Medium-4) dependency honesty:** WI-4b (DI incl. `AiProviderStore`) is foundational and gates the production run-through of WI-6/WI-7b/WI-AIP/WI-8; those WIs' unit/Compose gates use injected fakes; WI-4b sequenced before them; no external feature gates the chain.
363:  - **Low fixes:** WI count corrected to **13** (added WI-AIP; the "11 WIs" claim was wrong — Low-1); chunk semantics corrected — a chunk is ONE LINE, holds multiple SENTENCES, a paragraph spans MANY chunks; removed the "a chunk can hold multiple paragraphs" claim (Low-2). Awaiting Gate-2 round-4 audit.

codex
## Critical

None.

## High

1. **H1 is not fully resolved: the plan still specifies `List<IntRange>` for half-open ranges.**

The v4 correction correctly identifies that Kotlin `IntRange` is inclusive-inclusive and requires explicit `(start, endExclusive)` pairs ([plan:49](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:49), [plan:61](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:61)). However, the proposed `ChapterSegmenter` API still declares `paragraphRanges` / `sentenceRanges` as `List<IntRange>` while calling them half-open ([plan:126](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:126), [plan:281](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:281)).

Those contracts are mutually incompatible. Replace `IntRange` everywhere with a dedicated type such as `Utf16Span(start, endExclusive)`.

The underlying math itself is correct:

- `offsetForChunk` clamps `i + 1` to the final chunk start ([TxtDocument.kt:17](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:17)).
- `textForChunk` proves the required final-end behavior by using `text.length` ([TxtDocument.kt:36](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:36)).
- `chunkForOffset(endExclusive - 1)` correctly anchors non-empty half-open spans ([TxtDocument.kt:23](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:23)).

Therefore one-chunk, final-chunk, exact-boundary, and EOF anchors are correct only after the remaining `IntRange` API contradiction is removed.

2. **H2 remains blocked: separate additive lazy items break the reader’s chunk-index identity.**

The live reader treats `LazyListState` item indices as `TxtDocument` chunk indices throughout:

- Position saving converts `firstVisibleItemIndex` directly through `offsetForChunk` ([TxtReaderActivity.kt:220](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:220), [TxtReaderActivity.kt:623](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:623)).
- Bookmark, annotation, search, scrubber, and TTS jumps call `scrollToItem(chunkForOffset(...))` ([TxtReaderActivity.kt:404](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:404), [TxtReaderActivity.kt:470](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:470)).
- TTS visibility compares lazy-item indices directly with `spokenChunk` ([TxtReaderActivity.kt:252](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:252)).

Inserting separate translation lazy items shifts every following lazy index, corrupting these mappings. Conversely, composables emitted inside the existing `items(count=chunkCount)` lambda are part of the same lazy item, not separately keyed `LazyColumn` items. Thus the plan’s claim that the existing loop remains byte-identical while separately keyed lazy items are inserted inside it is not implementable as written ([plan:70](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:70), [plan:208](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:208)).

The source-`Text` preservation portion is correct: one unchanged `Text` retains one layout and one chunk registration ([TxtReaderActivity.kt:1043](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1043), [TxtReaderActivity.kt:1059](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1059), [TxtReaderActivity.kt:1062](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1062)). But the plan must choose one viable implementation:

- Keep exactly one lazy item per chunk and put the unchanged source `Text` plus translations in a containing `Column`; or
- Introduce an explicit lazy-index↔chunk-index mapping and update every position/jump/TTS consumer.

The first is substantially safer. It also needs an explicit gesture exclusion because long-press selection currently falls back to the nearest registered source chunk when the pointer is outside source bounds ([TxtSelectionController.kt:43](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:43)); merely omitting translation registration does not make translation text non-selectable.

3. **The Sentence fallback is underspecified and not yet sound.**

The design evidence is correctly characterized: `BilingualPageContent` maps paragraphs and renders one translation paragraph per source paragraph ([vreader-bilingual.jsx:195](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx:195), [vreader-bilingual.jsx:241](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx:241)); Sentence appears only in the setup control ([vreader-bilingual.jsx:77](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx:77)).

However, v4 says Sentence remains selectable, sentence segmentation/cache identity remains active, but rendering falls back to paragraphs ([plan:82](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:82)). It never defines how multiple sentence translations are deterministically reassembled into one paragraph translation or how sentence spans map back to paragraph spans. Without that shaping contract, implementation either renders sentence items—the prohibited undesigned surface—or serves paragraph-shaped content under a sentence cache key.

For v1, specify deterministic sentence-result aggregation into the containing paragraph, with tests for punctuation, whitespace, multiline paragraphs, CJK, and RTL; otherwise constrain v1 to Paragraph.

4. **FOLD-IN is not wireable “verbatim” against the live #118 UI/ViewModel.**

`AiProviderListScreen` already owns a full `NavScreen`, generic empty-state copy, and row-tap-as-edit behavior ([AiProviderListScreen.kt:45](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:45), [AiProviderListScreen.kt:59](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:59), [AiProviderListScreen.kt:84](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:84), [AiProviderListScreen.kt:101](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:101)). It cannot simultaneously be reused verbatim and reproduce the designed reader-scoped navigation, bilingual-context empty state, checked active row, and tap-to-select behavior ([reader-ai-provider-entry.md:39](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:39), [vreader-ai-provider-entry.jsx:162](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:162)).

Additionally, `AiSettingsViewModel.save()` returns no saved ID and performs `upsert` asynchronously ([AiSettingsViewModel.kt:85](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:85)). Therefore WI-AIP cannot perform the promised `setActive(savedId)` followed by pop-on-success while reusing that ViewModel verbatim. Popping immediately would race persistence; observing list state cannot reliably distinguish the newly saved profile from unrelated updates.

The canonical editor can be reused verbatim, but the scoped list must be a new reader-specific presentation over shared state/components, and saving needs a completion/result seam returning the saved ID.

## Medium

No additional blockers.

Round-3 resolution status:

- **M1 EPUB ownership: resolved.** The controller-only enumerate → cache/direct-prefetch → token-guarded commit flow is coherent, and excluding EPUB kinds from position-driven VM prefetch prevents two planned writers for one canonical row ([plan:181](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:181), [plan:197](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:197)). WI-0 must still prove token lifetime across fragment/activity recreation.
- **M2 cancellation: resolved.** Native and typed cancellation are ordered before generic mapping, and cancel-and-join single-flight is sound. The cited iOS dual catch and task registry exist ([ChapterTranslationService.swift:359](/Users/ll/workspace/vreader/vreader/Services/AI/ChapterTranslationService.swift:359), [BilingualReadingViewModel.swift:138](/Users/ll/workspace/vreader/vreader/ViewModels/BilingualReadingViewModel.swift:138)).
- **M3 blank model: resolved.** The fallback matches live precedent ([AiChatViewModel.kt:61](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt:61)); both providers serialize `request.model` directly ([OpenAiCompatibleProvider.kt:38](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/OpenAiCompatibleProvider.kt:38), [AnthropicProvider.kt:36](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AnthropicProvider.kt:36)).
- **M4 dependency sequencing: resolved.** WI-4b is placed before the production integrations that consume it.

## Low

- `AppContainer` indeed has no live `AiProviderStore`; the cited occurrence is only a comment ([VReaderApp.kt:64](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:64)). Constructing it there is appropriate.
- `aiConfigured = active profile + successfully decrypted non-blank key`, with cipher failure mapped to false, is correct. Profiles can exist without an active match ([AiProviderStore.kt:34](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:34)), and decrypt can fail at `apiKey(profile)` ([AiProviderStore.kt:105](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:105)).
- `AiProviderStore.upsert` already activates the first-ever provider ([AiProviderStore.kt:81](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:81)); explicit activation is needed only when adding through this flow while other profiles already exist.
- Dependencies `[feat:#132, feat:#134]` and the enumerated count of 13 WIs are arithmetically correct ([plan:270](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:270), [docs/features.md:184](/Users/ll/workspace/vreader/docs/features.md:184)).

FINAL VERDICT: block-recommended
tokens used
110,315
## Critical

None.

## High

1. **H1 is not fully resolved: the plan still specifies `List<IntRange>` for half-open ranges.**

The v4 correction correctly identifies that Kotlin `IntRange` is inclusive-inclusive and requires explicit `(start, endExclusive)` pairs ([plan:49](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:49), [plan:61](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:61)). However, the proposed `ChapterSegmenter` API still declares `paragraphRanges` / `sentenceRanges` as `List<IntRange>` while calling them half-open ([plan:126](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:126), [plan:281](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:281)).

Those contracts are mutually incompatible. Replace `IntRange` everywhere with a dedicated type such as `Utf16Span(start, endExclusive)`.

The underlying math itself is correct:

- `offsetForChunk` clamps `i + 1` to the final chunk start ([TxtDocument.kt:17](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:17)).
- `textForChunk` proves the required final-end behavior by using `text.length` ([TxtDocument.kt:36](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:36)).
- `chunkForOffset(endExclusive - 1)` correctly anchors non-empty half-open spans ([TxtDocument.kt:23](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:23)).

Therefore one-chunk, final-chunk, exact-boundary, and EOF anchors are correct only after the remaining `IntRange` API contradiction is removed.

2. **H2 remains blocked: separate additive lazy items break the reader’s chunk-index identity.**

The live reader treats `LazyListState` item indices as `TxtDocument` chunk indices throughout:

- Position saving converts `firstVisibleItemIndex` directly through `offsetForChunk` ([TxtReaderActivity.kt:220](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:220), [TxtReaderActivity.kt:623](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:623)).
- Bookmark, annotation, search, scrubber, and TTS jumps call `scrollToItem(chunkForOffset(...))` ([TxtReaderActivity.kt:404](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:404), [TxtReaderActivity.kt:470](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:470)).
- TTS visibility compares lazy-item indices directly with `spokenChunk` ([TxtReaderActivity.kt:252](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:252)).

Inserting separate translation lazy items shifts every following lazy index, corrupting these mappings. Conversely, composables emitted inside the existing `items(count=chunkCount)` lambda are part of the same lazy item, not separately keyed `LazyColumn` items. Thus the plan’s claim that the existing loop remains byte-identical while separately keyed lazy items are inserted inside it is not implementable as written ([plan:70](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:70), [plan:208](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:208)).

The source-`Text` preservation portion is correct: one unchanged `Text` retains one layout and one chunk registration ([TxtReaderActivity.kt:1043](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1043), [TxtReaderActivity.kt:1059](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1059), [TxtReaderActivity.kt:1062](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1062)). But the plan must choose one viable implementation:

- Keep exactly one lazy item per chunk and put the unchanged source `Text` plus translations in a containing `Column`; or
- Introduce an explicit lazy-index↔chunk-index mapping and update every position/jump/TTS consumer.

The first is substantially safer. It also needs an explicit gesture exclusion because long-press selection currently falls back to the nearest registered source chunk when the pointer is outside source bounds ([TxtSelectionController.kt:43](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:43)); merely omitting translation registration does not make translation text non-selectable.

3. **The Sentence fallback is underspecified and not yet sound.**

The design evidence is correctly characterized: `BilingualPageContent` maps paragraphs and renders one translation paragraph per source paragraph ([vreader-bilingual.jsx:195](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx:195), [vreader-bilingual.jsx:241](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx:241)); Sentence appears only in the setup control ([vreader-bilingual.jsx:77](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx:77)).

However, v4 says Sentence remains selectable, sentence segmentation/cache identity remains active, but rendering falls back to paragraphs ([plan:82](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:82)). It never defines how multiple sentence translations are deterministically reassembled into one paragraph translation or how sentence spans map back to paragraph spans. Without that shaping contract, implementation either renders sentence items—the prohibited undesigned surface—or serves paragraph-shaped content under a sentence cache key.

For v1, specify deterministic sentence-result aggregation into the containing paragraph, with tests for punctuation, whitespace, multiline paragraphs, CJK, and RTL; otherwise constrain v1 to Paragraph.

4. **FOLD-IN is not wireable “verbatim” against the live #118 UI/ViewModel.**

`AiProviderListScreen` already owns a full `NavScreen`, generic empty-state copy, and row-tap-as-edit behavior ([AiProviderListScreen.kt:45](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:45), [AiProviderListScreen.kt:59](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:59), [AiProviderListScreen.kt:84](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:84), [AiProviderListScreen.kt:101](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:101)). It cannot simultaneously be reused verbatim and reproduce the designed reader-scoped navigation, bilingual-context empty state, checked active row, and tap-to-select behavior ([reader-ai-provider-entry.md:39](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:39), [vreader-ai-provider-entry.jsx:162](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:162)).

Additionally, `AiSettingsViewModel.save()` returns no saved ID and performs `upsert` asynchronously ([AiSettingsViewModel.kt:85](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:85)). Therefore WI-AIP cannot perform the promised `setActive(savedId)` followed by pop-on-success while reusing that ViewModel verbatim. Popping immediately would race persistence; observing list state cannot reliably distinguish the newly saved profile from unrelated updates.

The canonical editor can be reused verbatim, but the scoped list must be a new reader-specific presentation over shared state/components, and saving needs a completion/result seam returning the saved ID.

## Medium

No additional blockers.

Round-3 resolution status:

- **M1 EPUB ownership: resolved.** The controller-only enumerate → cache/direct-prefetch → token-guarded commit flow is coherent, and excluding EPUB kinds from position-driven VM prefetch prevents two planned writers for one canonical row ([plan:181](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:181), [plan:197](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:197)). WI-0 must still prove token lifetime across fragment/activity recreation.
- **M2 cancellation: resolved.** Native and typed cancellation are ordered before generic mapping, and cancel-and-join single-flight is sound. The cited iOS dual catch and task registry exist ([ChapterTranslationService.swift:359](/Users/ll/workspace/vreader/vreader/Services/AI/ChapterTranslationService.swift:359), [BilingualReadingViewModel.swift:138](/Users/ll/workspace/vreader/vreader/ViewModels/BilingualReadingViewModel.swift:138)).
- **M3 blank model: resolved.** The fallback matches live precedent ([AiChatViewModel.kt:61](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt:61)); both providers serialize `request.model` directly ([OpenAiCompatibleProvider.kt:38](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/OpenAiCompatibleProvider.kt:38), [AnthropicProvider.kt:36](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AnthropicProvider.kt:36)).
- **M4 dependency sequencing: resolved.** WI-4b is placed before the production integrations that consume it.

## Low

- `AppContainer` indeed has no live `AiProviderStore`; the cited occurrence is only a comment ([VReaderApp.kt:64](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:64)). Constructing it there is appropriate.
- `aiConfigured = active profile + successfully decrypted non-blank key`, with cipher failure mapped to false, is correct. Profiles can exist without an active match ([AiProviderStore.kt:34](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:34)), and decrypt can fail at `apiKey(profile)` ([AiProviderStore.kt:105](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:105)).
- `AiProviderStore.upsert` already activates the first-ever provider ([AiProviderStore.kt:81](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:81)); explicit activation is needed only when adding through this flow while other profiles already exist.
- Dependencies `[feat:#132, feat:#134]` and the enumerated count of 13 WIs are arithmetically correct ([plan:270](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:270), [docs/features.md:184](/Users/ll/workspace/vreader/docs/features.md:184)).

FINAL VERDICT: block-recommended
